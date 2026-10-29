import 'dart:async';
import 'dart:math' as math;

import 'package:bdo_craft_planner_flutter/visual/components/app_tooltip.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/state/planner_application_controller.dart';
import '../../app/window/window_host_service.dart';
import '../../domain/formatting/planner_formatters.dart';
import '../../shared/overlays/draggable_overlay_surface.dart';
import '../../visual/visual.dart';
import 'inventory_amount_input_formatter.dart';
import 'inventory_screenshot_recognition.dart';

enum InventoryScreenshotSaveMode { update, add }

final class InventoryScreenshotReview {
  InventoryScreenshotReview({
    required this.saveMode,
    required Map<String, double> quantities,
  }) : quantities = Map<String, double>.unmodifiable(quantities);

  final InventoryScreenshotSaveMode saveMode;
  final Map<String, double> quantities;
}

typedef AcquireAdditionalInventoryScreenshot =
    Future<InventoryScreenshotAnalysis?> Function();
typedef _OrderCandidate = ({String name, int itemId, double utility});
typedef _OrderState = ({double score, List<String?> choices});

Future<InventoryScreenshotReview?> showInventoryScreenshotImportDialog(
  BuildContext context, {
  required ModeFeatureController controller,
  required InventoryScreenshotAnalysis analysis,
  AcquireAdditionalInventoryScreenshot? pasteAnother,
  AcquireAdditionalInventoryScreenshot? chooseAnother,
  WindowHostService windowHost = const WindowHostService(),
}) => showDialog<InventoryScreenshotReview>(
  context: context,
  barrierDismissible: false,
  builder: (context) => DraggableModalRouteSurface(
    overlayId: 'inventory-screenshot-review',
    insetPadding: const EdgeInsets.all(16),
    child: _InventoryScreenshotImportDialog(
      controller: controller,
      analysis: analysis,
      pasteAnother: pasteAnother,
      chooseAnother: chooseAnother,
      windowHost: windowHost,
    ),
  ),
);

class _InventoryScreenshotImportDialog extends StatefulWidget {
  const _InventoryScreenshotImportDialog({
    required this.controller,
    required this.analysis,
    required this.pasteAnother,
    required this.chooseAnother,
    required this.windowHost,
  });

  final ModeFeatureController controller;
  final InventoryScreenshotAnalysis analysis;
  final AcquireAdditionalInventoryScreenshot? pasteAnother;
  final AcquireAdditionalInventoryScreenshot? chooseAnother;
  final WindowHostService windowHost;

  @override
  State<_InventoryScreenshotImportDialog> createState() =>
      _InventoryScreenshotImportDialogState();
}

