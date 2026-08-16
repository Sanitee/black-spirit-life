import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../import/screenshot_map_import.dart';
import '../lodging/lodging_data.dart';
import '../model/map_geometry.dart';
import '../model/resource_map_data.dart';
import 'active_node_recording_import_dialog.dart';
import 'draggable_dialog_surface.dart';
import 'resource_map_chrome_theme.dart';

enum BdoSetupScreenshotImportMode { workerNodes, townHouses }

const String _anyScreenshotRegionId = 'anywhere';

final class _ScreenshotRegionPreset {
  const _ScreenshotRegionPreset({
    required this.id,
    required this.label,
    required this.anchorNames,
    required this.radius,
  });

  final String id;
  final String label;
  final List<String> anchorNames;
  final double radius;
}

const List<_ScreenshotRegionPreset> _screenshotRegionPresets =
    <_ScreenshotRegionPreset>[
      _ScreenshotRegionPreset(
        id: 'balenos',
        label: 'Balenos',
        anchorNames: <String>['Velia', 'Olvia', 'Iliya Island'],
        radius: 250000,
      ),
      _ScreenshotRegionPreset(
        id: 'serendia',
        label: 'Serendia',
        anchorNames: <String>['Heidel', 'Glish'],
        radius: 230000,
      ),
      _ScreenshotRegionPreset(
        id: 'calpheon',
        label: 'Calpheon',
        anchorNames: <String>['Calpheon', 'Port Epheria', 'Trent'],
        radius: 300000,
      ),
      _ScreenshotRegionPreset(
        id: 'mediah',
        label: 'Mediah',
        anchorNames: <String>['Altinova', 'Tarif', 'Kusha'],
        radius: 280000,
      ),
      _ScreenshotRegionPreset(
        id: 'valencia',
        label: 'Valencia',
        anchorNames: <String>['Valencia City', 'Sand Grain Bazaar', 'Shakatu'],
        radius: 520000,
      ),
      _ScreenshotRegionPreset(
        id: 'kamasylvia',
        label: 'Kamasylvia',
        anchorNames: <String>['Gr\u00E1na', 'Old Wisdom Tree'],
        radius: 300000,
      ),
      _ScreenshotRegionPreset(
        id: 'drieghan',
        label: 'Drieghan',
        anchorNames: <String>['Duvencrune'],
        radius: 270000,
      ),
      _ScreenshotRegionPreset(
        id: 'odyllita',
        label: "O'dyllita",
        anchorNames: <String>["O'draxxia"],
        radius: 280000,
      ),
      _ScreenshotRegionPreset(
        id: 'winter',
        label: 'Mountain of Eternal Winter',
        anchorNames: <String>['Eilton'],
        radius: 260000,
      ),
      _ScreenshotRegionPreset(
        id: 'ulukita',
        label: 'Ulukita',
        anchorNames: <String>['Asparkan', 'Muzgar'],
        radius: 280000,
      ),
      _ScreenshotRegionPreset(
        id: 'morning-light',
        label: 'Land of the Morning Light',
        anchorNames: <String>[
          'Seoul',
          "Nampo's Moodle Village",
          'Dalbeol Village',
          'Bukpo',
        ],
        radius: 330000,
      ),
      _ScreenshotRegionPreset(
        id: 'edania',
        label: 'Edania',
        anchorNames: <String>['Hakinza Sanctuary', 'Shore of Ruins'],
        radius: 260000,
      ),
      _ScreenshotRegionPreset(
        id: 'ocean',
        label: 'Great Ocean & islands',
        anchorNames: <String>["Oquilla's Eye", 'Iliya Island', 'Lema Island'],
        radius: 520000,
      ),
    ];

final class BdoSetupScreenshotImportSelection {
  BdoSetupScreenshotImportSelection({
    required this.mode,
    required Iterable<String> workerNodeIds,
    required Iterable<String> houseIds,
    required Iterable<BdoSetupScreenshotConfirmation> confirmations,
    required this.townNodeId,
  }) : workerNodeIds = Set<String>.unmodifiable(workerNodeIds),
       houseIds = Set<String>.unmodifiable(houseIds),
       confirmations = List<BdoSetupScreenshotConfirmation>.unmodifiable(
         confirmations,
       );

  final BdoSetupScreenshotImportMode mode;
  final Set<String> workerNodeIds;
  final Set<String> houseIds;
  final List<BdoSetupScreenshotConfirmation> confirmations;
  final String? townNodeId;
}

final class BdoSetupScreenshotConfirmation {
  BdoSetupScreenshotConfirmation({
    required this.analysis,
    required Iterable<String> targetIds,
  }) : targetIds = Set<String>.unmodifiable(targetIds);

  final BdoScreenshotAnalysisResult analysis;
  final Set<String> targetIds;
}

class BdoSetupScreenshotImportDialog extends StatefulWidget {
  const BdoSetupScreenshotImportDialog({
    required this.dataset,
    required this.picker,
    required this.existingWorkerNodeIds,
    required this.existingHouseIds,
    this.clipboardReader,
    this.lodgingDataset,
    this.initialMode,
    this.initialTownNodeId,
    this.activeNodeRecordingLauncher,
    this.activeNodeRecordingFinder,
    this.activeNodeRecordingPicker,
    this.activeNodeRecordingScanner,
    super.key,
  });

  final BdoResourceMapDataset dataset;
  final LodgingDataset? lodgingDataset;
  final Future<Uint8List?> Function() picker;
  final Future<Uint8List?> Function()? clipboardReader;
  final Set<String> existingWorkerNodeIds;
  final Set<String> existingHouseIds;
  final BdoSetupScreenshotImportMode? initialMode;
  final String? initialTownNodeId;
  final BdoActiveNodeRecordingLauncher? activeNodeRecordingLauncher;
  final BdoActiveNodeRecordingFinder? activeNodeRecordingFinder;
  final BdoActiveNodeRecordingPicker? activeNodeRecordingPicker;
  final BdoActiveNodeRecordingScanner? activeNodeRecordingScanner;

  @override
  State<BdoSetupScreenshotImportDialog> createState() =>
      _BdoSetupScreenshotImportDialogState();
}

enum _ImportStage { choose, align, review }

enum _ReferenceTap { none, active, inactive }

