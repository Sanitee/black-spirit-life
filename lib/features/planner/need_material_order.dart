import '../../domain/planner/planner_models.dart';

/// Keeps the visible Need First order stable across local plan mutations.
///
/// The planner engine deliberately ranks missing materials by quantity. A
/// substitute can change both a material's name and required quantity, but it
/// still represents the same recipe choice. Matching that stable choice keeps
/// the edited row in place until the user explicitly requests a fresh ranking.
final class NeedMaterialOrder {
  List<_NeedMaterialSnapshot> _previous = const <_NeedMaterialSnapshot>[];
  _PendingSubstitute? _pendingSubstitute;

  /// Records the row the user is actively replacing before the plan rebuilds.
  ///
  /// A selected material can merge into an already-present row. In that case
  /// [MissingMaterial.choice] belongs to only one of the merged requests and
  /// may no longer contain the identity of the choice just edited. Remembering
  /// the command lets the reconciler swap the visible rows instead of losing
  /// the edited row to the engine's quantity sort.
  void stageSubstitute({
    required MissingMaterial source,
    required String selection,
  }) {
    final choice = source.choice;
    if (choice == null) return;
    stageSubstituteChoice(
      parentName: choice.parentName,
      original: choice.original,
      substituteGroup: choice.substituteGroup,
      sourceName: source.name,
      sourceBaseName: choice.baseName,
      selection: selection,
    );
  }

  /// Queue ingredient rows retain the full choice identity even when a Need
  /// First material has merged and exposes another request's [ChoiceMeta].
  void stageSubstituteChoice({
    required String parentName,
    required String original,
    required String substituteGroup,
    required String sourceName,
    required String sourceBaseName,
    required String selection,
  }) {
    final selected = _fold(selection);
    final fromBaseName = _fold(sourceBaseName);
    if (selected.isEmpty || selected == fromBaseName) return;
    _pendingSubstitute = _PendingSubstitute(
      choiceKey: _choiceKeyFor(
        parentName: parentName,
        original: original,
        substituteGroup: substituteGroup,
      ),
      fromName: _fold(sourceName),
      fromBaseName: fromBaseName,
      toBaseName: selected,
    );
  }

  List<MissingMaterial> apply(
    List<MissingMaterial> current, {
    bool useDefaultOrder = false,
  }) {
    if (useDefaultOrder || _previous.isEmpty) {
      if (useDefaultOrder) _pendingSubstitute = null;
      _remember(current);
      return current;
    }

    final remaining = current.toList(growable: true);
    final assigned = List<MissingMaterial?>.filled(_previous.length, null);
    _applyPendingSubstitute(current, remaining, assigned);

    for (var index = 0; index < _previous.length; index += 1) {
      if (assigned[index] != null) continue;
      final match = _bestMatchIndex(remaining, _previous[index]);
      if (match >= 0) assigned[index] = remaining.removeAt(match);
    }
    final ordered = assigned.whereType<MissingMaterial>().toList();
    ordered.addAll(remaining);
    _remember(ordered);
    return List<MissingMaterial>.unmodifiable(ordered);
  }

  void reset() {
    _previous = const <_NeedMaterialSnapshot>[];
    _pendingSubstitute = null;
  }