class _InventoryScreenshotImportDialogState
    extends State<_InventoryScreenshotImportDialog> {
  static const int _maximumScreenshots = 8;
  static const int _maximumSessionBytes = 48 * 1024 * 1024;
  static const double _rowExtent = 72;
  static const double _rowSpacing = 10;
  static const int _saltItemId = 9001;
  static const int _sunDriedSaltItemId = 9008;
  static const String _saltOrderFamily = 'items:9001,9008';
  static const double _automaticVisualAlternativeWindow = .04;
  static const double _automaticVisualFamilyBonus = .04;
  static const double _automaticSourceSelectionBonus = .025;
  static const double _automaticFallbackVisualScore = .82;
  static const Set<String> _verifiedAutomaticOrderGroups = <String>{
    'blood:all',
    'meat:all',
    'dried-fish',
    'mushroom:big',
    'sap:tree',
    'hide:raw',
  };

  final List<_ReviewRow> _rows = <_ReviewRow>[];
  final List<_ReviewRow> _removed = <_ReviewRow>[];
  final List<_HiddenReviewSource> _nativeHidden = <_HiddenReviewSource>[];
  final Set<String> _fingerprints = <String>{};
  final Set<String> _rowIds = <String>{};
  final List<String> _itemNames = <String>[];
  final Map<String, int> _itemIdsByName = <String, int>{};
  final Map<String, String> _itemOrderGroupsByName = <String, String>{};
  final Map<String, int> _screenshotOrderByFingerprint = <String, int>{};
  final ScrollController _rowScrollController = ScrollController();
  // A screenshot normally represents one more character/city inventory. New
  // reviews therefore add to the shared inventory by default. Replacing the
  // current inventory remains an explicit destructive choice in the dialog.
  InventoryScreenshotSaveMode _saveMode = InventoryScreenshotSaveMode.add;
  bool _busy = false;
  bool _submitting = false;
  int _sourceBytes = 0;
  int _gridColumns = 1;
  int _validationPulse = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _appendAnalysis(widget.analysis, initial: true);
  }

  @override
  void dispose() {
    for (final row in <_ReviewRow>[..._rows, ..._removed]) {
      row.dispose();
    }
    _rowScrollController.dispose();
    super.dispose();
  }

  void _appendAnalysis(
    InventoryScreenshotAnalysis analysis, {
    bool initial = false,
  }) {
    final fingerprint = analysis.draft.imageFingerprint.toLowerCase();
    final screenshotOrder = _fingerprints.length;
    if (!_fingerprints.add(fingerprint)) {
      if (!initial) _error = 'That screenshot is already in this review.';
      return;
    }
    _screenshotOrderByFingerprint[fingerprint] = screenshotOrder;
    _sourceBytes += analysis.sourceByteCount;
    final knownNames = <String>{for (final name in _itemNames) _fold(name)};
    for (final name in analysis.plannerItemNames) {
      if (knownNames.add(_fold(name))) _itemNames.add(name);
    }
    _itemNames.sort(_compareNames);
    for (final entry in analysis.plannerItemIds.entries) {
      _itemIdsByName.putIfAbsent(_fold(entry.key), () => entry.value);
    }
    for (final entry in analysis.plannerItemOrderGroups.entries) {
      _itemOrderGroupsByName.putIfAbsent(_fold(entry.key), () => entry.value);
    }
    for (final source in analysis.draft.rows) {
      if (!_rowIds.add('$fingerprint:${source.id}')) continue;
      final row = _ReviewRow(
        source,
        screenshotFingerprint: fingerprint,
        screenshotOrder: screenshotOrder,
      );
      for (final match in source.matches) {
        if (match.itemId case final itemId?) {
          _itemIdsByName.putIfAbsent(_fold(match.name), () => itemId);
        }
      }
      _rows.add(row);
    }
    for (final hidden in analysis.draft.hiddenRows) {
      if (_rowIds.add('$fingerprint:${hidden.id}')) {
        _nativeHidden.add(
          _HiddenReviewSource(
            source: hidden,
            screenshotFingerprint: fingerprint,
            screenshotOrder: screenshotOrder,
          ),
        );
      }
    }
    _rows.sort(_compareRows);
    _reconcileAutomaticSelections();
  }

  Future<void> _addScreenshot(
    AcquireAdditionalInventoryScreenshot acquire,
  ) async {
    if (_busy || _fingerprints.length >= _maximumScreenshots) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final analysis = await acquire();
      if (!mounted || analysis == null) return;
      if (_sourceBytes + analysis.sourceByteCount > _maximumSessionBytes) {
        setState(() {
          _error = 'This review already contains 48 MB of screenshots.';
        });
        return;
      }
      setState(() => _appendAnalysis(analysis));
    } on Object catch (error) {
      if (mounted) {
        setState(() => _error = 'That screenshot could not be added. $error');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _removeRow(_ReviewRow row) {
    setState(() {
      _rows.remove(row);
      _removed.add(row);
      _reconcileAutomaticSelections();
      _error = null;
    });
  }

  void _restoreLastRemoved() {
    if (_removed.isEmpty) return;
    setState(() {
      final row = _removed.removeLast();
      _rows.add(row);
      _rows.sort(_compareRows);
      _reconcileAutomaticSelections();
      _error = null;
    });
  }

  void _showHiddenRows() {
    if (_nativeHidden.isEmpty) return;
    setState(() {
      for (final hidden in _nativeHidden) {
        _rows.add(
          _ReviewRow(
            hidden.source,
            screenshotFingerprint: hidden.screenshotFingerprint,
            screenshotOrder: hidden.screenshotOrder,
          ),
        );
      }
      _nativeHidden.clear();
      _rows.sort(_compareRows);
      _reconcileAutomaticSelections();
      _error = null;
    });
  }

  void _selectItem(_ReviewRow row, String name) {
    setState(() {
      row.select(name, fixed: true);
      _releaseLaterProvisionalSelections(row, name);
      _reconcileAutomaticSelections();
      _error = null;
    });
  }

  void _releaseLaterProvisionalSelections(_ReviewRow anchor, String name) {
    final family = _itemIdOrderFamilyForName(anchor, name);
    final screenshotRows =
        _rows
            .where(
              (row) =>
                  row.screenshotFingerprint == anchor.screenshotFingerprint,
            )
            .toList(growable: false)
          ..sort(_compareRows);
    final anchorIndex = screenshotRows.indexOf(anchor);
    if (anchorIndex < 0) return;

    if (family != null) {
      var first = anchorIndex;
      while (first > 0 &&
          _itemIdOrderFamily(screenshotRows[first - 1]) == family) {
        first -= 1;
      }
      var last = anchorIndex;
      while (last + 1 < screenshotRows.length &&
          _itemIdOrderFamily(screenshotRows[last + 1]) == family) {
        last += 1;
      }
      for (var index = first; index <= last; index += 1) {
        final candidate = screenshotRows[index];
        if (!identical(candidate, anchor) && !candidate.selectionFixed) {
          candidate.clearSelection(clearText: true, suppressAutoFill: false);
        }
      }
    }

    // A provisional automatic owner must never hide the user's correction,
    // whether it currently sits before or after this row. Releasing it here
    // transfers the name to the manual choice and lets the complete family
    // reflow against every fixed anchor during reconciliation.
    for (final candidate in screenshotRows) {
      final selected = candidate.selectedName;
      if (!identical(candidate, anchor) &&
          !candidate.selectionFixed &&
          selected != null &&
          _same(selected, name)) {
        candidate.clearSelection(clearText: true, suppressAutoFill: false);
      }
    }
  }

  void _queryItem(_ReviewRow row, String query) {
    final selected = row.selectedName;
    if (selected == null || _same(query, selected)) return;
    setState(() {
      row.clearSelection(clearText: false, suppressAutoFill: true);
      _error = null;
    });
  }

  void _amountChanged(_ReviewRow row) {
    row.amountEdited = true;
    final missing = row.missingAmount;
    if (missing == row.lastMissingAmount && _error == null) return;
    row.lastMissingAmount = missing;
    setState(() => _error = null);
  }

  void _reconcileAutomaticSelections() {
    final usedByScreenshot = <String, Set<String>>{};
    for (final row in _rows) {
      final selected = row.selectedName;
      if (selected == null || !row.selectionFixed) continue;
      final used = usedByScreenshot.putIfAbsent(
        row.screenshotFingerprint,
        () => <String>{},
      );
      if (!used.add(_fold(selected))) {
        row.clearSelection(clearText: true, suppressAutoFill: false);
      }
    }

    for (final row in _rows) {
      if (row.selectionInferred && !row.suppressAutoFill) {
        row.clearSelection(clearText: true, suppressAutoFill: false);
      }
    }

    for (final fingerprint in _screenshotOrderByFingerprint.keys) {
      final screenshotRows = _rows
          .where((row) => row.screenshotFingerprint == fingerprint)
          .toList(growable: false);
      final saltRows = screenshotRows.where(_isSaltChoiceRow).toList();
      final singletonSaltRow = saltRows.length == 1 ? saltRows.single : null;
      if (saltRows.length > 1) {
        // Two visible salt stacks can represent the two byte-identical BDO
        // items. Rebuild every automatic salt choice by canonical item ID;
        // manually confirmed choices remain authoritative.
        for (final saltRow in saltRows) {
          if (!saltRow.selectionFixed && !saltRow.suppressAutoFill) {
            saltRow.clearSelection(clearText: true, suppressAutoFill: false);
          }
        }
      }
      final used = usedByScreenshot.putIfAbsent(fingerprint, () => <String>{});
      final optimizedCatalogRows = _optimizeCatalogOrderRuns(
        screenshotRows,
        used,
      );
      int? previousItemId;
      String? previousOrderFamily;
      var orderRunHasManualAnchor = false;
      for (var index = 0; index < screenshotRows.length; index += 1) {
        final row = screenshotRows[index];
        if (optimizedCatalogRows.contains(row)) {
          final selected = row.selectedName;
          if (selected != null) used.add(_fold(selected));
          previousItemId = null;
          previousOrderFamily = null;
          orderRunHasManualAnchor = false;
          continue;
        }
        final orderFamily = _itemIdOrderFamily(row);
        final useItemOrder = orderFamily != null;
        if (orderFamily != previousOrderFamily) {
          previousItemId = null;
          orderRunHasManualAnchor = false;
        }
        final nextFixedId = orderFamily == null
            ? null
            : _nextFixedItemId(screenshotRows, index + 1, orderFamily);
        if (identical(row, singletonSaltRow) &&
            !row.selectionFixed &&
            !row.suppressAutoFill) {
          InventoryItemMatch? salt;
          for (final match in row.source.matches) {
            if (match.itemId == _saltItemId) {
              salt = match;
              break;
            }
          }
          if (salt != null) {
            // Salt and Sun-Dried Salt are visually identical. For one stack,
            // the ordinary recipe ingredient is the honest default requested
            // by the user; the yellow state keeps the dropdown easy to check.
            row.select(salt.name, fixed: false, inferred: true);
            used.add(_fold(salt.name));
            previousItemId = salt.itemId;
            previousOrderFamily = _saltOrderFamily;
            continue;
          }
        }
        // These two oils share their exact artwork with water bottles. Apply
        // the requested singleton default even when OCR already chose water;
        // a source suggestion is not a manual confirmation. Multiple stacks
        // still use ordering, and a user's explicit water choice always wins.
        if (!row.selectionFixed &&
            !row.suppressAutoFill &&
            orderFamily != null &&
            orderFamily.startsWith('artwork:') &&
            screenshotRows
                    .where(
                      (candidate) =>
                          _itemIdOrderFamily(candidate) == orderFamily,
                    )
                    .length ==
                1) {
          final preferredOil = _preferredSharedBottleOil(row, orderFamily);
          if (preferredOil != null) {
            row.select(preferredOil.name, fixed: false, inferred: true);
          }
        }
        var selected = row.selectedName;
        if (selected != null &&
            useItemOrder &&
            !row.selectionFixed &&
            !row.suppressAutoFill) {
          final folded = _fold(selected);
          final selectedId = _itemIdForName(selected);
          final violatesObservedOrder =
              selectedId != null &&
              ((previousItemId != null && selectedId > previousItemId) ||
                  (nextFixedId != null && selectedId < nextFixedId));
          if (used.contains(folded) || violatesObservedOrder) {
            // Source suggestions are useful evidence, but they are not manual
            // confirmations. A repeated stackable item or an ID that moves
            // backwards inside an established Auto Arrange run must be
            // re-evaluated. This repairs Elder/Elder and Loopy/Loopy without
            // overriding any choice the user fixed themselves.
            row.clearSelection(clearText: true, suppressAutoFill: false);
            selected = null;
          }
        }
        if (selected != null) {
          used.add(_fold(selected));
          orderRunHasManualAnchor =
              orderRunHasManualAnchor || row.selectionFixed;
          previousItemId = useItemOrder
              ? _itemIdForName(selected) ?? previousItemId
              : null;
          previousOrderFamily = orderFamily;
          continue;
        }
        if (row.suppressAutoFill) {
          previousItemId = null;
          previousOrderFamily = null;
          continue;
        }

        if (!useItemOrder) {
          // A normal row is auto-filled only by the sanitizer after it passes
          // the score, margin, quality, and material checks. Picking the first
          // remaining dropdown entry here used to turn weak look-alikes into
          // confident names (for example Bag of Muddy Water -> Thuja Plank).
          previousItemId = null;
          previousOrderFamily = null;
          continue;
        }

        final visualFamily = _visualChoiceFamily(row);
        final topConfidence = row.source.matches.firstOrNull?.confidence ?? 0;
        final available = row.source.matches
            .where(
              (match) =>
                  _itemIdOrderFamilyForMatch(match) == orderFamily &&
                  (visualFamily == null ||
                      _artworkFamilyForMatch(match) == visualFamily ||
                      topConfidence - match.confidence <=
                          _automaticVisualAlternativeWindow) &&
                  !used.contains(_fold(match.name)),
            )
            .toList(growable: true);
        if (available.isEmpty) continue;

        InventoryItemMatch? choice;
        final familyRowCount = screenshotRows
            .where((candidate) => _itemIdOrderFamily(candidate) == orderFamily)
            .length;
        if ((orderFamily == _saltOrderFamily ||
                orderFamily.startsWith('artwork:')) &&
            familyRowCount == 1 &&
            previousItemId == null &&
            nextFixedId == null) {
          // Some real BDO items intentionally share byte-identical artwork
          // even though one is the ingredient used by planner recipes and the
          // other is an older/raw alternative (for example Oil of Storms vs
          // Bottle of Turbid Water). For a single stack, prefer the candidate
          // backed by more exact recipe uses. Multiple stacks continue through
          // item-ID ordering so both identities remain possible.
          choice = _primaryIngredientChoice(available);
        }
        available.sort((left, right) {
          if (orderRunHasManualAnchor && orderFamily == 'catalog:dried-fish') {
            final leftId = left.itemId ?? _itemIdForName(left.name) ?? -1;
            final rightId = right.itemId ?? _itemIdForName(right.name) ?? -1;
            final id = rightId.compareTo(leftId);
            if (id != 0) return id;
          }
          final leftVisual =
              visualFamily != null &&
              _artworkFamilyForMatch(left) == visualFamily;
          final rightVisual =
              visualFamily != null &&
              _artworkFamilyForMatch(right) == visualFamily;
          if (leftVisual != rightVisual) return leftVisual ? -1 : 1;
          final confidence = right.confidence.compareTo(left.confidence);
          if (confidence != 0) return confidence;
          final leftId = left.itemId ?? _itemIdForName(left.name) ?? -1;
          final rightId = right.itemId ?? _itemIdForName(right.name) ?? -1;
          return rightId.compareTo(leftId);
        });
        if (choice == null) {
          for (final match in available) {
            final itemId = match.itemId ?? _itemIdForName(match.name);
            if (itemId == null) continue;
            if (previousItemId != null && itemId > previousItemId) continue;
            if (nextFixedId != null && itemId < nextFixedId) continue;
            choice = match;
            break;
          }
        }
        if (choice == null) continue;
        row.select(choice.name, fixed: false, inferred: true);
        used.add(_fold(choice.name));
        previousItemId =
            choice.itemId ?? _itemIdForName(choice.name) ?? previousItemId;
        previousOrderFamily = orderFamily;
      }
    }
  }

  Set<_ReviewRow> _optimizeCatalogOrderRuns(
    List<_ReviewRow> screenshotRows,
    Set<String> usedOutsideRuns,
  ) {
    final processed = <_ReviewRow>{};
    var start = 0;
    while (start < screenshotRows.length) {
      final first = screenshotRows[start];
      final family = first.suppressAutoFill ? null : _itemIdOrderFamily(first);
      if (family != 'catalog:blood:all') {
        start += 1;
        continue;
      }
      var end = start + 1;
      while (end < screenshotRows.length &&
          !screenshotRows[end].suppressAutoFill &&
          _itemIdOrderFamily(screenshotRows[end]) == family) {
        end += 1;
      }
      final run = screenshotRows.sublist(start, end);
      // Preserve the sanitizer's visual decisions on first load. Whole-run
      // optimization is only needed after the user establishes a trustworthy
      // anchor; without one, an ID-perfect sequence can invent items that are
      // absent from storage simply because their IDs fill a catalogue gap.
      if (run.length < 3 && !run.any((row) => row.selectionFixed)) {
        start = end;
        continue;
      }
      _optimizeCatalogOrderRun(run, 'catalog:blood:all', usedOutsideRuns);
      processed.addAll(run);
      start = end;
    }
    return processed;
  }

  void _optimizeCatalogOrderRun(
    List<_ReviewRow> rows,
    String family,
    Set<String> usedOutsideRuns,
  ) {
    final candidatesByRow = <List<_OrderCandidate>>[];
    for (final row in rows) {
      final selected = row.selectedName;
      if (row.selectionFixed && selected != null) {
        final itemId = _itemIdForName(selected);
        if (itemId == null) {
          candidatesByRow.add(const <_OrderCandidate>[]);
        } else {
          candidatesByRow.add(<_OrderCandidate>[
            (name: selected, itemId: itemId, utility: 1000),
          ]);
        }
        continue;
      }

      final visualFamily = _visualChoiceFamily(row);
      final topConfidence = row.source.matches.firstOrNull?.confidence ?? 0;
      final byId = <int, _OrderCandidate>{};
      for (final match in row.source.matches) {
        if (_itemIdOrderFamilyForMatch(match) != family ||
            match.qualityConflict) {
          continue;
        }
        final itemId = match.itemId ?? _itemIdForName(match.name);
        if (itemId == null || usedOutsideRuns.contains(_fold(match.name))) {
          continue;
        }
        final artworkFamily = _artworkFamilyForMatch(match);
        final matchesVisual =
            visualFamily == null || artworkFamily == visualFamily;
        final nearVisualAlternative =
            visualFamily != null &&
            topConfidence - match.confidence <=
                _automaticVisualAlternativeWindow;
        final wasSourceSelection =
            row.source.selectedName != null &&
            _same(row.source.selectedName!, match.name);
        final reviewedBloodFallback =
            family == 'catalog:blood:all' &&
            match.orderGroupKey == 'blood:all' &&
            match.nativeMaterialEligible == null &&
            match.confidence <= .7000001;
        if (!matchesVisual &&
            !nearVisualAlternative &&
            !wasSourceSelection &&
            !reviewedBloodFallback) {
          continue;
        }
        final visualConfidence =
            match.sourceVisualConfidence ?? match.confidence;
        final fallbackPenalty =
            reviewedBloodFallback &&
                (match.sourceVisualConfidence == null ||
                    match.sourceVisualConfidence! <
                        _automaticFallbackVisualScore)
            ? -.20
            : 0.0;
        final utility =
            visualConfidence +
            (matchesVisual ? _automaticVisualFamilyBonus : 0) +
            (wasSourceSelection ? _automaticSourceSelectionBonus : 0) +
            fallbackPenalty +
            itemId * 1e-12;
        final candidate = (name: match.name, itemId: itemId, utility: utility);
        final previous = byId[itemId];
        if (previous == null || candidate.utility > previous.utility) {
          byId[itemId] = candidate;
        }
      }
      candidatesByRow.add(byId.values.toList(growable: false));
    }

    var states = <int, _OrderState>{
      0x7fffffff: (score: 0, choices: const <String?>[]),
    };
    for (var index = 0; index < rows.length; index += 1) {
      final row = rows[index];
      final candidates = candidatesByRow[index];
      final next = <int, _OrderState>{};

      void retain(int lastItemId, _OrderState candidate) {
        final existing = next[lastItemId];
        if (existing == null || candidate.score > existing.score) {
          next[lastItemId] = candidate;
        }
      }

      for (final entry in states.entries) {
        final previousId = entry.key;
        final state = entry.value;
        if (!row.selectionFixed) {
          retain(previousId, (
            score: state.score,
            choices: <String?>[...state.choices, null],
          ));
        }
        for (final candidate in candidates) {
          if (candidate.itemId >= previousId) continue;
          retain(candidate.itemId, (
            score: state.score + candidate.utility,
            choices: <String?>[...state.choices, candidate.name],
          ));
        }
      }
      states = next;
      if (states.isEmpty) break;
    }

    if (states.isEmpty) {
      // Contradictory manual anchors remain authoritative. Clear only the
      // automatic rows rather than inventing a sequence around them.
      for (final row in rows) {
        if (!row.selectionFixed) {
          row.clearSelection(clearText: true, suppressAutoFill: false);
        } else if (row.selectedName case final selected?) {
          usedOutsideRuns.add(_fold(selected));
        }
      }
      return;
    }

    final best = states.values.reduce(
      (left, right) => right.score > left.score ? right : left,
    );
    for (var index = 0; index < rows.length; index += 1) {
      final row = rows[index];
      if (row.selectionFixed) {
        if (row.selectedName case final selected?) {
          usedOutsideRuns.add(_fold(selected));
        }
        continue;
      }
      final choice = best.choices[index];
      if (choice == null) {
        row.clearSelection(clearText: true, suppressAutoFill: false);
        continue;
      }
      final preservesSource =
          row.source.selectedName != null &&
          _same(row.source.selectedName!, choice);
      row.select(choice, fixed: false, inferred: !preservesSource);
      usedOutsideRuns.add(_fold(choice));
    }
  }

  InventoryItemMatch? _preferredSharedBottleOil(
    _ReviewRow row,
    String artworkFamily,
  ) {
    final candidates = row.source.matches
        .where((match) => _artworkFamilyForMatch(match) == artworkFamily)
        .toList(growable: false);
    for (final pair in const <(int, int)>[(6601, 6655), (6602, 6654)]) {
      final oil = candidates
          .where((match) => match.itemId == pair.$1)
          .firstOrNull;
      final water = candidates
          .where((match) => match.itemId == pair.$2)
          .firstOrNull;
      if (oil != null &&
          water != null &&
          (oil.confidence - water.confidence).abs() <=
              _automaticVisualAlternativeWindow) {
        return oil;
      }
    }
    return null;
  }

  InventoryItemMatch? _primaryIngredientChoice(
    List<InventoryItemMatch> available,
  ) {
    if (available.length < 2) return null;
    final ranked = List<InventoryItemMatch>.of(available)
      ..sort((left, right) {
        final usage = right.primaryIngredientUseCount.compareTo(
          left.primaryIngredientUseCount,
        );
        return usage != 0 ? usage : right.confidence.compareTo(left.confidence);
      });
    final best = ranked.first;
    if (best.primaryIngredientUseCount <= 0 ||
        best.primaryIngredientUseCount == ranked[1].primaryIngredientUseCount) {
      return null;
    }
    return best;
  }

  String? _itemIdOrderFamily(_ReviewRow row) {
    if (row.selectedName case final selected?) {
      final selectedFamily = _itemIdOrderFamilyForName(row, selected);
      if (selectedFamily != null) return selectedFamily;
    }
    final top = row.source.matches.firstOrNull;
    if (top == null) return null;
    final family = _itemIdOrderFamilyForMatch(top);
    if (family == null) return null;
    if (top.orderGroupKey?.trim().isNotEmpty == true && top.itemId != null) {
      return family;
    }
    final members = row.source.matches.where(
      (match) =>
          _itemIdOrderFamilyForMatch(match) == family &&
          (match.itemId != null || _itemIdForName(match.name) != null),
    );
    return members.length >= 2 ? family : null;
  }

  String? _itemIdOrderFamilyForName(_ReviewRow row, String name) {
    final catalogGroup = _itemOrderGroupsByName[_fold(name)];
    if (catalogGroup != null &&
        _verifiedAutomaticOrderGroups.contains(catalogGroup) &&
        _itemIdForName(name) != null) {
      return 'catalog:$catalogGroup';
    }
    InventoryItemMatch? match;
    for (final candidate in row.source.matches) {
      if (_same(candidate.name, name)) {
        match = candidate;
        break;
      }
    }
    if (match == null) return null;
    final family = _itemIdOrderFamilyForMatch(match);
    if (family == null) return null;
    final members = row.source.matches.where(
      (candidate) =>
          _itemIdOrderFamilyForMatch(candidate) == family &&
          (candidate.itemId != null || _itemIdForName(candidate.name) != null),
    );
    return members.length >= 2 ? family : null;
  }

  String? _itemIdOrderFamilyForMatch(InventoryItemMatch match) {
    if (match.qualityConflict) return null;
    final catalogGroup = match.orderGroupKey?.trim();
    if (catalogGroup != null &&
        catalogGroup.isNotEmpty &&
        _verifiedAutomaticOrderGroups.contains(catalogGroup) &&
        match.itemId != null) {
      return 'catalog:$catalogGroup';
    }
    if (match.itemId == _saltItemId || match.itemId == _sunDriedSaltItemId) {
      return _saltOrderFamily;
    }
    return _artworkFamilyForMatch(match);
  }

  String? _artworkFamilyForMatch(InventoryItemMatch match) {
    if (match.qualityConflict) return null;
    final artwork = match.artworkKey;
    if (artwork == null || artwork.isEmpty) {
      return null;
    }
    // Auto Arrange is useful only after the picture has identified the exact
    // artwork family. A broad catalogue group such as Dried Fish must not let
    // Grouper compete with every differently drawn fish on the map.
    return 'artwork:$artwork:${match.grade ?? -1}';
  }

  String? _visualChoiceFamily(_ReviewRow row) {
    final selected = row.selectedName;
    if (selected != null) {
      for (final match in row.source.matches) {
        if (_same(match.name, selected)) {
          return _artworkFamilyForMatch(match);
        }
      }
    }
    final top = row.source.matches.firstOrNull;
    return top == null ? null : _artworkFamilyForMatch(top);
  }

  bool _isSaltChoiceRow(_ReviewRow row) {
    final leading = row.source.matches.firstOrNull;
    if (leading == null ||
        (leading.itemId != _saltItemId &&
            leading.itemId != _sunDriedSaltItemId)) {
      return false;
    }
    final leadingArtwork = leading.artworkKey;
    if (leadingArtwork == null || leadingArtwork.isEmpty) return false;
    var hasSalt = false;
    var hasSunDriedSalt = false;
    for (final match in row.source.matches) {
      if (match.artworkKey != leadingArtwork) continue;
      hasSalt = hasSalt || match.itemId == _saltItemId;
      hasSunDriedSalt = hasSunDriedSalt || match.itemId == _sunDriedSaltItemId;
    }
    return hasSalt && hasSunDriedSalt;
  }

  int? _nextFixedItemId(List<_ReviewRow> rows, int start, String family) {
    for (var index = start; index < rows.length; index += 1) {
      final row = rows[index];
      if (_itemIdOrderFamily(row) != family) break;
      if (row.selectionFixed && row.selectedName != null) {
        final itemId = _itemIdForName(row.selectedName!);
        if (itemId != null) return itemId;
      }
    }
    return null;
  }

  int? _itemIdForName(String name) => _itemIdsByName[_fold(name)];

  ({int? previous, int? next, bool enabled, String? family}) _itemIdBoundsFor(
    _ReviewRow row,
  ) {
    final screenshotRows = _rows
        .where(
          (candidate) =>
              candidate.screenshotFingerprint == row.screenshotFingerprint,
        )
        .toList(growable: false);
    final family = _itemIdOrderFamily(row);
    if (family == null) {
      return (previous: null, next: null, enabled: false, family: null);
    }
    final index = screenshotRows.indexOf(row);
    int? previous;
    for (var cursor = index - 1; cursor >= 0; cursor -= 1) {
      final candidate = screenshotRows[cursor];
      if (_itemIdOrderFamily(candidate) != family) break;
      if (!candidate.selectionFixed) continue;
      final selected = candidate.selectedName;
      if (selected == null) continue;
      previous = _itemIdForName(selected);
      if (previous != null) break;
    }
    int? next;
    for (var cursor = index + 1; cursor < screenshotRows.length; cursor += 1) {
      final candidate = screenshotRows[cursor];
      if (_itemIdOrderFamily(candidate) != family) break;
      if (!candidate.selectionFixed) continue;
      final selected = candidate.selectedName;
      if (selected == null) continue;
      next = _itemIdForName(selected);
      if (next != null) break;
    }
    return (previous: previous, next: next, enabled: true, family: family);
  }

  int? _previousSelectedItemId(_ReviewRow row, String family) {
    final screenshotRows = _rows
        .where(
          (candidate) =>
              candidate.screenshotFingerprint == row.screenshotFingerprint,
        )
        .toList(growable: false);
    final index = screenshotRows.indexOf(row);
    for (var cursor = index - 1; cursor >= 0; cursor -= 1) {
      final candidate = screenshotRows[cursor];
      if (_itemIdOrderFamily(candidate) != family) break;
      final selected = candidate.selectedName;
      if (selected == null) continue;
      final itemId = _itemIdForName(selected);
      if (itemId != null) return itemId;
    }
    return null;
  }

  List<String> _choicesFor(_ReviewRow row) {
    final used = <String>{};
    final currentOrderFamily = _itemIdOrderFamily(row);
    for (final other in _rows) {
      final name = other.selectedName;
      final provisionalInSameFamily =
          !other.selectionFixed &&
          currentOrderFamily != null &&
          _itemIdOrderFamily(other) == currentOrderFamily;
      if (!identical(other, row) &&
          other.screenshotFingerprint == row.screenshotFingerprint &&
          name != null &&
          !provisionalInSameFamily) {
        used.add(_fold(name));
      }
    }
    final choices = <String>[];
    final seen = <String>{};
    final bounds = _itemIdBoundsFor(row);
    final visualFamily = _visualChoiceFamily(row);
    final previousLimit =
        bounds.previous ??
        (currentOrderFamily == null
            ? null
            : _previousSelectedItemId(row, currentOrderFamily));
    double visualEvidence(InventoryItemMatch match) =>
        match.sourceVisualConfidence ?? match.confidence;
    bool withinBounds(String name) {
      if (!bounds.enabled) return true;
      final itemId = _itemIdForName(name);
      if (itemId == null) return true;
      if (previousLimit != null && itemId > previousLimit) return false;
      if (bounds.next != null && itemId < bounds.next!) return false;
      return true;
    }

    void add(String name, {bool always = false}) {
      final folded = _fold(name);
      if (!used.contains(folded) &&
          (always || withinBounds(name)) &&
          seen.add(folded)) {
        choices.add(name);
      }
    }

    if (row.selectedName case final selected?) {
      add(selected, always: true);
    }
    final likelyMatches =
        row.source.matches
            .where(
              (match) =>
                  currentOrderFamily == null ||
                  _itemIdOrderFamilyForMatch(match) == currentOrderFamily,
            )
            .toList(growable: false)
          ..sort((left, right) {
            final leftWithinBounds = withinBounds(left.name);
            final rightWithinBounds = withinBounds(right.name);
            if (leftWithinBounds != rightWithinBounds) {
              return leftWithinBounds ? -1 : 1;
            }
            // Once the preceding row establishes a verified Auto Arrange run,
            // impossible higher IDs must not bury the next valid fish. This
            // keeps Bluefish/Nibbler/etc. at the top while still retaining
            // every same-artwork alternative for mouse correction below it.
            if (leftWithinBounds &&
                previousLimit != null &&
                currentOrderFamily == 'catalog:dried-fish') {
              final leftId = left.itemId ?? _itemIdForName(left.name) ?? -1;
              final rightId = right.itemId ?? _itemIdForName(right.name) ?? -1;
              final id = rightId.compareTo(leftId);
              if (id != 0) return id;
            }
            final visualScore = visualEvidence(
              right,
            ).compareTo(visualEvidence(left));
            if (visualScore != 0) return visualScore;
            final leftVisual =
                visualFamily != null &&
                _artworkFamilyForMatch(left) == visualFamily;
            final rightVisual =
                visualFamily != null &&
                _artworkFamilyForMatch(right) == visualFamily;
            if (leftVisual != rightVisual) return leftVisual ? -1 : 1;
            final score = right.confidence.compareTo(left.confidence);
            if (score != 0) return score;
            final leftId = left.itemId ?? _itemIdForName(left.name) ?? -1;
            final rightId = right.itemId ?? _itemIdForName(right.name) ?? -1;
            return rightId.compareTo(leftId);
          });
    for (final match in likelyMatches) {
      if (currentOrderFamily == null &&
          visualFamily != null &&
          _artworkFamilyForMatch(match) != visualFamily) {
        continue;
      }
      add(
        match.name,
        always:
            visualFamily != null &&
            _artworkFamilyForMatch(match) == visualFamily,
      );
    }
    return choices;
  }

  List<String> _searchChoicesFor(_ReviewRow row) {
    final fixedElsewhere = <String>{};
    for (final other in _rows) {
      final selected = other.selectedName;
      if (!identical(other, row) &&
          other.screenshotFingerprint == row.screenshotFingerprint &&
          other.selectionFixed &&
          selected != null) {
        fixedElsewhere.add(_fold(selected));
      }
    }
    final result = <String>[];
    final seen = <String>{};
    void add(String name) {
      final folded = _fold(name);
      if (!fixedElsewhere.contains(folded) && seen.add(folded)) {
        result.add(name);
      }
    }

    for (final name in _choicesFor(row)) {
      add(name);
    }
    for (final name in _itemNames) {
      add(name);
    }
    return result;
  }

  void _submit() {
    if (_submitting) return;
    if (_rows.isEmpty) {
      setState(() => _error = 'Keep at least one recognized item to save.');
      return;
    }
    final firstIncomplete = _rows.cast<_ReviewRow?>().firstWhere(
      (row) => row!.isIncomplete,
      orElse: () => null,
    );
    if (firstIncomplete != null) {
      setState(() {
        _validationPulse += 1;
        _error = firstIncomplete.missingItem && firstIncomplete.missingAmount
            ? 'Choose the item and enter its amount.'
            : firstIncomplete.missingItem
            ? 'Choose the item for this slot.'
            : 'Enter a positive amount for this item.';
      });
      unawaited(
        _revealIncomplete(
          firstIncomplete,
          focusItem: firstIncomplete.missingItem,
        ),
      );
      return;
    }

    final quantities = <String, double>{};
    for (final row in _rows) {
      final name = row.selectedName?.trim();
      final amount = parsePlannerNumber(row.amount.text);
      if (name == null || name.isEmpty || amount == null || amount <= 0) return;
      String? existingName;
      for (final candidate in quantities.keys) {
        if (_same(candidate, name)) {
          existingName = candidate;
          break;
        }
      }
      final canonicalName = existingName ?? name;
      quantities[canonicalName] = (quantities[canonicalName] ?? 0) + amount;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    Navigator.of(context).pop(
      InventoryScreenshotReview(saveMode: _saveMode, quantities: quantities),
    );
  }

  Future<void> _revealIncomplete(
    _ReviewRow row, {
    required bool focusItem,
  }) async {
    if (!_rows.contains(row)) return;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (row.scrollKey.currentContext == null &&
        _rowScrollController.hasClients) {
      final target = _estimatedRowOffset(
        row,
      ).clamp(0.0, _rowScrollController.position.maxScrollExtent).toDouble();
      if (reduceMotion) {
        _rowScrollController.jumpTo(target);
      } else {
        await _rowScrollController.animateTo(
          target,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
        );
      }
      if (!mounted) return;
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
    }
    final rowContext = row.scrollKey.currentContext;
    if (rowContext != null && rowContext.mounted) {
      await Scrollable.ensureVisible(
        rowContext,
        duration: reduceMotion
            ? Duration.zero
            : const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        alignment: .35,
      );
    }
    if (!mounted) return;
    (focusItem ? row.itemFocus : row.amountFocus).requestFocus();
  }

  double _estimatedRowOffset(_ReviewRow targetRow) {
    var offset = 0.0;
    for (final fingerprint in _screenshotOrderByFingerprint.keys) {
      final screenshotRows = _rows
          .where((row) => row.screenshotFingerprint == fingerprint)
          .toList(growable: false);
      if (screenshotRows.isEmpty) continue;
      offset += _ScreenshotReviewHeading.extent;
      final localIndex = screenshotRows.indexOf(targetRow);
      if (localIndex >= 0) {
        return offset +
            (localIndex ~/ _gridColumns) * (_rowExtent + _rowSpacing);
      }
      final gridRows =
          (screenshotRows.length + _gridColumns - 1) ~/ _gridColumns;
      offset += gridRows * (_rowExtent + _rowSpacing) + 10;
    }
    return offset;
  }

  Future<void> _jumpToScreenshot(
    int screenshotIndex,
    List<List<_ReviewRow>> screenshots,
  ) async {
    if (!_rowScrollController.hasClients ||
        screenshotIndex < 0 ||
        screenshotIndex >= screenshots.length) {
      return;
    }
    var target = 0.0;
    final columns = math.max(1, _gridColumns);
    for (var index = 0; index < screenshotIndex; index += 1) {
      final gridRows = (screenshots[index].length + columns - 1) ~/ columns;
      final gridExtent =
          gridRows * _rowExtent + math.max(0, gridRows - 1) * _rowSpacing;
      target += _ScreenshotReviewHeading.extent + gridExtent + 14;
    }
    target = target
        .clamp(0.0, _rowScrollController.position.maxScrollExtent)
        .toDouble();
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduceMotion) {
      _rowScrollController.jumpTo(target);
      return;
    }
    await _rowScrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _showPreview(_ReviewRow row) => showDialog<void>(
    context: context,
    builder: (context) {
      final parsed = parsePlannerNumber(row.amount.text);
      final fullAmount = parsed == null
          ? row.amount.text.trim()
          : formatGroupedEditableQuantity(parsed);
      return Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440, maxHeight: 520),
          child: AppSurface(
            role: AppSurfaceRole.modal,
            semanticLabel: 'Enlarged screenshot item',
            padding: const EdgeInsets.all(14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                SectionHeader(
                  title: row.selectedName ?? 'Screenshot item',
                  trailing: AppButton.icon(
                    icon: const AppVectorGlyph('close', size: 19),
                    semanticLabel: 'Close enlarged screenshot item',
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 260,
                  child: AppSurface(
                    role: AppSurfaceRole.card,
                    padding: const EdgeInsets.all(10),
                    child: InteractiveViewer(
                      minScale: 1,
                      maxScale: 6,
                      child: Center(
                        child: Image.memory(
                          row.source.previewPng,
                          key: ValueKey<String>(
                            'inventory-import-preview-large-${row.uiId}',
                          ),
                          fit: BoxFit.contain,
                          filterQuality: FilterQuality.none,
                          semanticLabel:
                              'Enlarged screenshot crop for row ${row.source.row + 1}, column ${row.source.column + 1}',
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _PreviewValue(
                  label: 'Visible in screenshot',
                  value: row.source.quantityText.isEmpty
                      ? 'No readable number'
                      : row.source.quantityText,
                ),
                const SizedBox(height: 6),
                _PreviewValue(
                  label: 'Full amount',
                  value: fullAmount.isEmpty ? 'Not entered' : fullAmount,
                ),
              ],
            ),
          ),
        ),
      );
    },
  );

  @override
  Widget build(BuildContext context) {
    final incomplete = _rows.where((row) => row.isIncomplete).length;
    final reviewCount =
        '${_rows.length} ${_rows.length == 1 ? 'item' : 'items'}'
        '${incomplete > 0 ? ' · $incomplete missing' : ''}';
    final canAddMore = _fingerprints.length < _maximumScreenshots;
    final addScreenshot = widget.pasteAnother ?? widget.chooseAnother;
    final screenshots = <List<_ReviewRow>>[
      for (final fingerprint in _screenshotOrderByFingerprint.keys)
        _rows
            .where((row) => row.screenshotFingerprint == fingerprint)
            .toList(growable: false),
    ].where((rows) => rows.isNotEmpty).toList(growable: false);
    return ConstrainedBox(
      key: const ValueKey<String>('inventory-import-dialog-frame'),
      constraints: BoxConstraints(
        maxWidth: 980,
        maxHeight: (MediaQuery.sizeOf(context).height - 32).clamp(0.0, 860.0),
      ),
      child: SizedBox(
        width: double.infinity,
        child: AppSurface(
          role: AppSurfaceRole.modal,
          semanticLabel: 'Review recognized inventory items',
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              SizedBox(
                width: double.infinity,
                child: Stack(
                  children: <Widget>[
                    _ApplicationWindowDragRegion(
                      key: const ValueKey<String>(
                        'inventory-import-drag-region',
                      ),
                      windowHost: widget.windowHost,
                      child: Padding(
                        padding: const EdgeInsets.only(right: 54),
                        child: SectionHeader(
                          title: 'Review items',
                          meta: reviewCount,
                        ),
                      ),
                    ),
                    Positioned(
                      top: 0,
                      right: 0,
                      child: AppButton.icon(
                        key: const ValueKey<String>('inventory-import-close'),
                        icon: const AppVectorGlyph('close', size: 19),
                        semanticLabel: 'Close screenshot review',
                        tooltip: 'Close',
                        onPressed: (_busy || _submitting)
                            ? null
                            : () => Navigator.of(context).pop(),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                key: const ValueKey<String>('inventory-import-actions'),
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: <Widget>[
                  AppButton.label(
                    'Replace current inventory',
                    key: const ValueKey<String>('inventory-import-update-mode'),
                    role: AppButtonRole.optionPill,
                    selected: _saveMode == InventoryScreenshotSaveMode.update,
                    tooltip:
                        'Clear the current Inventory and replace it with the reviewed totals',
                    onPressed: _busy
                        ? null
                        : () => setState(() {
                            _saveMode = InventoryScreenshotSaveMode.update;
                            _error = null;
                          }),
                  ),
                  AppButton.label(
                    'Add to inventory',
                    key: const ValueKey<String>('inventory-import-add-mode'),
                    role: AppButtonRole.optionPill,
                    selected: _saveMode == InventoryScreenshotSaveMode.add,
                    tooltip: 'Add these amounts to what is already saved',
                    onPressed: _busy
                        ? null
                        : () => setState(() {
                            _saveMode = InventoryScreenshotSaveMode.add;
                            _error = null;
                          }),
                  ),
                  if (canAddMore && addScreenshot != null)
                    AppButton(
                      key: const ValueKey<String>(
                        'inventory-import-add-screenshot',
                      ),
                      role: AppButtonRole.secondary,
                      minimumSize: const Size(0, 38),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      semanticLabel: _busy
                          ? 'Adding screenshot'
                          : 'Add another screenshot',
                      onPressed: _busy
                          ? null
                          : () => _addScreenshot(addScreenshot),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          if (_busy)
                            const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          else
                            const Icon(
                              Icons.add_photo_alternate_outlined,
                              size: 18,
                            ),
                          const SizedBox(width: 7),
                          const Text('Add screenshot'),
                        ],
                      ),
                    ),
                  if (_nativeHidden.isNotEmpty)
                    AppButton.label(
                      'Review ${_nativeHidden.length} items',
                      role: AppButtonRole.secondary,
                      onPressed: _busy ? null : _showHiddenRows,
                    ),
                  if (_removed.isNotEmpty)
                    AppButton.label(
                      'Undo removal',
                      role: AppButtonRole.secondary,
                      onPressed: _busy ? null : _restoreLastRemoved,
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: _rows.isEmpty
                    ? AppSurface(
                        role: AppSurfaceRole.row,
                        tone: AppSurfaceTone.warning,
                        child: const Center(
                          child: Text(
                            'No planner items remain. Restore a removed slot or close this review.',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      )
                    : LayoutBuilder(
                        builder: (context, constraints) {
                          final columns = constraints.maxWidth >= 720 ? 2 : 1;
                          _gridColumns = columns;
                          return CustomScrollView(
                            key: const ValueKey<String>(
                              'inventory-import-rows',
                            ),
                            controller: _rowScrollController,
                            slivers: <Widget>[
                              for (
                                var screenshotIndex = 0;
                                screenshotIndex < screenshots.length;
                                screenshotIndex += 1
                              ) ...<Widget>[
                                SliverToBoxAdapter(
                                  child: _ScreenshotReviewHeading(
                                    key: ValueKey<String>(
                                      'inventory-import-screenshot-section-$screenshotIndex',
                                    ),
                                    number: screenshotIndex + 1,
                                    itemCount:
                                        screenshots[screenshotIndex].length,
                                  ),
                                ),
                                SliverPadding(
                                  padding: const EdgeInsets.only(bottom: 14),
                                  sliver: SliverGrid(
                                    key: ValueKey<String>(
                                      'inventory-import-grid-$screenshotIndex',
                                    ),
                                    gridDelegate:
                                        SliverGridDelegateWithFixedCrossAxisCount(
                                          crossAxisCount: columns,
                                          crossAxisSpacing: _rowSpacing,
                                          mainAxisSpacing: _rowSpacing,
                                          mainAxisExtent: _rowExtent,
                                        ),
                                    delegate: SliverChildBuilderDelegate(
                                      (context, index) => _buildRow(
                                        context,
                                        review:
                                            screenshots[screenshotIndex][index],
                                      ),
                                      childCount:
                                          screenshots[screenshotIndex].length,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          );
                        },
                      ),
              ),
              if (_error case final error?) ...<Widget>[
                const SizedBox(height: 10),
                AppSurface(
                  role: AppSurfaceRole.row,
                  tone: AppSurfaceTone.danger,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  child: Text(error),
                ),
              ],
              const SizedBox(height: 10),
              Row(
                children: <Widget>[
                  if (screenshots.length > 1)
                    Expanded(
                      child: SingleChildScrollView(
                        key: const ValueKey<String>(
                          'inventory-import-screenshot-bookmarks',
                        ),
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: <Widget>[
                            for (
                              var screenshotIndex = 0;
                              screenshotIndex < screenshots.length;
                              screenshotIndex += 1
                            ) ...<Widget>[
                              if (screenshotIndex > 0) const SizedBox(width: 7),
                              _ScreenshotNumberBadge(
                                key: ValueKey<String>(
                                  'inventory-import-screenshot-bookmark-$screenshotIndex',
                                ),
                                number: screenshotIndex + 1,
                                onPressed: () => _jumpToScreenshot(
                                  screenshotIndex,
                                  screenshots,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    )
                  else
                    const Spacer(),
                  const SizedBox(width: 12),
                  AppButton(
                    key: const ValueKey<String>('inventory-import-save'),
                    role: AppButtonRole.primary,
                    semanticLabel: 'Done and save reviewed inventory',
                    onPressed: _busy || _submitting ? null : _submit,
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Icon(Icons.check_rounded, size: 19),
                        SizedBox(width: 7),
                        Text('Done'),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRow(BuildContext context, {required _ReviewRow review}) {
    final spec = context.visualTheme;
    final choices = _choicesFor(review);
    final searchChoices = _searchChoicesFor(review);
    return KeyedSubtree(
      key: review.scrollKey,
      child: AppSurface(
        key: ValueKey<String>('inventory-import-row-${review.uiId}'),
        role: AppSurfaceRole.row,
        tone: review.isIncomplete
            ? AppSurfaceTone.danger
            : review.hasUncertainSuggestion
            ? AppSurfaceTone.warning
            : AppSurfaceTone.neutral,
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            AppTooltip(
              message: 'Open a larger screenshot crop',
              child: Semantics(
                button: true,
                label:
                    'Open a larger screenshot crop for row ${review.source.row + 1}, column ${review.source.column + 1}',
                child: InkWell(
                  key: ValueKey<String>(
                    'inventory-import-preview-button-${review.uiId}',
                  ),
                  borderRadius: BorderRadius.circular(7),
                  onTap: () => _showPreview(review),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(7),
                    child: Image.memory(
                      review.source.previewPng,
                      key: ValueKey<String>(
                        'inventory-import-preview-${review.uiId}',
                      ),
                      width: 60,
                      height: 48,
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.high,
                      excludeFromSemantics: true,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: SizedBox(
                      height: 44,
                      child: _MissingFieldFrame(
                        fieldKey: 'item-${review.uiId}',
                        missing: review.missingItem,
                        warning: review.itemSuggestionIsUncertain,
                        pulseToken: _validationPulse,
                        child: AppSearchSelect<String>(
                          key: ValueKey<String>(
                            'inventory-import-item-${review.uiId}',
                          ),
                          controller: review.item,
                          focusNode: review.itemFocus,
                          items: choices,
                          searchItems: searchChoices,
                          value: review.selectedName,
                          labelFor: (value) => value,
                          hintText: 'Choose planner item',
                          hintStyle: review.missingItem
                              ? spec.typography.body.copyWith(
                                  color: spec.palette.danger,
                                  fontWeight: FontWeight.w700,
                                )
                              : null,
                          semanticLabel:
                              'Item in row ${review.source.row + 1}, column ${review.source.column + 1}',
                          enabled: !_busy && !_submitting,
                          anchorMaxLines: 2,
                          onQueryChanged: (query) => _queryItem(review, query),
                          onSelected: (name) => _selectItem(review, name),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 7),
                  SizedBox(
                    width: 108,
                    height: 44,
                    child: _MissingFieldFrame(
                      fieldKey: 'amount-${review.uiId}',
                      missing: review.missingAmount,
                      warning: review.amountSuggestionIsUncertain,
                      pulseToken: _validationPulse,
                      child: AppTextField(
                        key: ValueKey<String>(
                          'inventory-import-amount-${review.uiId}',
                        ),
                        controller: review.amount,
                        focusNode: review.amountFocus,
                        semanticLabel:
                            'Amount for ${review.selectedName ?? 'this slot'}',
                        hintText: 'Amount',
                        hintStyle: review.missingAmount
                            ? spec.typography.body.copyWith(
                                color: spec.palette.danger,
                                fontWeight: FontWeight.w700,
                              )
                            : null,
                        enabled: !_busy && !_submitting,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: false,
                        ),
                        inputFormatters: const <TextInputFormatter>[
                          InventoryAmountInputFormatter(),
                        ],
                        onChanged: (_) => _amountChanged(review),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  AppButton.icon(
                    key: ValueKey<String>(
                      'inventory-import-remove-${review.uiId}',
                    ),
                    icon: const AppVectorGlyph('trash', size: 17),
                    semanticLabel: 'Remove this recognized item',
                    tooltip: 'Remove',
                    onPressed: _busy || _submitting
                        ? null
                        : () => _removeRow(review),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PreviewValue extends StatelessWidget {
  const _PreviewValue({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final spec = context.visualTheme;
    return Row(
      children: <Widget>[
        Expanded(child: Text(label, style: spec.typography.meta)),
        const SizedBox(width: 12),
        SelectableText(
          value,
          textAlign: TextAlign.right,
          style: spec.typography.body.copyWith(fontWeight: FontWeight.w800),
        ),
      ],
    );
  }
}

class _ScreenshotReviewHeading extends StatelessWidget {
  const _ScreenshotReviewHeading({
    super.key,
    required this.number,
    required this.itemCount,
  });

  static const double extent = 46;

  final int number;
  final int itemCount;

  @override
  Widget build(BuildContext context) {
    final spec = context.visualTheme;
    return SizedBox(
      height: extent,
      child: Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 8),
        child: Row(
          children: <Widget>[
            _ScreenshotNumberBadge(number: number),
            const SizedBox(width: 8),
            Text(
              'Screenshot',
              style: spec.typography.body.copyWith(fontWeight: FontWeight.w800),
            ),
            const Spacer(),
            Text(
              '$itemCount ${itemCount == 1 ? 'item' : 'items'}',
              style: spec.typography.meta,
            ),
          ],
        ),
      ),
    );
  }
}

class _ScreenshotNumberBadge extends StatelessWidget {
  const _ScreenshotNumberBadge({
    required this.number,
    this.onPressed,
    super.key,
  });

  final int number;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final spec = context.visualTheme;
    final badge = DecoratedBox(
      decoration: BoxDecoration(
        color: spec.palette.primaryBright.withValues(alpha: .14),
        border: Border.all(
          color: spec.palette.primaryBright.withValues(alpha: .62),
        ),
        borderRadius: BorderRadius.circular(7),
      ),
      child: SizedBox.square(
        dimension: 28,
        child: Center(
          child: Text(
            '$number',
            style: spec.typography.body.copyWith(
              color: spec.palette.primaryBright,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ),
    );
    final action = onPressed;
    if (action == null) return badge;
    return AppTooltip(
      message: 'Jump to screenshot $number',
      child: Semantics(
        button: true,
        label: 'Jump to screenshot $number',
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(7),
            onTap: action,
            child: badge,
          ),
        ),
      ),
    );
  }
}

class _ApplicationWindowDragRegion extends StatelessWidget {
  const _ApplicationWindowDragRegion({
    required this.windowHost,
    required this.child,
    super.key,
  });

  final WindowHostService windowHost;
  final Widget child;

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: SystemMouseCursors.move,
    child: GestureDetector(
      behavior: HitTestBehavior.translucent,
      onPanStart: (_) => unawaited(windowHost.beginDrag()),
      child: child,
    ),
  );
}

final class _ReviewRow {
  _ReviewRow(
    this.source, {
    required this.screenshotFingerprint,
    required this.screenshotOrder,
  }) : selectedName = source.selectedName,
       selectionFixed = false,
       // A non-null source selection has already passed the sanitizer's visual,
       // material, quality, and row-local ambiguity gates. It may still be
       // highlighted yellow, but only choices created by the dialog's item-ID
       // reflow are provisional and eligible to be cleared automatically.
       selectionInferred = false,
       item = TextEditingController(text: source.selectedName ?? ''),
       amount = TextEditingController(
         text: source.quantity == null
             ? ''
             : formatGroupedEditableQuantity(source.quantity!.toDouble()),
       ) {
    lastMissingAmount = missingAmount;
  }

  final InventoryScreenshotRow source;
  final String screenshotFingerprint;
  final int screenshotOrder;
  final TextEditingController item;
  final TextEditingController amount;
  final FocusNode itemFocus = FocusNode();
  final FocusNode amountFocus = FocusNode();
  final GlobalKey scrollKey = GlobalKey();
  String? selectedName;
  bool selectionFixed;
  bool selectionInferred;
  bool suppressAutoFill = false;
  bool amountEdited = false;
  late bool lastMissingAmount;

  String get uiId =>
      screenshotOrder == 0 ? source.id : 's$screenshotOrder-${source.id}';

  bool get missingItem => selectedName?.trim().isNotEmpty != true;
  bool get missingAmount {
    final parsed = parsePlannerNumber(amount.text);
    return parsed == null || parsed <= 0;
  }

  bool get isIncomplete => missingItem || missingAmount;

  bool get itemSuggestionIsUncertain =>
      !missingItem &&
      !selectionFixed &&
      !selectedAnswerIsVisuallyCertain &&
      (selectionInferred || source.itemSuggestionUncertain);

  bool get selectedAnswerIsVisuallyCertain {
    final selected = selectedName;
    if (selected == null) return false;
    InventoryItemMatch? selectedMatch;
    for (final match in source.matches) {
      if (_same(match.name, selected)) {
        selectedMatch = match;
        break;
      }
    }
    if (selectedMatch == null || selectedMatch.qualityConflict) {
      return false;
    }
    final selectedScore =
        selectedMatch.sourceVisualConfidence ?? selectedMatch.confidence;
    if (selectedScore < .90) return false;
    var runnerUp = 0.0;
    for (final match in source.matches) {
      if (_same(match.name, selected) || match.qualityConflict) {
        continue;
      }
      final matchScore = match.sourceVisualConfidence ?? match.confidence;
      if (selectedMatch.artworkKey != null &&
          match.artworkKey == selectedMatch.artworkKey) {
        if (matchScore >= .70 && selectedScore - matchScore < .08) {
          // Two credible names backed by the same pixels cannot become
          // certain merely because one was placed first by item-ID order.
          return false;
        }
        continue;
      }
      runnerUp = math.max(runnerUp, matchScore);
    }
    return selectedScore - runnerUp >= .04;
  }

  bool get amountSuggestionIsUncertain =>
      !missingAmount && !amountEdited && source.quantitySuggestionUncertain;

  bool get hasUncertainSuggestion =>
      itemSuggestionIsUncertain || amountSuggestionIsUncertain;

  void select(String name, {required bool fixed, bool inferred = false}) {
    selectedName = name;
    selectionFixed = fixed;
    selectionInferred = inferred;
    suppressAutoFill = false;
    item.value = TextEditingValue(
      text: name,
      selection: TextSelection.collapsed(offset: name.length),
    );
  }

  void clearSelection({bool clearText = true, required bool suppressAutoFill}) {
    selectedName = null;
    selectionFixed = false;
    selectionInferred = false;
    this.suppressAutoFill = suppressAutoFill;
    if (clearText) item.clear();
  }

  void dispose() {
    item.dispose();
    amount.dispose();
    itemFocus.dispose();
    amountFocus.dispose();
  }
}

final class _HiddenReviewSource {
  const _HiddenReviewSource({
    required this.source,
    required this.screenshotFingerprint,
    required this.screenshotOrder,
  });

  final InventoryScreenshotRow source;
  final String screenshotFingerprint;
  final int screenshotOrder;
}

class _MissingFieldFrame extends StatefulWidget {
  const _MissingFieldFrame({
    required this.fieldKey,
    required this.missing,
    required this.warning,
    required this.pulseToken,
    required this.child,
  });

  final String fieldKey;
  final bool missing;
  final bool warning;
  final int pulseToken;
  final Widget child;

  @override
  State<_MissingFieldFrame> createState() => _MissingFieldFrameState();
}

class _MissingFieldFrameState extends State<_MissingFieldFrame>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void didUpdateWidget(_MissingFieldFrame oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.missing) {
      _pulse.stop();
      _pulse.value = 0;
    } else if (widget.pulseToken != oldWidget.pulseToken &&
        widget.pulseToken > 0) {
      _pulse.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final spec = context.visualTheme;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return AnimatedBuilder(
      key: ValueKey<String>('inventory-import-error-${widget.fieldKey}-frame'),
      animation: _pulse,
      builder: (context, child) {
        final animationProgress = _pulse.value;
        final wave = animationProgress <= .5
            ? animationProgress * 2
            : (1 - animationProgress) * 2;
        final opacity = !widget.missing
            ? widget.warning
                  ? .92
                  : 0.0
            : reduceMotion || widget.pulseToken == 0
            ? .72
            : .58 + (.42 * wave);
        final frameColor = widget.missing
            ? spec.palette.danger
            // The Sakura warning token is intentionally copper-toned, which
            // is too close to the normal rose field border in this dense
            // review. Blend it toward clear amber so uncertain automatic
            // answers are actually visible without marking decisive rows.
            : Color.lerp(spec.palette.warning, const Color(0xFFFFC857), .62)!;
        return DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: _decoration(frameColor, opacity, spec),
          child: child,
        );
      },
      child: widget.child,
    );
  }

  BoxDecoration _decoration(Color danger, double opacity, ThemeSpec spec) =>
      BoxDecoration(
        border: Border.all(
          color: danger.withValues(alpha: opacity.clamp(0.0, 1.0).toDouble()),
          width: 1.8,
        ),
        borderRadius: BorderRadius.circular(spec.geometry.fieldRadius + 1),
      );
}

int _compareRows(_ReviewRow left, _ReviewRow right) {
  final screenshot = left.screenshotOrder.compareTo(right.screenshotOrder);
  if (screenshot != 0) return screenshot;
  final row = left.source.row.compareTo(right.source.row);
  if (row != 0) return row;
  final column = left.source.column.compareTo(right.source.column);
  if (column != 0) return column;
  return left.source.id.compareTo(right.source.id);
}

int _compareNames(String left, String right) =>
    left.toLowerCase().compareTo(right.toLowerCase());

String _fold(String value) => value.trim().toLowerCase();
bool _same(String left, String right) => _fold(left) == _fold(right);