class _BdoSetupScreenshotImportDialogState
    extends State<BdoSetupScreenshotImportDialog> {
  static const int _maximumDecodedPixels = 16 * 1024 * 1024;
  static const int _maximumDecodedDimension = 4096;

  late BdoSetupScreenshotImportMode? _mode = widget.initialMode;
  late String? _townNodeId = _initialTownNodeId();
  late String _regionId = _initialRegionId();
  _ImportStage _stage = _ImportStage.choose;
  _ReferenceTap _referenceTap = _ReferenceTap.none;
  bool _improveRecognition = false;
  final List<_ScreenshotEntry> _screenshots = <_ScreenshotEntry>[];
  final Map<String, bool> _manualCheckByTargetId = <String, bool>{};
  int _activeScreenshotIndex = -1;
  bool _busy = false;
  String? _error;

  double _gestureStartScale = 1;
  Offset _gestureStartOffset = Offset.zero;
  Offset _gestureBasePoint = Offset.zero;

  String? _initialTownNodeId() {
    final requested = widget.initialTownNodeId;
    if (requested != null &&
        widget.lodgingDataset?.townsByNodeId.containsKey(requested) == true) {
      return requested;
    }
    return null;
  }

  String _initialRegionId() {
    final requested = widget.initialTownNodeId;
    final requestedNode = requested == null
        ? null
        : widget.dataset.workerNodesById[requested];
    if (requestedNode == null) {
      return _anyScreenshotRegionId;
    }
    _ScreenshotRegionPreset? nearest;
    var nearestDistance = double.infinity;
    for (final preset in _availableRegionPresets) {
      for (final anchor in _anchorNodesFor(preset)) {
        final distance = _mapDistanceSquared(
          requestedNode.location.mapPoint,
          anchor.location.mapPoint,
        );
        if (distance < nearestDistance) {
          nearestDistance = distance;
          nearest = preset;
        }
      }
    }
    return nearest?.id ?? _anyScreenshotRegionId;
  }

  List<LodgingTown> get _sortedTowns {
    final values =
        widget.lodgingDataset?.towns.toList(growable: false) ??
        const <LodgingTown>[];
    return values.toList()
      ..sort((left, right) => left.name.compareTo(right.name));
  }

  List<_ScreenshotRegionPreset> get _availableRegionPresets =>
      _screenshotRegionPresets
          .where((preset) => _anchorNodesFor(preset).isNotEmpty)
          .toList(growable: false);

  List<BdoWorkerNode> _anchorNodesFor(_ScreenshotRegionPreset preset) {
    final names = preset.anchorNames.toSet();
    return widget.dataset.workerNodes
        .where((node) => names.contains(node.siteName))
        .toList(growable: false);
  }

  _ScreenshotEntry? get _activeScreenshot =>
      _activeScreenshotIndex >= 0 &&
          _activeScreenshotIndex < _screenshots.length
      ? _screenshots[_activeScreenshotIndex]
      : null;

  @override
  void dispose() {
    for (final screenshot in _screenshots) {
      screenshot.dispose();
    }
    super.dispose();
  }

  Future<void> _pickScreenshot() => _readScreenshot(widget.picker);

  Future<void> _openActiveNodeRecordingImport() async {
    final picker = widget.activeNodeRecordingPicker;
    final scanner = widget.activeNodeRecordingScanner;
    if (picker == null || scanner == null || _busy) return;
    final selectedNodeIds = await showDialog<Set<String>>(
      context: context,
      barrierDismissible: false,
      builder: (context) => BdoActiveNodeRecordingImportDialog(
        dataset: widget.dataset,
        existingNodeIds: widget.existingWorkerNodeIds,
        launchRecording: widget.activeNodeRecordingLauncher,
        findLatestRecording: widget.activeNodeRecordingFinder,
        pickRecording: picker,
        scanRecording: scanner,
      ),
    );
    if (!mounted || selectedNodeIds == null) return;
    Navigator.of(context).pop(
      BdoSetupScreenshotImportSelection(
        mode: BdoSetupScreenshotImportMode.workerNodes,
        workerNodeIds: selectedNodeIds,
        houseIds: const <String>{},
        confirmations: const <BdoSetupScreenshotConfirmation>[],
        townNodeId: null,
      ),
    );
  }

  Future<void> _pasteScreenshot() async {
    final reader = widget.clipboardReader;
    if (reader == null) return;
    await _readScreenshot(
      reader,
      emptyMessage:
          'No screenshot image was found in the clipboard. Copy the image '
          'in Lightshot, then try Paste screenshot again.',
    );
  }

  Future<void> _readScreenshot(
    Future<Uint8List?> Function() source, {
    String? emptyMessage,
  }) async {
    if (_mode == null ||
        (_mode == BdoSetupScreenshotImportMode.workerNodes &&
            _regionId != _anyScreenshotRegionId &&
            !_availableRegionPresets.any((preset) => preset.id == _regionId)) ||
        (_mode == BdoSetupScreenshotImportMode.townHouses &&
            _townNodeId == null)) {
      setState(() {
        _error = _mode == BdoSetupScreenshotImportMode.workerNodes
            ? 'Choose Anywhere / sea, or select a map region first.'
            : 'Choose the town shown in the screenshot first.';
      });
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final bytes = await source();
      if (!mounted || bytes == null) {
        if (mounted) {
          setState(() {
            _busy = false;
            _error = emptyMessage;
          });
        }
        return;
      }
      final screenshot = await _decodeScreenshot(
        bytes,
        mode: _mode!,
        regionId: _regionId,
        townNodeId: _townNodeId,
      );
      if (!mounted) {
        screenshot.dispose();
        return;
      }
      setState(() {
        _screenshots.add(screenshot);
        _activeScreenshotIndex = _screenshots.length - 1;
        _stage = _ImportStage.align;
        _referenceTap = _ReferenceTap.none;
        _busy = false;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _messageForError(error);
      });
    }
  }

  Future<_ScreenshotEntry> _decodeScreenshot(
    Uint8List bytes, {
    required BdoSetupScreenshotImportMode mode,
    required String regionId,
    required String? townNodeId,
  }) async {
    final encodedSize = _encodedImageSize(bytes);
    if (encodedSize == null ||
        encodedSize.width <= 0 ||
        encodedSize.height <= 0) {
      throw const FormatException(
        'The image dimensions could not be read. Use PNG, JPG, WebP or GIF.',
      );
    }
    final downscale = math.min(
      1.0,
      math.min(
        _maximumDecodedDimension /
            math.max(encodedSize.width, encodedSize.height),
        math.sqrt(
          _maximumDecodedPixels / (encodedSize.width * encodedSize.height),
        ),
      ),
    );
    final targetWidth = math.max(1, (encodedSize.width * downscale).round());
    final targetHeight = math.max(1, (encodedSize.height * downscale).round());
    ui.Codec? codec;
    ui.Image? image;
    try {
      codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: targetWidth,
        targetHeight: targetHeight,
        allowUpscaling: false,
      );
      final frame = await codec.getNextFrame();
      image = frame.image;
      final pixelCount = image.width * image.height;
      if (pixelCount > _maximumDecodedPixels) {
        throw const FormatException(
          'That image is too large to inspect safely. Crop it to one region '
          'or one town and try again.',
        );
      }
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (data == null) {
        throw const FormatException(
          'The image could not be read as RGBA data.',
        );
      }
      final raster = BdoScreenshotRaster(
        width: image.width,
        height: image.height,
        rgbaBytes: data.buffer.asUint8List(
          data.offsetInBytes,
          data.lengthInBytes,
        ),
      );
      final targets = _targetsFor(
        mode: mode,
        regionId: regionId,
        townNodeId: townNodeId,
      );
      if (targets.length < 2) {
        throw const FormatException(
          'This map section does not contain enough mapped icons to align.',
        );
      }
      final baseAlignment = _fitTargetsToImage(targets, raster);
      final result = _ScreenshotEntry(
        image: image,
        raster: raster,
        mode: mode,
        regionId: regionId,
        townNodeId: townNodeId,
        targets: targets,
        baseAlignment: baseAlignment,
      );
      image = null;
      return result;
    } finally {
      image?.dispose();
      codec?.dispose();
    }
  }

  List<BdoScreenshotImportTarget> _targetsFor({
    required BdoSetupScreenshotImportMode mode,
    required String regionId,
    required String? townNodeId,
  }) {
    if (mode == BdoSetupScreenshotImportMode.townHouses) {
      final town = widget.lodgingDataset?.townsByNodeId[townNodeId];
      return town == null
          ? const <BdoScreenshotImportTarget>[]
          : town.houses
                .map(BdoScreenshotImportTarget.house)
                .toList(growable: false);
    }
    final values = _workerNodesForRegion(regionId);
    return values
        .map(BdoScreenshotImportTarget.workerNode)
        .toList(growable: false);
  }

  List<BdoWorkerNode> _workerNodesForRegion(String regionId) {
    if (regionId == _anyScreenshotRegionId) {
      return widget.dataset.workerNodes.toList(growable: false);
    }
    final preset = _availableRegionPresets
        .where((candidate) => candidate.id == regionId)
        .firstOrNull;
    if (preset == null) {
      return widget.dataset.workerNodes.toList(growable: false);
    }
    final anchors = _anchorNodesFor(preset);
    final radiusSquared = preset.radius * preset.radius;
    final values = widget.dataset.workerNodes
        .where((node) {
          return anchors.any(
            (anchor) =>
                _mapDistanceSquared(
                  node.location.mapPoint,
                  anchor.location.mapPoint,
                ) <=
                radiusSquared,
          );
        })
        .toList(growable: false);
    return values.length >= 3
        ? values
        : widget.dataset.workerNodes.toList(growable: false);
  }

  BdoScreenshotAlignment _fitTargetsToImage(
    List<BdoScreenshotImportTarget> targets,
    BdoScreenshotRaster raster,
  ) {
    var minimumX = double.infinity;
    var maximumX = double.negativeInfinity;
    var minimumY = double.infinity;
    var maximumY = double.negativeInfinity;
    for (final target in targets) {
      minimumX = math.min(minimumX, target.mapPoint.x);
      maximumX = math.max(maximumX, target.mapPoint.x);
      minimumY = math.min(minimumY, target.mapPoint.y);
      maximumY = math.max(maximumY, target.mapPoint.y);
    }
    final width = math.max(1.0, maximumX - minimumX);
    final height = math.max(1.0, maximumY - minimumY);
    final inset = math.max(22.0, math.min(raster.width, raster.height) * .055);
    final scale = math.min(
      math.max(1.0, raster.width - inset * 2) / width,
      math.max(1.0, raster.height - inset * 2) / height,
    );
    final centerX = (minimumX + maximumX) / 2;
    final centerY = (minimumY + maximumY) / 2;
    Offset project(BdoMapPoint point) => Offset(
      raster.width / 2 + (point.x - centerX) * scale,
      raster.height / 2 + (point.y - centerY) * scale,
    );
    final anchors = _spreadTargets(targets, 6)
        .map(
          (target) => BdoScreenshotAlignmentAnchor(
            mapPoint: target.mapPoint,
            imagePoint: project(target.mapPoint),
          ),
        )
        .toList(growable: false);
    return BdoScreenshotAlignment.fitSimilarity(anchors);
  }

  List<BdoScreenshotImportTarget> _spreadTargets(
    List<BdoScreenshotImportTarget> targets,
    int count,
  ) => BdoScreenshotAlignmentGuides.select(targets, maximumCount: count);

  List<BdoScreenshotImportTarget> _alignmentGuideTargets(
    _ScreenshotEntry screenshot,
  ) {
    if (screenshot.mode == BdoSetupScreenshotImportMode.townHouses) {
      return _spreadTargets(screenshot.targets, 7);
    }
    final mapNodes = screenshot.targets
        .where((target) {
          final node = widget.dataset.workerNodesById[target.id];
          return node != null && !node.isProductionNode && !node.isResourceNode;
        })
        .toList(growable: false);
    return _spreadTargets(
      mapNodes.length >= 3 ? mapNodes : screenshot.targets,
      8,
    );
  }

  BdoScreenshotAlignment _alignmentFor(_ScreenshotEntry screenshot) {
    final center = Offset(
      screenshot.raster.width / 2,
      screenshot.raster.height / 2,
    );
    Offset transformed(BdoMapPoint point) {
      final base = screenshot.baseAlignment.project(point);
      return center +
          (base - center) * screenshot.overlayScale +
          screenshot.overlayOffset;
    }

    final anchors = _spreadTargets(screenshot.targets, 6)
        .map(
          (target) => BdoScreenshotAlignmentAnchor(
            mapPoint: target.mapPoint,
            imagePoint: transformed(target.mapPoint),
          ),
        )
        .toList(growable: false);
    return BdoScreenshotAlignment.fitSimilarity(anchors);
  }

  void _setReference(_ScreenshotEntry screenshot, Offset imagePoint) {
    setState(() {
      switch (_referenceTap) {
        case _ReferenceTap.active:
          screenshot.activeReference = imagePoint;
          _referenceTap = _ReferenceTap.inactive;
        case _ReferenceTap.inactive:
          screenshot.inactiveReference = imagePoint;
          _referenceTap = _ReferenceTap.none;
        case _ReferenceTap.none:
          break;
      }
      screenshot.analysis = null;
      _error = null;
    });
  }

  void _resetAlignment(_ScreenshotEntry screenshot) {
    setState(() {
      screenshot.overlayScale = 1;
      screenshot.overlayOffset = Offset.zero;
      screenshot.activeReference = null;
      screenshot.inactiveReference = null;
      screenshot.analysis = null;
      _referenceTap = _ReferenceTap.none;
      _error = null;
    });
  }

  void _startOverlayGesture(
    ScaleStartDetails details,
    _ScreenshotEntry screenshot,
    Size viewport,
  ) {
    final imagePoint = _imagePointForLocal(
      details.localFocalPoint,
      screenshot,
      viewport,
    );
    if (imagePoint == null) return;
    final center = Offset(
      screenshot.raster.width / 2,
      screenshot.raster.height / 2,
    );
    _gestureStartScale = screenshot.overlayScale;
    _gestureStartOffset = screenshot.overlayOffset;
    _gestureBasePoint =
        center +
        (imagePoint - center - _gestureStartOffset) / _gestureStartScale;
  }

  void _updateOverlayGesture(
    ScaleUpdateDetails details,
    _ScreenshotEntry screenshot,
    Size viewport,
  ) {
    if (_referenceTap != _ReferenceTap.none) return;
    final imagePoint = _imagePointForLocal(
      details.localFocalPoint,
      screenshot,
      viewport,
    );
    if (imagePoint == null) return;
    final center = Offset(
      screenshot.raster.width / 2,
      screenshot.raster.height / 2,
    );
    final nextScale = (_gestureStartScale * details.scale).clamp(
      .18,
      _maximumOverlayScaleFor(screenshot),
    );
    setState(() {
      screenshot.overlayScale = nextScale;
      screenshot.overlayOffset =
          imagePoint - center - (_gestureBasePoint - center) * nextScale;
      screenshot.analysis = null;
    });
  }

  void _zoomOverlay(
    _ScreenshotEntry screenshot,
    Size viewport,
    Offset localPoint,
    double direction,
  ) {
    final imagePoint = _imagePointForLocal(localPoint, screenshot, viewport);
    if (imagePoint == null) return;
    final center = Offset(
      screenshot.raster.width / 2,
      screenshot.raster.height / 2,
    );
    final previousScale = screenshot.overlayScale;
    final nextScale = (previousScale * (direction > 0 ? .90 : 1.11)).clamp(
      .18,
      _maximumOverlayScaleFor(screenshot),
    );
    final basePoint =
        center +
        (imagePoint - center - screenshot.overlayOffset) / previousScale;
    setState(() {
      screenshot.overlayScale = nextScale;
      screenshot.overlayOffset =
          imagePoint - center - (basePoint - center) * nextScale;
      screenshot.analysis = null;
    });
  }

  double _maximumOverlayScaleFor(_ScreenshotEntry screenshot) =>
      screenshot.mode == BdoSetupScreenshotImportMode.workerNodes &&
          screenshot.regionId == _anyScreenshotRegionId
      ? 24
      : 12;

  Future<void> _analyzeActiveScreenshot() async {
    final screenshot = _activeScreenshot;
    if (screenshot == null) return;
    final activeReference = screenshot.activeReference;
    final inactiveReference = screenshot.inactiveReference;
    if (_improveRecognition &&
        ((activeReference == null) != (inactiveReference == null))) {
      setState(() {
        _error =
            'Mark both an invested and an uninvested icon, or turn off the '
            'extra recognition step.';
      });
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    await Future<void>.delayed(Duration.zero);
    try {
      final profile = activeReference != null && inactiveReference != null
          ? BdoScreenshotMapImportEngine.calibrateProfile(
              raster: screenshot.raster,
              kind: screenshot.mode == BdoSetupScreenshotImportMode.workerNodes
                  ? BdoScreenshotTargetKind.workerNode
                  : BdoScreenshotTargetKind.house,
              activeSampleCenters: <Offset>[activeReference],
              inactiveSampleCenters: <Offset>[inactiveReference],
              sampleRadiusPixels:
                  screenshot.mode == BdoSetupScreenshotImportMode.workerNodes
                  ? 14
                  : 16,
            )
          : screenshot.mode == BdoSetupScreenshotImportMode.workerNodes
          ? BdoScreenshotStateProfile.bdoWorkerNodes()
          : BdoScreenshotStateProfile.bdoOwnedHouses();
      final result = BdoScreenshotMapImportEngine.analyze(
        raster: screenshot.raster,
        alignment: _alignmentFor(screenshot),
        profile: profile,
        targets: screenshot.targets,
      );
      if (!mounted) return;
      setState(() {
        screenshot.analysis = result;
        _busy = false;
        _stage = _ImportStage.review;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _messageForError(error);
      });
    }
  }

  bool _isReviewTargetChecked(_ReviewTarget target) =>
      _manualCheckByTargetId[target.id] ??
      (target.highConfidence && !target.alreadySaved && !target.conflict);

  List<_ReviewTarget> get _reviewTargets {
    final byId = <String, List<BdoScreenshotTargetAnalysis>>{};
    for (final screenshot in _screenshots) {
      final analysis = screenshot.analysis;
      if (analysis == null) continue;
      for (final target in analysis.targets) {
        if (target.state == BdoScreenshotTargetState.outsideViewport) continue;
        if (target.state == BdoScreenshotTargetState.inactive) {
          (byId[target.target.id] ??= <BdoScreenshotTargetAnalysis>[]).add(
            target,
          );
          continue;
        }
        if (target.state == BdoScreenshotTargetState.active ||
            target.confidence >= .08 ||
            target.reviewReasons.contains(
              BdoScreenshotReviewReason.overlappingTargets,
            )) {
          (byId[target.target.id] ??= <BdoScreenshotTargetAnalysis>[]).add(
            target,
          );
        }
      }
    }
    final result = <_ReviewTarget>[];
    for (final entry in byId.entries) {
      final evidence = BdoScreenshotEvidence.summarize(entry.value);
      if (evidence == null) continue;
      final best = evidence.primary;
      final alreadySaved =
          best.target.kind == BdoScreenshotTargetKind.workerNode
          ? widget.existingWorkerNodeIds.contains(best.target.id)
          : widget.existingHouseIds.contains(best.target.id);
      result.add(
        _ReviewTarget(
          id: best.target.id,
          label: best.target.label,
          kind: best.target.kind,
          confidence: evidence.confidence,
          highConfidence: evidence.highConfidence,
          conflict: evidence.conflict,
          alreadySaved: alreadySaved,
          uncertain: best.state != BdoScreenshotTargetState.active,
          reviewReasons: best.reviewReasons,
          analysis: _analysisContaining(best),
          supportCount: evidence.supportCount,
        ),
      );
    }
    result.sort((left, right) {
      final bySaved = left.alreadySaved == right.alreadySaved
          ? 0
          : left.alreadySaved
          ? 1
          : -1;
      if (bySaved != 0) return bySaved;
      final byConfidence = right.confidence.compareTo(left.confidence);
      return byConfidence != 0
          ? byConfidence
          : left.label.compareTo(right.label);
    });
    return result;
  }

  BdoScreenshotAnalysisResult _analysisContaining(
    BdoScreenshotTargetAnalysis target,
  ) => _screenshots
      .map((screenshot) => screenshot.analysis)
      .whereType<BdoScreenshotAnalysisResult>()
      .firstWhere(
        (analysis) => identical(analysis.targetsById[target.target.id], target),
      );

  void _confirm() {
    final mode = _mode;
    if (mode == null) return;
    final checkedIds = _reviewTargets
        .where(_isReviewTargetChecked)
        .map((target) => target.id)
        .toSet();
    final confirmationsByAnalysis =
        <BdoScreenshotAnalysisResult, Set<String>>{};
    for (final target in _reviewTargets.where(
      (target) => checkedIds.contains(target.id),
    )) {
      (confirmationsByAnalysis[target.analysis] ??= <String>{}).add(target.id);
    }
    Navigator.of(context).pop(
      BdoSetupScreenshotImportSelection(
        mode: mode,
        workerNodeIds: mode == BdoSetupScreenshotImportMode.workerNodes
            ? checkedIds
            : const <String>{},
        houseIds: mode == BdoSetupScreenshotImportMode.townHouses
            ? checkedIds
            : const <String>{},
        confirmations: <BdoSetupScreenshotConfirmation>[
          for (final entry in confirmationsByAnalysis.entries)
            BdoSetupScreenshotConfirmation(
              analysis: entry.key,
              targetIds: entry.value,
            ),
        ],
        townNodeId: mode == BdoSetupScreenshotImportMode.townHouses
            ? _townNodeId
            : null,
      ),
    );
  }

  void _removeActiveScreenshot() {
    final index = _activeScreenshotIndex;
    if (index < 0 || index >= _screenshots.length) return;
    final removed = _screenshots.removeAt(index);
    removed.dispose();
    setState(() {
      _activeScreenshotIndex = _screenshots.isEmpty
          ? -1
          : math.min(index, _screenshots.length - 1);
      _stage = _screenshots.isEmpty ? _ImportStage.choose : _ImportStage.review;
      _rebuildReviewChecks();
    });
  }

  void _rebuildReviewChecks() {
    final validIds = _reviewTargets.map((target) => target.id).toSet();
    _manualCheckByTargetId.removeWhere((id, _) => !validIds.contains(id));
  }

  void _addAnotherScreenshot() {
    setState(() {
      _stage = _ImportStage.choose;
      _error = null;
      _referenceTap = _ReferenceTap.none;
    });
  }

  @override
  Widget build(BuildContext context) {
    final chrome = context.mapChrome;
    final media = MediaQuery.sizeOf(context);
    final choosing = _stage == _ImportStage.choose;
    final chooseHeight = _screenshots.isEmpty ? 390.0 : 455.0;
    final estimated = Size(
      math
          .min(choosing ? 640 : 980, math.max(520, media.width - 36))
          .toDouble(),
      math
          .min(choosing ? chooseHeight : 760, math.max(410, media.height - 36))
          .toDouble(),
    );
    return DraggableAlertDialog(
      identity: 'setup-screenshot-import-${_mode?.name}-${_stage.name}',
      dialogKey: const ValueKey<String>('setup-screenshot-import-dialog'),
      estimatedSize: estimated,
      insetPadding: const EdgeInsets.all(18),
      backgroundColor: chrome.paper,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: chrome.divider),
      ),
      titlePadding: const EdgeInsets.fromLTRB(22, 18, 12, 0),
      title: Row(
        children: <Widget>[
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: chrome.primary.withValues(alpha: .13),
              borderRadius: BorderRadius.circular(11),
            ),
            alignment: Alignment.center,
            child: Icon(Icons.document_scanner_outlined, color: chrome.primary),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Scan screenshots',
                  style: TextStyle(
                    color: chrome.ink,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  _stageLabel,
                  style: TextStyle(
                    color: chrome.muted,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            key: const ValueKey<String>('setup-screenshot-import-close'),
            tooltip: 'Close',
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
      contentPadding: const EdgeInsets.fromLTRB(22, 14, 22, 6),
      content: SizedBox(
        width: estimated.width - 44,
        height: math.max(250, estimated.height - 126),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (_error case final error?) ...<Widget>[
              _MessageStrip(message: error, error: true),
              const SizedBox(height: 10),
            ],
            Expanded(
              child: AnimatedSwitcher(
                duration: MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : const Duration(milliseconds: 180),
                child: switch (_stage) {
                  _ImportStage.choose => _buildChooseStage(context),
                  _ImportStage.align => _buildAlignStage(context),
                  _ImportStage.review => _buildReviewStage(context),
                },
              ),
            ),
          ],
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(22, 7, 22, 18),
      actions: _buildActions(context),
    );
  }

  String get _stageLabel => switch (_stage) {
    _ImportStage.choose =>
      _screenshots.isEmpty
          ? 'Import your current nodes or owned houses'
          : '${_screenshots.length} part${_screenshots.length == 1 ? '' : 's'} ready to combine',
    _ImportStage.align => 'Line up the map icons',
    _ImportStage.review => 'Review before saving',
  };

  Widget _buildChooseStage(BuildContext context) {
    final chrome = context.mapChrome;
    return SingleChildScrollView(
      key: const ValueKey<String>('setup-screenshot-import-choose'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            'What is shown?',
            style: TextStyle(
              color: chrome.ink,
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Expanded(
                child: _ModeCard(
                  key: const ValueKey<String>('setup-import-mode-nodes'),
                  icon: Icons.hub_outlined,
                  title: 'Worker nodes',
                  detail: 'One or more world-map sections, including the sea.',
                  selected: _mode == BdoSetupScreenshotImportMode.workerNodes,
                  enabled:
                      _screenshots.isEmpty ||
                      _mode == BdoSetupScreenshotImportMode.workerNodes,
                  onTap: () => setState(() {
                    _mode = BdoSetupScreenshotImportMode.workerNodes;
                    _error = null;
                  }),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _ModeCard(
                  key: const ValueKey<String>('setup-import-mode-houses'),
                  icon: Icons.holiday_village_outlined,
                  title: 'Town houses',
                  detail: 'A fully zoomed town view with its house icons.',
                  selected: _mode == BdoSetupScreenshotImportMode.townHouses,
                  enabled:
                      widget.lodgingDataset != null &&
                      (_screenshots.isEmpty ||
                          _mode == BdoSetupScreenshotImportMode.townHouses),
                  onTap: () => setState(() {
                    _mode = BdoSetupScreenshotImportMode.townHouses;
                    _error = null;
                  }),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          if (_mode == BdoSetupScreenshotImportMode.workerNodes) ...<Widget>[
            if (widget.activeNodeRecordingPicker != null &&
                widget.activeNodeRecordingScanner != null) ...<Widget>[
              _buildActiveNodeRecordingChoice(context),
              const SizedBox(height: 14),
              _SectionDivider(label: 'Or scan regional map screenshots'),
              const SizedBox(height: 12),
            ],
            _buildRegionSelector(context),
          ] else if (_mode == BdoSetupScreenshotImportMode.townHouses)
            _buildTownSelector(context),
          if (_mode != null) ...<Widget>[
            const SizedBox(height: 14),
            _MessageStrip(
              message: _mode == BdoSetupScreenshotImportMode.workerNodes
                  ? 'Keep at least three node icons or route lines visible. You can scan several overlapping land or sea sections before saving.'
                  : 'Zoom into the town. Scan several overlapping parts when one image cannot show every house clearly.',
            ),
          ],
          if (_screenshots.isNotEmpty) ...<Widget>[
            const SizedBox(height: 16),
            Text(
              'Parts in this scan',
              style: TextStyle(
                color: chrome.ink,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 7),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: <Widget>[
                for (var index = 0; index < _screenshots.length; index += 1)
                  ActionChip(
                    avatar: Icon(
                      _screenshots[index].mode ==
                              BdoSetupScreenshotImportMode.workerNodes
                          ? Icons.hub_outlined
                          : Icons.home_work_outlined,
                      size: 16,
                    ),
                    label: Text('Screenshot ${index + 1}'),
                    onPressed: () => setState(() {
                      _activeScreenshotIndex = index;
                      _stage = _screenshots[index].analysis == null
                          ? _ImportStage.align
                          : _ImportStage.review;
                    }),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildActiveNodeRecordingChoice(BuildContext context) {
    final chrome = context.mapChrome;
    return DecoratedBox(
      key: const ValueKey<String>('setup-import-active-list-card'),
      decoration: BoxDecoration(
        color: chrome.primary.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: chrome.primary.withValues(alpha: .52)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
        child: Row(
          children: <Widget>[
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: chrome.primary.withValues(alpha: .14),
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: Icon(Icons.video_file_outlined, color: chrome.primary),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Flexible(
                        child: Text(
                          'Activated list recording',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: chrome.ink,
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const SizedBox(width: 7),
                      _CompactTag(label: 'Recommended'),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Scroll the in-game Activated list once. Best for a full setup.',
                    style: TextStyle(
                      color: chrome.muted,
                      fontSize: 10.5,
                      height: 1.25,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            FilledButton.icon(
              key: const ValueKey<String>('setup-import-active-list-open'),
              onPressed: _openActiveNodeRecordingImport,
              icon: const Icon(Icons.video_camera_back_outlined, size: 17),
              label: const Text('Scan list'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRegionSelector(BuildContext context) {
    final chrome = context.mapChrome;
    final values = _availableRegionPresets;
    final anywhere = _regionId == _anyScreenshotRegionId;
    final selected = values
        .where((region) => region.id == _regionId)
        .firstOrNull;
    return Column(
      key: const ValueKey<String>('setup-import-region-selector'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        InkWell(
          key: const ValueKey<String>('setup-import-anywhere-toggle'),
          borderRadius: BorderRadius.circular(12),
          onTap: _screenshots.isNotEmpty
              ? null
              : () => setState(() {
                  _regionId = anywhere ? '' : _anyScreenshotRegionId;
                  _error = null;
                }),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
            child: Row(
              children: <Widget>[
                Checkbox(
                  key: const ValueKey<String>('setup-import-anywhere-checkbox'),
                  value: anywhere,
                  onChanged: _screenshots.isNotEmpty
                      ? null
                      : (value) => setState(() {
                          _regionId = value == true
                              ? _anyScreenshotRegionId
                              : '';
                          _error = null;
                        }),
                ),
                const SizedBox(width: 3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'Anywhere / sea',
                        style: TextStyle(
                          color: chrome.ink,
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        'Use this when the region is unknown or the nodes are offshore.',
                        style: TextStyle(color: chrome.muted, fontSize: 10.5),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        if (!anywhere) ...<Widget>[
          const SizedBox(height: 8),
          _ScreenshotLocationTypeahead(
            key: const ValueKey<String>('setup-import-region-typeahead'),
            fieldKey: const ValueKey<String>('setup-import-region-search'),
            optionsKey: const ValueKey<String>(
              'setup-import-region-suggestions',
            ),
            label: 'Map region',
            hint: 'Type a region, e.g. Calpheon',
            icon: Icons.public_rounded,
            enabled: _screenshots.isEmpty,
            selectedLabel: selected?.label,
            options: <_ScreenshotLocationOption>[
              for (final region in values)
                _ScreenshotLocationOption(id: region.id, label: region.label),
            ],
            optionKeyPrefix: 'setup-import-region-option-',
            onTextChanged: () {
              if (_regionId.isEmpty) return;
              setState(() => _regionId = '');
            },
            onSelected: (option) => setState(() {
              _regionId = option.id;
              _error = null;
            }),
          ),
        ],
      ],
    );
  }

  Widget _buildTownSelector(BuildContext context) {
    final towns = _sortedTowns;
    final selected = towns
        .where((town) => town.townNodeId == _townNodeId)
        .firstOrNull;
    return _ScreenshotLocationTypeahead(
      key: const ValueKey<String>('setup-import-town-selector'),
      fieldKey: const ValueKey<String>('setup-import-town-search'),
      optionsKey: const ValueKey<String>('setup-import-town-suggestions'),
      label: 'Town in the screenshot',
      hint: 'Type a town, e.g. Calpheon',
      icon: Icons.location_city_rounded,
      enabled: _screenshots.isEmpty,
      selectedLabel: selected?.name,
      options: <_ScreenshotLocationOption>[
        for (final town in towns)
          _ScreenshotLocationOption(id: town.townNodeId, label: town.name),
      ],
      optionKeyPrefix: 'setup-import-town-option-',
      onTextChanged: () {
        if (_townNodeId == null) return;
        setState(() => _townNodeId = null);
      },
      onSelected: (option) => setState(() {
        _townNodeId = option.id;
        _error = null;
      }),
    );
  }

  Widget _buildAlignStage(BuildContext context) {
    final screenshot = _activeScreenshot;
    if (screenshot == null) {
      return const SizedBox.shrink(key: ValueKey<String>('setup-import-empty'));
    }
    final chrome = context.mapChrome;
    return Column(
      key: const ValueKey<String>('setup-screenshot-import-align'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                'The labelled rings are alignment guides, not scan results. '
                'Drag and resize them until the names sit on the same map '
                'icons in your screenshot.',
                style: TextStyle(
                  color: chrome.text,
                  fontSize: 12,
                  height: 1.35,
                ),
              ),
            ),
            TextButton.icon(
              key: const ValueKey<String>('setup-import-reset-alignment'),
              onPressed: () => _resetAlignment(screenshot),
              icon: const Icon(Icons.restart_alt_rounded, size: 17),
              label: const Text('Reset'),
            ),
          ],
        ),
        if (screenshot.mode == BdoSetupScreenshotImportMode.workerNodes &&
            screenshot.regionId == _anyScreenshotRegionId) ...<Widget>[
          const SizedBox(height: 6),
          Text(
            'Regional screenshot? Go back and choose its region first. '
            'Anywhere is best for a whole-world or offshore view.',
            style: TextStyle(
              color: chrome.primary,
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              height: 1.3,
            ),
          ),
        ],
        const SizedBox(height: 8),
        Expanded(child: _buildScreenshotPreview(context, screenshot)),
        const SizedBox(height: 10),
        SwitchListTile.adaptive(
          key: const ValueKey<String>('setup-import-improve-recognition'),
          value: _improveRecognition,
          onChanged: (value) => setState(() {
            _improveRecognition = value;
            if (!value) _referenceTap = _ReferenceTap.none;
          }),
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: Text(
            'Improve recognition for unusual map colors',
            style: TextStyle(
              color: chrome.ink,
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
            ),
          ),
          subtitle: Text(
            'Optional. The normal BDO node and house colors are recognized automatically.',
            style: TextStyle(color: chrome.muted, fontSize: 10.5),
          ),
        ),
        if (_improveRecognition) ...<Widget>[
          const SizedBox(height: 7),
          Row(
            children: <Widget>[
              Expanded(
                child: _ReferenceButton(
                  key: const ValueKey<String>('setup-import-active-reference'),
                  icon: Icons.check_circle_rounded,
                  label: screenshot.activeReference == null
                      ? 'Mark an invested icon'
                      : 'Invested icon marked',
                  selected: _referenceTap == _ReferenceTap.active,
                  complete: screenshot.activeReference != null,
                  onPressed: () => setState(() {
                    _referenceTap = _referenceTap == _ReferenceTap.active
                        ? _ReferenceTap.none
                        : _ReferenceTap.active;
                  }),
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: _ReferenceButton(
                  key: const ValueKey<String>(
                    'setup-import-inactive-reference',
                  ),
                  icon: Icons.radio_button_unchecked_rounded,
                  label: screenshot.inactiveReference == null
                      ? 'Mark an uninvested icon'
                      : 'Uninvested icon marked',
                  selected: _referenceTap == _ReferenceTap.inactive,
                  complete: screenshot.inactiveReference != null,
                  onPressed: () => setState(() {
                    _referenceTap = _referenceTap == _ReferenceTap.inactive
                        ? _ReferenceTap.none
                        : _ReferenceTap.inactive;
                  }),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildScreenshotPreview(
    BuildContext context,
    _ScreenshotEntry screenshot,
  ) {
    final chrome = context.mapChrome;
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewport = Size(constraints.maxWidth, constraints.maxHeight);
        return DecoratedBox(
          key: const ValueKey<String>('setup-import-screenshot-preview'),
          decoration: BoxDecoration(
            color: const Color(0xFF071311),
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: chrome.divider),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Listener(
              onPointerSignal: (event) {
                if (event is PointerScrollEvent &&
                    _referenceTap == _ReferenceTap.none) {
                  _zoomOverlay(
                    screenshot,
                    viewport,
                    event.localPosition,
                    event.scrollDelta.dy,
                  );
                }
              },
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: (details) {
                  if (_referenceTap == _ReferenceTap.none) return;
                  final point = _imagePointForLocal(
                    details.localPosition,
                    screenshot,
                    viewport,
                  );
                  if (point != null) _setReference(screenshot, point);
                },
                onScaleStart: (details) =>
                    _startOverlayGesture(details, screenshot, viewport),
                onScaleUpdate: (details) =>
                    _updateOverlayGesture(details, screenshot, viewport),
                child: Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    RawImage(image: screenshot.image, fit: BoxFit.contain),
                    IgnorePointer(
                      child: CustomPaint(
                        painter: _ScreenshotAlignmentPainter(
                          alignment: _alignmentFor(screenshot),
                          targets: _alignmentGuideTargets(screenshot),
                          imageSize: Size(
                            screenshot.raster.width.toDouble(),
                            screenshot.raster.height.toDouble(),
                          ),
                          displayRect: _imageDisplayRect(viewport, screenshot),
                          activeReference: screenshot.activeReference,
                          inactiveReference: screenshot.inactiveReference,
                          primary: chrome.primary,
                          ink: chrome.ink,
                        ),
                      ),
                    ),
                    if (_referenceTap != _ReferenceTap.none)
                      Positioned(
                        left: 12,
                        top: 12,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: const Color(0xE8162421),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: chrome.primary),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 11,
                              vertical: 7,
                            ),
                            child: Text(
                              _referenceTap == _ReferenceTap.active
                                  ? 'Click the center of an invested icon'
                                  : 'Click the center of an uninvested icon',
                              style: TextStyle(
                                color: chrome.ink,
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildReviewStage(BuildContext context) {
    final chrome = context.mapChrome;
    final targets = _reviewTargets;
    final recognized = targets.where((target) => !target.uncertain).length;
    final needsReview = targets
        .where((target) => target.uncertain || target.conflict)
        .length;
    final alreadySaved = targets.where((target) => target.alreadySaved).length;
    return Column(
      key: const ValueKey<String>('setup-screenshot-import-review'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Wrap(
          spacing: 8,
          runSpacing: 7,
          children: <Widget>[
            _ReviewSummaryChip(
              icon: Icons.document_scanner_outlined,
              label: '$recognized recognized',
            ),
            _ReviewSummaryChip(
              icon: Icons.visibility_outlined,
              label: '$needsReview check manually',
              warning: needsReview > 0,
            ),
            _ReviewSummaryChip(
              icon: Icons.bookmark_added_outlined,
              label: '$alreadySaved already saved',
            ),
          ],
        ),
        const SizedBox(height: 9),
        Text(
          'Only checked rows are added. Existing nodes and houses are never removed.',
          style: TextStyle(color: chrome.muted, fontSize: 11.5, height: 1.3),
        ),
        const SizedBox(height: 9),
        Expanded(
          child: targets.isEmpty
              ? _EmptyReview(
                  onBack: () => setState(() => _stage = _ImportStage.align),
                )
              : ListView.separated(
                  key: const ValueKey<String>('setup-import-review-list'),
                  itemCount: targets.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 6),
                  itemBuilder: (context, index) {
                    final target = targets[index];
                    final checked = _isReviewTargetChecked(target);
                    return _ScreenshotReviewRow(
                      key: ValueKey<String>('setup-import-review-${target.id}'),
                      target: target,
                      checked: checked,
                      onChanged: target.alreadySaved
                          ? null
                          : (value) => setState(() {
                              _manualCheckByTargetId[target.id] = value;
                            }),
                    );
                  },
                ),
        ),
      ],
    );
  }

  List<Widget> _buildActions(BuildContext context) {
    final screenshot = _activeScreenshot;
    return switch (_stage) {
      _ImportStage.choose => <Widget>[
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        if (widget.clipboardReader != null)
          OutlinedButton.icon(
            key: const ValueKey<String>('setup-import-paste-screenshot'),
            onPressed: _busy || _mode == null ? null : _pasteScreenshot,
            icon: const Icon(Icons.content_paste_rounded),
            label: const Text('Paste screenshot'),
          ),
        FilledButton.icon(
          key: const ValueKey<String>('setup-import-pick-screenshot'),
          onPressed: _busy || _mode == null ? null : _pickScreenshot,
          icon: _busy
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.add_photo_alternate_outlined),
          label: Text(
            _screenshots.isEmpty ? 'Choose screenshot' : 'Scan another part',
          ),
        ),
      ],
      _ImportStage.align => <Widget>[
        TextButton.icon(
          key: const ValueKey<String>('setup-import-remove-screenshot'),
          onPressed: _busy ? null : _removeActiveScreenshot,
          icon: const Icon(Icons.delete_outline_rounded),
          label: const Text('Remove'),
        ),
        TextButton(
          onPressed: _busy
              ? null
              : () => setState(() => _stage = _ImportStage.choose),
          child: const Text('Back'),
        ),
        FilledButton.icon(
          key: const ValueKey<String>('setup-import-analyze'),
          onPressed: _busy || screenshot == null
              ? null
              : _analyzeActiveScreenshot,
          icon: _busy
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.manage_search_rounded),
          label: const Text('Find invested icons'),
        ),
      ],
      _ImportStage.review => <Widget>[
        TextButton.icon(
          key: const ValueKey<String>('setup-import-add-another'),
          onPressed: _busy ? null : _addAnotherScreenshot,
          icon: const Icon(Icons.add_photo_alternate_outlined),
          label: const Text('Scan another part'),
        ),
        TextButton(
          onPressed: _busy
              ? null
              : () => setState(() => _stage = _ImportStage.align),
          child: const Text('Adjust alignment'),
        ),
        FilledButton.icon(
          key: const ValueKey<String>('setup-import-confirm'),
          onPressed: _busy ? null : _confirm,
          icon: const Icon(Icons.add_task_rounded),
          label: Text(
            'Add ${_reviewTargets.where(_isReviewTargetChecked).length} to my setup',
          ),
        ),
      ],
    };
  }

  Rect _imageDisplayRect(Size viewport, _ScreenshotEntry screenshot) {
    final imageAspect = screenshot.raster.width / screenshot.raster.height;
    final viewportAspect = viewport.width / math.max(1, viewport.height);
    if (imageAspect > viewportAspect) {
      final height = viewport.width / imageAspect;
      return Rect.fromLTWH(
        0,
        (viewport.height - height) / 2,
        viewport.width,
        height,
      );
    }
    final width = viewport.height * imageAspect;
    return Rect.fromLTWH(
      (viewport.width - width) / 2,
      0,
      width,
      viewport.height,
    );
  }

  Offset? _imagePointForLocal(
    Offset local,
    _ScreenshotEntry screenshot,
    Size viewport,
  ) {
    final rect = _imageDisplayRect(viewport, screenshot);
    if (!rect.contains(local)) return null;
    return Offset(
      (local.dx - rect.left) / rect.width * screenshot.raster.width,
      (local.dy - rect.top) / rect.height * screenshot.raster.height,
    );
  }

  String _messageForError(Object error) {
    if (error is FormatException) return error.message;
    return 'The screenshot could not be inspected. Use PNG, JPG or WebP and try again.';
  }
}

final class _ScreenshotLocationOption {
  const _ScreenshotLocationOption({required this.id, required this.label});

  final String id;
  final String label;
}

class _ScreenshotLocationTypeahead extends StatefulWidget {
  const _ScreenshotLocationTypeahead({
    required this.fieldKey,
    required this.optionsKey,
    required this.label,
    required this.hint,
    required this.icon,
    required this.enabled,
    required this.options,
    required this.optionKeyPrefix,
    required this.onTextChanged,
    required this.onSelected,
    this.selectedLabel,
    super.key,
  });

  final Key fieldKey;
  final Key optionsKey;
  final String label;
  final String hint;
  final IconData icon;
  final bool enabled;
  final String? selectedLabel;
  final List<_ScreenshotLocationOption> options;
  final String optionKeyPrefix;
  final VoidCallback onTextChanged;
  final ValueChanged<_ScreenshotLocationOption> onSelected;

  @override
  State<_ScreenshotLocationTypeahead> createState() =>
      _ScreenshotLocationTypeaheadState();
}

class _ScreenshotLocationTypeaheadState
    extends State<_ScreenshotLocationTypeahead> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.selectedLabel ?? '',
  );
  late final FocusNode _focusNode = FocusNode();

  @override
  void didUpdateWidget(_ScreenshotLocationTypeahead oldWidget) {
    super.didUpdateWidget(oldWidget);
    final selectedLabel = widget.selectedLabel;
    if (selectedLabel != null && selectedLabel != _controller.text) {
      _controller.value = TextEditingValue(
        text: selectedLabel,
        selection: TextSelection.collapsed(offset: selectedLabel.length),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chrome = context.mapChrome;
    return LayoutBuilder(
      builder: (context, constraints) {
        final menuWidth = constraints.maxWidth;
        return RawAutocomplete<_ScreenshotLocationOption>(
          textEditingController: _controller,
          focusNode: _focusNode,
          displayStringForOption: (option) => option.label,
          optionsViewOpenDirection: OptionsViewOpenDirection.down,
          optionsBuilder: (value) {
            final query = _normalizedSearchText(value.text.trim());
            final matches =
                widget.options
                    .where((option) {
                      if (query.isEmpty) return true;
                      return _normalizedSearchText(
                        option.label,
                      ).contains(query);
                    })
                    .toList(growable: false)
                  ..sort((left, right) {
                    final leftLabel = _normalizedSearchText(left.label);
                    final rightLabel = _normalizedSearchText(right.label);
                    final leftStarts = leftLabel.startsWith(query);
                    final rightStarts = rightLabel.startsWith(query);
                    if (leftStarts != rightStarts) return leftStarts ? -1 : 1;
                    return left.label.compareTo(right.label);
                  });
            return matches.take(6);
          },
          onSelected: widget.onSelected,
          fieldViewBuilder:
              (context, controller, focusNode, onFieldSubmitted) => TextField(
                key: widget.fieldKey,
                controller: controller,
                focusNode: focusNode,
                enabled: widget.enabled,
                textInputAction: TextInputAction.done,
                onChanged: (_) => widget.onTextChanged(),
                onSubmitted: (_) => onFieldSubmitted(),
                decoration: InputDecoration(
                  labelText: widget.label,
                  hintText: widget.hint,
                  prefixIcon: Icon(widget.icon),
                  suffixIcon: const Icon(Icons.search_rounded, size: 19),
                ),
              ),
          optionsViewBuilder: (context, onSelected, options) {
            final values = options.toList(growable: false);
            return Align(
              alignment: Alignment.topLeft,
              child: Material(
                key: widget.optionsKey,
                elevation: 18,
                shadowColor: const Color(0x4A000000),
                color: chrome.paperRaised,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: chrome.divider),
                ),
                clipBehavior: Clip.antiAlias,
                child: SizedBox(
                  width: menuWidth,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 228),
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      shrinkWrap: true,
                      itemCount: values.length,
                      itemBuilder: (context, index) {
                        final option = values[index];
                        final highlighted =
                            AutocompleteHighlightedOption.of(context) == index;
                        return InkWell(
                          key: ValueKey<String>(
                            '${widget.optionKeyPrefix}${option.id}',
                          ),
                          onTap: () => onSelected(option),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 90),
                            color: highlighted
                                ? chrome.primary.withValues(alpha: .14)
                                : Colors.transparent,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 13,
                              vertical: 10,
                            ),
                            child: Text(
                              option.label,
                              style: TextStyle(
                                color: chrome.ink,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

String _normalizedSearchText(String value) => value
    .toLowerCase()
    .replaceAll(RegExp('[\u00e0\u00e1\u00e2\u00e3\u00e4\u00e5]'), 'a')
    .replaceAll(RegExp('[\u00e8\u00e9\u00ea\u00eb]'), 'e')
    .replaceAll(RegExp('[\u00ec\u00ed\u00ee\u00ef]'), 'i')
    .replaceAll(RegExp('[\u00f2\u00f3\u00f4\u00f5\u00f6]'), 'o')
    .replaceAll(RegExp('[\u00f9\u00fa\u00fb\u00fc]'), 'u')
    .replaceAll('\u00f1', 'n')
    .replaceAll('\u00df', 'ss');

class _ScreenshotEntry {
  _ScreenshotEntry({
    required this.image,
    required this.raster,
    required this.mode,
    required this.regionId,
    required this.townNodeId,
    required this.targets,
    required this.baseAlignment,
  });

  final ui.Image image;
  final BdoScreenshotRaster raster;
  final BdoSetupScreenshotImportMode mode;
  final String regionId;
  final String? townNodeId;
  final List<BdoScreenshotImportTarget> targets;
  final BdoScreenshotAlignment baseAlignment;
  double overlayScale = 1;
  Offset overlayOffset = Offset.zero;
  Offset? activeReference;
  Offset? inactiveReference;
  BdoScreenshotAnalysisResult? analysis;

  void dispose() => image.dispose();
}

final class _ReviewTarget {
  const _ReviewTarget({
    required this.id,
    required this.label,
    required this.kind,
    required this.confidence,
    required this.highConfidence,
    required this.conflict,
    required this.alreadySaved,
    required this.uncertain,
    required this.reviewReasons,
    required this.analysis,
    required this.supportCount,
  });

  final String id;
  final String label;
  final BdoScreenshotTargetKind kind;
  final double confidence;
  final bool highConfidence;
  final bool conflict;
  final bool alreadySaved;
  final bool uncertain;
  final Set<BdoScreenshotReviewReason> reviewReasons;
  final BdoScreenshotAnalysisResult analysis;
  final int supportCount;
}

class _ScreenshotAlignmentPainter extends CustomPainter {
  const _ScreenshotAlignmentPainter({
    required this.alignment,
    required this.targets,
    required this.imageSize,
    required this.displayRect,
    required this.activeReference,
    required this.inactiveReference,
    required this.primary,
    required this.ink,
  });

  final BdoScreenshotAlignment alignment;
  final List<BdoScreenshotImportTarget> targets;
  final Size imageSize;
  final Rect displayRect;
  final Offset? activeReference;
  final Offset? inactiveReference;
  final Color primary;
  final Color ink;

  Offset toDisplay(Offset imagePoint) => Offset(
    displayRect.left + imagePoint.dx / imageSize.width * displayRect.width,
    displayRect.top + imagePoint.dy / imageSize.height * displayRect.height,
  );

  @override
  void paint(Canvas canvas, Size size) {
    final fill = Paint()
      ..color = primary.withValues(alpha: .16)
      ..style = PaintingStyle.fill;
    final stroke = Paint()
      ..color = primary.withValues(alpha: .96)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.55;
    final shadow = Paint()
      ..color = const Color(0xB0000000)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.5;
    final labelBackground = Paint()
      ..color = const Color(0xE8171B1A)
      ..style = PaintingStyle.fill;
    for (var index = 0; index < targets.length; index++) {
      final target = targets[index];
      final imagePoint = alignment.project(target.mapPoint);
      if (!Rect.fromLTWH(
        0,
        0,
        imageSize.width,
        imageSize.height,
      ).contains(imagePoint)) {
        continue;
      }
      final point = toDisplay(imagePoint);
      final radius = target.kind == BdoScreenshotTargetKind.house ? 8.2 : 7.2;
      canvas.drawCircle(point, radius, shadow);
      canvas.drawCircle(point, radius, fill);
      canvas.drawCircle(point, radius, stroke);
      canvas.drawCircle(point, 1.9, Paint()..color = primary);

      final textPainter =
          TextPainter(
            text: TextSpan(
              text: '${index + 1}  ${target.label}',
              style: TextStyle(
                color: ink,
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                height: 1.1,
              ),
            ),
            maxLines: 1,
            ellipsis: '…',
            textDirection: TextDirection.ltr,
          )..layout(
            maxWidth: math
                .min(170, math.max(80, displayRect.width * .28))
                .toDouble(),
          );
      var labelLeft = point.dx + radius + 5;
      if (labelLeft + textPainter.width + 12 > displayRect.right) {
        labelLeft = point.dx - radius - 5 - textPainter.width - 12;
      }
      final labelTop = (point.dy - textPainter.height / 2 - 4)
          .clamp(
            displayRect.top,
            math.max(
              displayRect.top,
              displayRect.bottom - textPainter.height - 8,
            ),
          )
          .toDouble();
      final labelRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          labelLeft,
          labelTop,
          textPainter.width + 12,
          textPainter.height + 8,
        ),
        const Radius.circular(7),
      );
      canvas.drawRRect(labelRect, labelBackground);
      canvas.drawRRect(labelRect, stroke);
      textPainter.paint(canvas, Offset(labelLeft + 6, labelTop + 4));
    }
    _drawReference(canvas, activeReference, const Color(0xFF55E2AF));
    _drawReference(canvas, inactiveReference, const Color(0xFFE4E8E6));
  }

  void _drawReference(Canvas canvas, Offset? imagePoint, Color color) {
    if (imagePoint == null) return;
    final point = toDisplay(imagePoint);
    canvas.drawCircle(
      point,
      10,
      Paint()
        ..color = const Color(0xCC000000)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5,
    );
    canvas.drawCircle(
      point,
      9,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
    canvas.drawCircle(point, 2.4, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_ScreenshotAlignmentPainter oldDelegate) =>
      oldDelegate.alignment != alignment ||
      oldDelegate.targets != targets ||
      oldDelegate.displayRect != displayRect ||
      oldDelegate.activeReference != activeReference ||
      oldDelegate.inactiveReference != inactiveReference ||
      oldDelegate.primary != primary ||
      oldDelegate.ink != ink;
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.icon,
    required this.title,
    required this.detail,
    required this.selected,
    required this.onTap,
    this.enabled = true,
    super.key,
  });

  final IconData icon;
  final String title;
  final String detail;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final chrome = context.mapChrome;
    return Material(
      color: selected
          ? chrome.primary.withValues(alpha: .12)
          : chrome.paperRaised,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(13),
        side: BorderSide(
          color: selected ? chrome.primary : chrome.divider,
          width: selected ? 1.4 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: enabled ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.all(13),
          child: Row(
            children: <Widget>[
              Icon(
                icon,
                color: enabled
                    ? selected
                          ? chrome.primary
                          : chrome.text
                    : chrome.muted,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      style: TextStyle(
                        color: enabled ? chrome.ink : chrome.muted,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      detail,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: chrome.muted,
                        fontSize: 10.5,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
              if (selected)
                Icon(
                  Icons.check_circle_rounded,
                  color: chrome.primary,
                  size: 20,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReferenceButton extends StatelessWidget {
  const _ReferenceButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.complete,
    required this.onPressed,
    super.key,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final bool complete;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final chrome = context.mapChrome;
    final color = complete ? chrome.positive : chrome.primary;
    return OutlinedButton.icon(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        backgroundColor: selected ? color.withValues(alpha: .12) : null,
        side: BorderSide(color: selected || complete ? color : chrome.divider),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      ),
      icon: Icon(icon, size: 18),
      label: Text(label, overflow: TextOverflow.ellipsis),
    );
  }
}

class _MessageStrip extends StatelessWidget {
  const _MessageStrip({required this.message, this.error = false});

  final String message;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final chrome = context.mapChrome;
    final color = error ? chrome.error : chrome.primary;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: .42)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
        child: Row(
          children: <Widget>[
            Icon(
              error ? Icons.error_outline_rounded : Icons.info_outline_rounded,
              size: 18,
              color: color,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  color: chrome.text,
                  fontSize: 11.5,
                  height: 1.3,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReviewSummaryChip extends StatelessWidget {
  const _ReviewSummaryChip({
    required this.icon,
    required this.label,
    this.warning = false,
  });

  final IconData icon;
  final String label;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    final chrome = context.mapChrome;
    final color = warning ? chrome.warning : chrome.primary;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: .35)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 15, color: color),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                color: chrome.text,
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScreenshotReviewRow extends StatelessWidget {
  const _ScreenshotReviewRow({
    required this.target,
    required this.checked,
    required this.onChanged,
    super.key,
  });

  final _ReviewTarget target;
  final bool checked;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final chrome = context.mapChrome;
    final confidence = (target.confidence * 100).round().clamp(0, 100);
    final status = target.alreadySaved
        ? 'Already saved'
        : target.conflict
        ? 'Screenshots disagree'
        : target.highConfidence
        ? target.supportCount > 1
              ? 'Confirmed in ${target.supportCount} screenshots'
              : 'Clear match'
        : 'Check on the image';
    final statusColor = target.alreadySaved
        ? chrome.muted
        : target.highConfidence
        ? chrome.positive
        : chrome.warning;
    return Material(
      color: checked
          ? chrome.primary.withValues(alpha: .09)
          : chrome.paperRaised,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(11),
        side: BorderSide(
          color: checked
              ? chrome.primary.withValues(alpha: .65)
              : chrome.divider,
        ),
      ),
      child: CheckboxListTile(
        value: target.alreadySaved ? true : checked,
        onChanged: onChanged == null
            ? null
            : (value) => onChanged!(value ?? false),
        controlAffinity: ListTileControlAffinity.leading,
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 9, vertical: 1),
        secondary: Icon(
          target.kind == BdoScreenshotTargetKind.workerNode
              ? Icons.hub_outlined
              : Icons.home_work_outlined,
          color: statusColor,
          size: 20,
        ),
        title: Text(
          target.label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: chrome.ink,
            fontSize: 12.5,
            fontWeight: FontWeight.w800,
          ),
        ),
        subtitle: Text(
          '$status · $confidence% confidence',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: statusColor,
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _EmptyReview extends StatelessWidget {
  const _EmptyReview({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final chrome = context.mapChrome;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 390),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.center_focus_weak_rounded,
              size: 42,
              color: chrome.muted,
            ),
            const SizedBox(height: 10),
            Text(
              'No reliable invested icons were found in this alignment.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: chrome.ink,
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              'Move the outlined markers more precisely, then run the check again.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: chrome.muted,
                fontSize: 11.5,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onBack,
              icon: const Icon(Icons.tune_rounded),
              label: const Text('Adjust alignment'),
            ),
          ],
        ),
      ),
    );
  }
}

double _mapDistanceSquared(BdoMapPoint first, BdoMapPoint second) {
  final x = first.x - second.x;
  final y = first.y - second.y;
  return x * x + y * y;
}

({int width, int height})? _encodedImageSize(Uint8List bytes) {
  if (bytes.length >= 24 &&
      bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4e &&
      bytes[3] == 0x47) {
    return (
      width: _readUint32BigEndian(bytes, 16),
      height: _readUint32BigEndian(bytes, 20),
    );
  }
  if (bytes.length >= 10 &&
      bytes[0] == 0x47 &&
      bytes[1] == 0x49 &&
      bytes[2] == 0x46) {
    return (
      width: bytes[6] | (bytes[7] << 8),
      height: bytes[8] | (bytes[9] << 8),
    );
  }
  if (bytes.length >= 30 &&
      bytes[0] == 0x52 &&
      bytes[1] == 0x49 &&
      bytes[2] == 0x46 &&
      bytes[8] == 0x57 &&
      bytes[9] == 0x45 &&
      bytes[10] == 0x42 &&
      bytes[11] == 0x50) {
    final chunk = String.fromCharCodes(bytes.sublist(12, 16));
    if (chunk == 'VP8X') {
      return (
        width: 1 + _readUint24LittleEndian(bytes, 24),
        height: 1 + _readUint24LittleEndian(bytes, 27),
      );
    }
    if (chunk == 'VP8L' && bytes.length >= 25 && bytes[20] == 0x2f) {
      final first = bytes[21];
      final second = bytes[22];
      final third = bytes[23];
      final fourth = bytes[24];
      return (
        width: 1 + first + ((second & 0x3f) << 8),
        height: 1 + (second >> 6) + (third << 2) + ((fourth & 0x0f) << 10),
      );
    }
    if (chunk == 'VP8 ' &&
        bytes.length >= 30 &&
        bytes[23] == 0x9d &&
        bytes[24] == 0x01 &&
        bytes[25] == 0x2a) {
      return (
        width: (bytes[26] | (bytes[27] << 8)) & 0x3fff,
        height: (bytes[28] | (bytes[29] << 8)) & 0x3fff,
      );
    }
  }
  if (bytes.length >= 4 && bytes[0] == 0xff && bytes[1] == 0xd8) {
    var offset = 2;
    while (offset + 8 < bytes.length) {
      while (offset < bytes.length && bytes[offset] != 0xff) {
        offset += 1;
      }
      while (offset < bytes.length && bytes[offset] == 0xff) {
        offset += 1;
      }
      if (offset >= bytes.length) break;
      final marker = bytes[offset++];
      if (marker == 0xd8 || marker == 0x01) continue;
      if (marker == 0xd9 || marker == 0xda || offset + 1 >= bytes.length) {
        break;
      }
      final length = (bytes[offset] << 8) | bytes[offset + 1];
      if (length < 2 || offset + length > bytes.length) break;
      final isStartOfFrame = <int>{
        0xc0,
        0xc1,
        0xc2,
        0xc3,
        0xc5,
        0xc6,
        0xc7,
        0xc9,
        0xca,
        0xcb,
        0xcd,
        0xce,
        0xcf,
      }.contains(marker);
      if (isStartOfFrame && length >= 7) {
        return (
          width: (bytes[offset + 5] << 8) | bytes[offset + 6],
          height: (bytes[offset + 3] << 8) | bytes[offset + 4],
        );
      }
      offset += length;
    }
  }
  return null;
}

class _SectionDivider extends StatelessWidget {
  const _SectionDivider({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final chrome = context.mapChrome;
    return Row(
      children: <Widget>[
        Expanded(child: Divider(color: chrome.divider)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Text(
            label,
            style: TextStyle(
              color: chrome.muted,
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Expanded(child: Divider(color: chrome.divider)),
      ],
    );
  }
}

class _CompactTag extends StatelessWidget {
  const _CompactTag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final chrome = context.mapChrome;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: chrome.primary.withValues(alpha: .13),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        child: Text(
          label,
          style: TextStyle(
            color: chrome.primary,
            fontSize: 9,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

int _readUint32BigEndian(Uint8List bytes, int offset) =>
    (bytes[offset] << 24) |
    (bytes[offset + 1] << 16) |
    (bytes[offset + 2] << 8) |
    bytes[offset + 3];

int _readUint24LittleEndian(Uint8List bytes, int offset) =>
    bytes[offset] | (bytes[offset + 1] << 8) | (bytes[offset + 2] << 16);