  void _applyPendingSubstitute(
    List<MissingMaterial> current,
    List<MissingMaterial> remaining,
    List<MissingMaterial?> assigned,
  ) {
    final pending = _pendingSubstitute;
    if (pending == null) return;

    var sourceSlot = _previous.indexWhere(
      (snapshot) => snapshot.matchesSource(pending),
    );
    sourceSlot = sourceSlot >= 0
        ? sourceSlot
        : _previous.indexWhere(
            (snapshot) =>
                snapshot.name == pending.fromName ||
                snapshot.baseName == pending.fromBaseName,
          );
    if (sourceSlot < 0) {
      _pendingSubstitute = null;
      return;
    }

    final exactReplacement = current.indexWhere(
      (material) =>
          _choiceKey(material) == pending.choiceKey &&
          _fold(material.choice?.baseName ?? '') == pending.toBaseName,
    );
    final oldSelectionStillPresent = current.any(
      (material) =>
          _choiceKey(material) == pending.choiceKey &&
          _fold(material.choice?.baseName ?? '') == pending.fromBaseName,
    );
    final namedReplacement = current.indexWhere(
      (material) =>
          _fold(material.name) == pending.toBaseName ||
          _fold(material.choice?.baseName ?? '') == pending.toBaseName,
    );

    // A child can close its chooser before the controller's plan notification
    // reaches this widget. Keep the command pending across that old-plan frame.
    if (exactReplacement < 0 &&
        (oldSelectionStillPresent || namedReplacement < 0)) {
      return;
    }

    final replacement =
        current[exactReplacement >= 0 ? exactReplacement : namedReplacement];
    final replacementIndex = remaining.indexOf(replacement);
    if (replacementIndex < 0) return;
    assigned[sourceSlot] = remaining.removeAt(replacementIndex);

    // If the replacement already had a row, put the remaining old material in
    // that vacated slot. This turns a merge/provenance change into a stable
    // visual swap instead of sending the old or new blood row to the bottom.
    final replacementSlot = _previous.indexWhere(
      (snapshot) =>
          snapshot.name == _fold(replacement.name) &&
          snapshot != _previous[sourceSlot],
    );
    if (replacementSlot >= 0) {
      final oldMaterialIndex = remaining.indexWhere(
        (material) =>
            _fold(material.name) == pending.fromName ||
            _fold(material.choice?.baseName ?? '') == pending.fromBaseName,
      );
      if (oldMaterialIndex >= 0) {
        assigned[replacementSlot] = remaining.removeAt(oldMaterialIndex);
      }
    }
    _pendingSubstitute = null;
  }

  void _remember(Iterable<MissingMaterial> materials) {
    _previous = materials
        .map(_NeedMaterialSnapshot.fromMaterial)
        .toList(growable: false);
  }
}

int _bestMatchIndex(
  List<MissingMaterial> materials,
  _NeedMaterialSnapshot previous,
) {
  var bestIndex = -1;
  var bestScore = 0;
  for (var index = 0; index < materials.length; index += 1) {
    final score = previous.matchScore(materials[index]);
    if (score <= bestScore) continue;
    bestIndex = index;
    bestScore = score;
  }
  return bestIndex;
}

final class _NeedMaterialSnapshot {
  const _NeedMaterialSnapshot({
    required this.name,
    required this.baseName,
    required this.choiceKey,
  });

  factory _NeedMaterialSnapshot.fromMaterial(MissingMaterial material) =>
      _NeedMaterialSnapshot(
        name: _fold(material.name),
        baseName: _fold(material.choice?.baseName ?? ''),
        choiceKey: _choiceKey(material),
      );

  final String name;
  final String baseName;
  final String? choiceKey;

  int matchScore(MissingMaterial material) {
    final sameName = name == _fold(material.name);
    final sameChoice = choiceKey != null && choiceKey == _choiceKey(material);
    if (sameChoice && sameName) return 4;
    if (sameChoice) return 3;
    if (sameName) return 2;
    return 0;
  }

  bool matchesSource(_PendingSubstitute pending) =>
      choiceKey == pending.choiceKey &&
      (baseName == pending.fromBaseName || name == pending.fromName);
}

final class _PendingSubstitute {
  const _PendingSubstitute({
    required this.choiceKey,
    required this.fromName,
    required this.fromBaseName,
    required this.toBaseName,
  });

  final String choiceKey;
  final String fromName;
  final String fromBaseName;
  final String toBaseName;
}

String? _choiceKey(MissingMaterial material) {
  final choice = material.choice;
  if (choice == null) return null;
  return _choiceKeyFor(
    parentName: choice.parentName,
    original: choice.original,
    substituteGroup: choice.substituteGroup,
  );
}

String _choiceKeyFor({
  required String parentName,
  required String original,
  required String substituteGroup,
}) =>
    '${_fold(parentName)}\u001f'
    '${_fold(substituteGroup)}\u001f'
    '${_fold(original)}';

String _fold(String value) => value.trim().toLowerCase();
