import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../engine/map_camera.dart';
import '../engine/tile_manager.dart';
import '../model/map_geometry.dart';
import '../model/map_visual_style.dart';
import '../model/resource_map_data.dart';
import '../model/tile_source.dart';
import '../network/node_network_models.dart';
import 'resource_map_chrome_theme.dart';
import 'worker_activity_style.dart';

const double _gatheringPointMinimumZoom = 4.15;
const double _maximumWheelZoomStep = 0.75;
const double _closeZoomNodeCollisionDistance = 40;
const int _plannedMarkerPictureMinimumClusterCount = 72;
const double _plannedMarkerPictureMinimumOverscan = 640;
const String _nodeIconPackage = 'bdo_map_core';

typedef BdoNodeIconImageKey = ({
  int sourceIconType,
  bool active,
  bool highlighted,
});

typedef _BdoPaintedNetworkEdge = ({
  String key,
  BdoWorkerNode first,
  BdoWorkerNode second,
});

enum BdoMapHitKind {
  workerNode,
  gatheringSpot,
  gatheringPoint,
  gatheringPointCluster,
  gatheringRoute,
  workerCluster,
}

class BdoMapHit {
  const BdoMapHit({
    required this.kind,
    required this.id,
    this.clusterNodeIds = const <String>[],
    this.clusterPointIds = const <String>[],
    this.clusterBounds,
  });

  final BdoMapHitKind kind;
  final String id;
  final List<String> clusterNodeIds;
  final List<String> clusterPointIds;
  final BdoMapBounds? clusterBounds;
}

class BdoMapCanvas extends StatefulWidget {
  const BdoMapCanvas({
    super.key,
    required this.cameraController,
    required this.tileManager,
    required this.workerNodes,
    required this.workerNodesById,
    required this.gatheringSpots,
    this.gatheringPoints = const <BdoGatheringPoint>[],
    required this.gatheringRoutes,
    required this.showConnections,
    this.showAllNetworkConnections = false,
    this.nodeNetworkEdgeChanges = const <BdoNodeNetworkEdgeChange>[],
    this.nodeNetworkChangeKinds = const <String, BdoNodeNetworkChangeKind>{},
    this.activeNodeIds = const <String>{},
    this.emphasizedNodeIds = const <String>{},
    this.emphasisRevision = 0,
    this.prioritizePlannedNetwork = true,
    this.declutterWorkerLabelsForOutputArtwork = false,
    this.workerOutputArtworkMinimumZoom = double.infinity,
    this.visualStyle = BdoMapVisualStyle.standard,
    this.chromeTheme = ResourceMapChromeThemeData.sakuraCartographer,
    required this.onHit,
    this.onEmptyTap,
    this.selectedNodeId,
    this.selectedSpotId,
    this.selectedPointId,
    this.selectedRouteId,
    this.onViewportChanged,
    this.handlePointerSignals = true,
  });

  final BdoMapCameraController cameraController;
  final BdoTileManager tileManager;
  final List<BdoWorkerNode> workerNodes;
  final Map<String, BdoWorkerNode> workerNodesById;
  final List<BdoGatheringSpot> gatheringSpots;
  final List<BdoGatheringPoint> gatheringPoints;
  final List<BdoGatheringRoute> gatheringRoutes;
  final bool showConnections;
  final bool showAllNetworkConnections;
  final List<BdoNodeNetworkEdgeChange> nodeNetworkEdgeChanges;
  final Map<String, BdoNodeNetworkChangeKind> nodeNetworkChangeKinds;
  final Set<String> activeNodeIds;

  /// Worker nodes matching the open material search.
  ///
  /// These remain emphasized as the user compares individual node details.
  final Set<String> emphasizedNodeIds;

  /// Changes when the same emphasized set should replay its breathing cue.
  final int emphasisRevision;

  /// Keeps a displayed recommendation readable by treating its complete route
  /// as the foreground and reducing the ordinary node-network browse layer.
  ///
  /// This only takes effect while [nodeNetworkEdgeChanges] is non-empty, so
  /// ordinary worker-node browsing and the all-connections layer are unchanged.
  final bool prioritizePlannedNetwork;

  final bool declutterWorkerLabelsForOutputArtwork;
  final double workerOutputArtworkMinimumZoom;
  final BdoMapVisualStyle visualStyle;
  final ResourceMapChromeThemeData chromeTheme;
  final String? selectedNodeId;
  final String? selectedSpotId;
  final String? selectedPointId;
  final String? selectedRouteId;
  final ValueChanged<BdoMapHit> onHit;
  final bool handlePointerSignals;
  final VoidCallback? onEmptyTap;
  final ValueChanged<Size>? onViewportChanged;

  @override
  State<BdoMapCanvas> createState() => _BdoMapCanvasState();
}

class _BdoMapCanvasState extends State<BdoMapCanvas>
    with TickerProviderStateMixin {
  late final AnimationController _tileFade;
  late final AnimationController _searchEmphasisPulse;
  late final FocusNode _focusNode;
  BdoMapCamera? _gestureStartCamera;
  BdoMapPoint? _gestureAnchorWorld;
  Offset _doubleTapPosition = Offset.zero;
  Size _viewport = Size.zero;
  late int _lastDecodedTileRevision;
  late int _lastDecodedTileCount;
  final ValueNotifier<int> _tilePaintRevision = ValueNotifier<int>(0);
  Map<BdoNodeIconImageKey, ui.Image> _nodeIconImages =
      const <BdoNodeIconImageKey, ui.Image>{};
  bool _dragging = false;
  BdoMapHitTarget? _hoveredTarget;
  Offset _hoverPosition = Offset.zero;
  BdoMapOverlayLayout? _overlayLayout;
  Set<String>? _plannedNetworkNodeIdsCache;
  List<BdoWorkerNode>? _overlayWorkerNodesCache;
  bool _reduceMotion = false;
  late double _lastUiZoom;

  @override
  void initState() {
    super.initState();
    _tileFade = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
      value: 1,
    );
    _searchEmphasisPulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
      value: .5,
    );
    _lastDecodedTileRevision = widget.tileManager.decodedTileRevision;
    _lastDecodedTileCount = widget.tileManager.decodedTileCount;
    if (_lastDecodedTileRevision > 0) {
      _tileFade.forward(from: 0);
    }
    _focusNode = FocusNode(debugLabel: 'BDO resource map');
    _lastUiZoom = widget.cameraController.camera.zoom;
    widget.cameraController.addListener(_handleCameraChanged);
    widget.tileManager.addListener(_handleTilesChanged);
    _loadNodeIconImages();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (_reduceMotion != reduceMotion) {
      _reduceMotion = reduceMotion;
    }
    _syncSearchEmphasisAnimation();
  }

  @override
  void didUpdateWidget(BdoMapCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    var engineChanged = false;
    final overlaysChanged =
        !identical(oldWidget.workerNodes, widget.workerNodes) ||
        !identical(oldWidget.workerNodesById, widget.workerNodesById) ||
        !identical(oldWidget.gatheringSpots, widget.gatheringSpots) ||
        !identical(oldWidget.gatheringPoints, widget.gatheringPoints) ||
        !identical(oldWidget.gatheringRoutes, widget.gatheringRoutes) ||
        !identical(
          oldWidget.nodeNetworkEdgeChanges,
          widget.nodeNetworkEdgeChanges,
        ) ||
        !identical(
          oldWidget.nodeNetworkChangeKinds,
          widget.nodeNetworkChangeKinds,
        ) ||
        oldWidget.prioritizePlannedNetwork != widget.prioritizePlannedNetwork ||
        !setEquals(oldWidget.emphasizedNodeIds, widget.emphasizedNodeIds) ||
        oldWidget.emphasisRevision != widget.emphasisRevision ||
        oldWidget.selectedNodeId != widget.selectedNodeId;
    if (oldWidget.cameraController != widget.cameraController) {
      oldWidget.cameraController.removeListener(_handleCameraChanged);
      widget.cameraController.addListener(_handleCameraChanged);
      _lastUiZoom = widget.cameraController.camera.zoom;
      engineChanged = true;
    }
    if (oldWidget.tileManager != widget.tileManager) {
      oldWidget.tileManager.removeListener(_handleTilesChanged);
      widget.tileManager.addListener(_handleTilesChanged);
      _lastDecodedTileRevision = widget.tileManager.decodedTileRevision;
      _lastDecodedTileCount = widget.tileManager.decodedTileCount;
      if (_lastDecodedTileRevision > 0) {
        _tileFade.forward(from: 0);
      }
      engineChanged = true;
    }
    if (engineChanged || overlaysChanged) {
      _overlayLayout = null;
      _plannedNetworkNodeIdsCache = null;
      _overlayWorkerNodesCache = null;
      _hoveredTarget = null;
    }
    if (engineChanged) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _requestTiles();
        }
      });
    }
    if (!setEquals(oldWidget.emphasizedNodeIds, widget.emphasizedNodeIds) ||
        oldWidget.emphasisRevision != widget.emphasisRevision ||
        oldWidget.selectedNodeId != widget.selectedNodeId) {
      _syncSearchEmphasisAnimation(restart: true);
    }
  }

  void _syncSearchEmphasisAnimation({bool restart = false}) {
    if (_reduceMotion || widget.emphasizedNodeIds.isEmpty) {
      _searchEmphasisPulse.stop();
      _searchEmphasisPulse.value = widget.emphasizedNodeIds.isEmpty ? 0 : .58;
      return;
    }
    if (restart || !_searchEmphasisPulse.isAnimating) {
      _searchEmphasisPulse.value = 0;
      // Three unhurried breaths draw attention without creating a permanent
      // distraction or an animation that prevents the UI from settling.
      _searchEmphasisPulse.repeat(reverse: true, count: 3);
    }
  }

  @override
  void dispose() {
    widget.cameraController.removeListener(_handleCameraChanged);
    widget.tileManager.removeListener(_handleTilesChanged);
    _tileFade.dispose();
    _searchEmphasisPulse.dispose();
    _tilePaintRevision.dispose();
    _focusNode.dispose();
    for (final image in _nodeIconImages.values) {
      image.dispose();
    }
    super.dispose();
  }

  Future<void> _loadNodeIconImages() async {
    final loaded = <BdoNodeIconImageKey, ui.Image>{};
    try {
      for (
        var sourceIconType = bdoNodeIconTypeMinimum;
        sourceIconType <= bdoNodeIconTypeMaximum;
        sourceIconType += 1
      ) {
        for (final active in const <bool>[false, true]) {
          for (final highlighted in const <bool>[false, true]) {
            final relativePath = bdoNodeIconAssetPath(
              sourceIconType,
              active: active,
              highlighted: highlighted,
            );
            final data = await rootBundle.load(
              'packages/$_nodeIconPackage/$relativePath',
            );
            final codec = await ui.instantiateImageCodec(
              data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
            );
            try {
              final frame = await codec.getNextFrame();
              loaded[(
                    sourceIconType: sourceIconType,
                    active: active,
                    highlighted: highlighted,
                  )] =
                  frame.image;
            } finally {
              codec.dispose();
            }
          }
        }
      }
    } catch (_) {
      for (final image in loaded.values) {
        image.dispose();
      }
      return;
    }
    if (!mounted) {
      for (final image in loaded.values) {
        image.dispose();
      }
      return;
    }
    setState(() {
      final previous = _nodeIconImages;
      _nodeIconImages = Map<BdoNodeIconImageKey, ui.Image>.unmodifiable(loaded);
      for (final image in previous.values) {
        image.dispose();
      }
    });
  }

  void _handleCameraChanged() {
    final hadHover = _hoveredTarget != null;
    final zoom = widget.cameraController.camera.zoom;
    final zoomChanged = zoom != _lastUiZoom;
    _lastUiZoom = zoom;
    // A planned route retains every primary node at fixed zoom. Its cluster
    // membership is world-anchored, so pure pan can translate the layout and
    // inverse-transform hit tests instead of scanning/rebucketing the entire
    // 500-CP plan on every pointer frame.
    if (zoomChanged || !_plannedNetworkFocus) {
      _overlayLayout = null;
    }
    _hoveredTarget = null;
    _requestTiles();
    // The map painter listens to the camera directly, so ordinary panning can
    // stay entirely in the paint pipeline. Rebuild only the small widget
    // layers whose content actually changes with zoom or hover. Search
    // emphasis resolves its layout from the live camera during paint, so an
    // emphasized result no longer turns every pure pan into a full rebuild.
    if (mounted && (zoomChanged || hadHover)) {
      setState(() {});
    }
  }

  void _handleTilesChanged() {
    final revision = widget.tileManager.decodedTileRevision;
    final decodedTileCount = widget.tileManager.decodedTileCount;
    final decodedTilesChanged =
        revision != _lastDecodedTileRevision ||
        decodedTileCount != _lastDecodedTileCount;
    _lastDecodedTileCount = decodedTileCount;
    if (revision != _lastDecodedTileRevision) {
      _lastDecodedTileRevision = revision;
      _tileFade.forward(from: 0);
    }
    if (decodedTilesChanged && mounted) {
      // A decoded tile only needs a repaint. Keeping this out of setState
      // preserves the painter's retained dense-route geometry and avoids a
      // widget rebuild on every image arrival/fade tick.
      _tilePaintRevision.value += 1;
    }
  }

  void _requestTiles() {
    if (_viewport.isEmpty) {
      return;
    }
    widget.tileManager.updateViewport(
      visibleBounds: widget.cameraController.visibleWorldBounds(_viewport),
      zoom: widget.cameraController.tileSource.tileZoomFor(
        widget.cameraController.camera.zoom,
      ),
    );
  }

  void _handleScaleStart(ScaleStartDetails details) {
    _focusNode.requestFocus();
    _gestureStartCamera = widget.cameraController.camera;
    _gestureAnchorWorld = widget.cameraController.screenToWorld(
      details.localFocalPoint,
      _viewport,
    );
    setState(() {
      _dragging = true;
      _hoveredTarget = null;
    });
  }

  void _handleScaleUpdate(ScaleUpdateDetails details) {
    final start = _gestureStartCamera;
    final anchorWorld = _gestureAnchorWorld;
    if (start == null || anchorWorld == null || _viewport.isEmpty) {
      return;
    }
    final zoom = (start.zoom + math.log(details.scale) / math.ln2).clamp(
      widget.cameraController.minimumZoom,
      widget.cameraController.maximumZoom,
    );
    final scale = widget.cameraController.tileSource.scaleForZoom(zoom);
    final center = BdoMapPoint(
      anchorWorld.x -
          (details.localFocalPoint.dx - _viewport.width / 2) / scale,
      anchorWorld.y -
          (details.localFocalPoint.dy - _viewport.height / 2) / scale,
    );
    widget.cameraController.setCamera(
      BdoMapCamera(center: center, zoom: zoom),
      _viewport,
    );
  }

  void _handleScaleEnd(ScaleEndDetails details) {
    _gestureStartCamera = null;
    _gestureAnchorWorld = null;
    setState(() => _dragging = false);
  }

  void _handlePointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || _viewport.isEmpty) {
      return;
    }
    final delta = (-event.scrollDelta.dy / 240)
        .clamp(-_maximumWheelZoomStep, _maximumWheelZoomStep)
        .toDouble();
    if (delta == 0) {
      return;
    }
    widget.cameraController.zoomAround(
      zoom: widget.cameraController.camera.zoom + delta,
      anchor: event.localPosition,
      viewport: _viewport,
    );
  }

  void _handleDoubleTap() {
    widget.cameraController.zoomAround(
      zoom: widget.cameraController.camera.zoom + 1,
      anchor: _doubleTapPosition,
      viewport: _viewport,
    );
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent || _viewport.isEmpty) {
      return KeyEventResult.ignored;
    }
    final logicalKey = event.logicalKey;
    if (logicalKey == LogicalKeyboardKey.add ||
        logicalKey == LogicalKeyboardKey.equal) {
      widget.cameraController.zoomAround(
        zoom: widget.cameraController.camera.zoom + 0.7,
        anchor: _viewport.center(Offset.zero),
        viewport: _viewport,
      );
      return KeyEventResult.handled;
    }
    if (logicalKey == LogicalKeyboardKey.minus ||
        logicalKey == LogicalKeyboardKey.numpadSubtract) {
      widget.cameraController.zoomAround(
        zoom: widget.cameraController.camera.zoom - 0.7,
        anchor: _viewport.center(Offset.zero),
        viewport: _viewport,
      );
      return KeyEventResult.handled;
    }
    if (logicalKey == LogicalKeyboardKey.home ||
        logicalKey == LogicalKeyboardKey.digit0) {
      widget.cameraController.reset(_viewport);
      return KeyEventResult.handled;
    }
    if (logicalKey == LogicalKeyboardKey.escape) {
      widget.onEmptyTap?.call();
      return KeyEventResult.handled;
    }
    final panDelta = switch (logicalKey) {
      LogicalKeyboardKey.arrowLeft => const Offset(80, 0),
      LogicalKeyboardKey.arrowRight => const Offset(-80, 0),
      LogicalKeyboardKey.arrowUp => const Offset(0, 80),
      LogicalKeyboardKey.arrowDown => const Offset(0, -80),
      _ => null,
    };
    if (panDelta != null) {
      widget.cameraController.panBy(panDelta, _viewport);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _handleSemanticsZoom(double delta) {
    if (_viewport.isEmpty) {
      return;
    }
    _focusNode.requestFocus();
    widget.cameraController.zoomAround(
      zoom: widget.cameraController.camera.zoom + delta,
      anchor: _viewport.center(Offset.zero),
      viewport: _viewport,
    );
  }

  String _semanticsZoomValue(double delta) {
    final zoom = (widget.cameraController.camera.zoom + delta).clamp(
      widget.cameraController.minimumZoom,
      widget.cameraController.maximumZoom,
    );
    return 'Zoom ${zoom.toStringAsFixed(1)}';
  }

  String get _semanticsLabel {
    final emphasizedCount = widget.emphasizedNodeIds.length;
    return 'Interactive Black Desert resource map. '
        'Visible: ${_semanticCount(_overlayWorkerNodes.length, 'worker node')}, '
        '${_semanticCount(widget.gatheringSpots.length, 'gathering zone')}, '
        '${_semanticCount(widget.gatheringPoints.length, 'historical gathering point')}, '
        'and ${_semanticCount(widget.gatheringRoutes.length, 'gathering route')}.'
        '${emphasizedCount == 0 ? '' : ' ${_semanticCount(emphasizedCount, 'matching worker node')} highlighted.'}';
  }

  void _handleTapUp(TapUpDetails details) {
    final target = _hitTargetAt(details.localPosition);
    if (target != null) {
      widget.onHit(target.hit);
    } else {
      widget.onEmptyTap?.call();
    }
  }

  void _handleHover(PointerHoverEvent event) {
    final target = _hitTargetAt(event.localPosition);
    if (identical(target, _hoveredTarget)) {
      return;
    }
    setState(() {
      _hoveredTarget = target;
      _hoverPosition = event.localPosition;
    });
  }

  void _handleExit(PointerExitEvent event) {
    if (_hoveredTarget != null) {
      setState(() => _hoveredTarget = null);
    }
  }

  BdoMapHitTarget? _hitTargetAt(Offset position) {
    return _overlayLayoutForCurrentViewport().hitTest(position);
  }

  BdoMapOverlayLayout _overlayLayoutForCurrentViewport() {
    return _overlayLayout ??= BdoMapOverlayLayout(
      cameraController: widget.cameraController,
      viewport: _viewport,
      workerNodes: _overlayWorkerNodes,
      workerNodesById: widget.workerNodesById,
      gatheringSpots: widget.gatheringSpots,
      gatheringPoints: widget.gatheringPoints,
      gatheringRoutes: widget.gatheringRoutes,
      selectedNodeId: widget.selectedNodeId,
      retainAllWorkerNodes: _plannedNetworkFocus,
    );
  }

  bool get _plannedNetworkFocus =>
      widget.prioritizePlannedNetwork &&
      widget.nodeNetworkEdgeChanges.isNotEmpty;

  Set<String> get _plannedNetworkNodeIds =>
      _plannedNetworkNodeIdsCache ??= _plannedNodeIds(
        widget.nodeNetworkEdgeChanges,
        widget.nodeNetworkChangeKinds,
      );

  List<BdoWorkerNode> get _overlayWorkerNodes {
    if (!_plannedNetworkFocus) {
      return widget.workerNodes;
    }
    final cached = _overlayWorkerNodesCache;
    if (cached != null) {
      return cached;
    }
    final plannedNodeIds = _plannedNetworkNodeIds;
    return _overlayWorkerNodesCache = widget.workerNodes
        .where(
          (node) =>
              plannedNodeIds.contains(node.id) &&
              _isPlannedNetworkPrimaryNode(
                node,
                changeKinds: widget.nodeNetworkChangeKinds,
                selectedNodeId: widget.selectedNodeId,
              ),
        )
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final nextViewport = Size(constraints.maxWidth, constraints.maxHeight);
        if (nextViewport != _viewport && !nextViewport.isEmpty) {
          _viewport = nextViewport;
          _overlayLayout = null;
          _hoveredTarget = null;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) {
              return;
            }
            widget.onViewportChanged?.call(_viewport);
            _requestTiles();
          });
        }
        return ClipRect(
          key: const ValueKey<String>('bdo-map-canvas-viewport-clip'),
          clipBehavior: Clip.hardEdge,
          child: Semantics(
            container: true,
            focusable: true,
            label: _semanticsLabel,
            value:
                'Zoom ${widget.cameraController.camera.zoom.toStringAsFixed(1)}',
            increasedValue: _semanticsZoomValue(0.7),
            decreasedValue: _semanticsZoomValue(-0.7),
            hint:
                'Click or tap a marker for details. Drag or use the arrow keys '
                'to pan; use the mouse wheel, double-click, plus and minus, or '
                'the accessibility increase and decrease actions to zoom. '
                'Home resets the map and Escape closes details.',
            onIncrease: () => _handleSemanticsZoom(0.7),
            onDecrease: () => _handleSemanticsZoom(-0.7),
            child: Focus(
              focusNode: _focusNode,
              autofocus: true,
              onKeyEvent: _handleKeyEvent,
              child: MouseRegion(
                cursor: _dragging
                    ? SystemMouseCursors.grabbing
                    : _hoveredTarget != null
                    ? SystemMouseCursors.click
                    : SystemMouseCursors.grab,
                onHover: _handleHover,
                onExit: _handleExit,
                child: Listener(
                  onPointerSignal: widget.handlePointerSignals
                      ? _handlePointerSignal
                      : null,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onScaleStart: _handleScaleStart,
                    onScaleUpdate: _handleScaleUpdate,
                    onScaleEnd: _handleScaleEnd,
                    onDoubleTapDown: (details) {
                      _doubleTapPosition = details.localPosition;
                    },
                    onDoubleTap: _handleDoubleTap,
                    onTapUp: _handleTapUp,
                    child: Stack(
                      fit: StackFit.expand,
                      children: <Widget>[
                        RepaintBoundary(
                          child: CustomPaint(
                            painter: BdoMapPainter(
                              repaint: Listenable.merge(<Listenable>[
                                widget.cameraController,
                                _tileFade,
                                _tilePaintRevision,
                              ]),
                              cameraController: widget.cameraController,
                              tileManager: widget.tileManager,
                              workerNodes: widget.workerNodes,
                              workerNodesById: widget.workerNodesById,
                              gatheringSpots: widget.gatheringSpots,
                              gatheringPoints: widget.gatheringPoints,
                              gatheringRoutes: widget.gatheringRoutes,
                              showConnections: widget.showConnections,
                              showAllNetworkConnections:
                                  widget.showAllNetworkConnections,
                              nodeNetworkEdgeChanges:
                                  widget.nodeNetworkEdgeChanges,
                              nodeNetworkChangeKinds:
                                  widget.nodeNetworkChangeKinds,
                              activeNodeIds: widget.activeNodeIds,
                              emphasizedNodeIds: widget.emphasizedNodeIds,
                              nodeIconImages: _nodeIconImages,
                              prioritizePlannedNetwork:
                                  widget.prioritizePlannedNetwork,
                              declutterWorkerLabelsForOutputArtwork:
                                  widget.declutterWorkerLabelsForOutputArtwork,
                              workerOutputArtworkMinimumZoom:
                                  widget.workerOutputArtworkMinimumZoom,
                              visualStyle: widget.visualStyle,
                              chromeTheme: widget.chromeTheme,
                              selectedNodeId: widget.selectedNodeId,
                              selectedSpotId: widget.selectedSpotId,
                              selectedPointId: widget.selectedPointId,
                              selectedRouteId: widget.selectedRouteId,
                              colorScheme: Theme.of(context).colorScheme,
                              overlayLayoutProvider:
                                  _overlayLayoutForCurrentViewport,
                              overlayLayout: _overlayLayoutForCurrentViewport(),
                              tilePaintRevision: _tilePaintRevision.value,
                              tilePaintRevisionListenable: _tilePaintRevision,
                              tileFadeProgress: _tileFade.value,
                            ),
                            size: Size.infinite,
                          ),
                        ),
                        if (widget.emphasizedNodeIds.isNotEmpty)
                          RepaintBoundary(
                            key: const ValueKey<String>(
                              'bdo-map-search-emphasis-boundary',
                            ),
                            child: IgnorePointer(
                              child: AnimatedBuilder(
                                animation: _searchEmphasisPulse,
                                builder: (context, child) {
                                  return CustomPaint(
                                    key: const ValueKey<String>(
                                      'bdo-map-search-emphasis-paint',
                                    ),
                                    painter: BdoMapSearchEmphasisPainter(
                                      overlayLayoutProvider:
                                          _overlayLayoutForCurrentViewport,
                                      emphasizedNodeIds:
                                          widget.emphasizedNodeIds,
                                      selectedNodeId: widget.selectedNodeId,
                                      pulse: _searchEmphasisPulse.value,
                                      chromeTheme: widget.chromeTheme,
                                      repaint: widget.cameraController,
                                    ),
                                    size: Size.infinite,
                                  );
                                },
                              ),
                            ),
                          ),
                        if (_hoveredTarget != null)
                          _MapHoverLabel(
                            viewport: _viewport,
                            pointer: _hoverPosition,
                            label: _hoveredTarget!.label,
                            chromeTheme: widget.chromeTheme,
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Lightweight foreground rings for nodes matched by the current search.
///
/// Keeping this in its own repaint boundary means the breathing animation
/// never redraws basemap tiles, network lines, labels, or gathering artwork.
class BdoMapSearchEmphasisPainter extends CustomPainter {
  BdoMapSearchEmphasisPainter({
    this.overlayLayout,
    this.overlayLayoutProvider,
    required this.emphasizedNodeIds,
    required this.selectedNodeId,
    required this.pulse,
    this.chromeTheme = ResourceMapChromeThemeData.sakuraCartographer,
    super.repaint,
  }) : assert(
         overlayLayout != null || overlayLayoutProvider != null,
         'Provide an overlay layout or a live overlay layout provider.',
       );

  final BdoMapOverlayLayout? overlayLayout;
  final BdoMapOverlayLayout Function()? overlayLayoutProvider;
  final Set<String> emphasizedNodeIds;
  final String? selectedNodeId;
  final double pulse;
  final ResourceMapChromeThemeData chromeTheme;

  @override
  void paint(Canvas canvas, Size size) {
    final resolvedOverlayLayout =
        overlayLayoutProvider?.call() ?? overlayLayout!;
    final easedPulse = Curves.easeInOut.transform(pulse.clamp(0.0, 1.0));
    for (final cluster in resolvedOverlayLayout.nodeClusters) {
      if (!cluster.nodes.any((node) => emphasizedNodeIds.contains(node.id))) {
        continue;
      }
      final selected = cluster.nodes.any((node) => node.id == selectedNodeId);
      final markerRadius = cluster.nodes.length > 1
          ? cluster.singleActivity == null
                ? 15.0
                : 14.0
          : selected
          ? 13.0
          : 10.5;
      final color = selected ? chromeTheme.accent : chromeTheme.primary;
      final innerRadius = markerRadius + (selected ? 5.5 : 4.5);
      final outerRadius = innerRadius + 4 + easedPulse * (selected ? 7.5 : 6.0);
      final position = resolvedOverlayLayout.livePositionFor(cluster.position);
      if (!_screenContains(position, size, padding: outerRadius + 4)) {
        continue;
      }

      canvas.drawCircle(
        position,
        outerRadius,
        Paint()
          ..color = color.withAlpha(selected ? 92 : 76)
          ..style = PaintingStyle.stroke
          ..strokeWidth = selected ? 5.2 : 4.4
          ..maskFilter = MaskFilter.blur(
            BlurStyle.normal,
            selected ? 4.8 : 4.0,
          ),
      );
      canvas.drawCircle(
        position,
        outerRadius,
        Paint()
          ..color = color.withAlpha(selected ? 230 : 205)
          ..style = PaintingStyle.stroke
          ..strokeWidth = selected ? 2.5 : 2.0,
      );
      canvas.drawCircle(
        position,
        innerRadius,
        Paint()
          ..color = color.withAlpha(selected ? 255 : 232)
          ..style = PaintingStyle.stroke
          ..strokeWidth = selected ? 2.2 : 1.7,
      );
    }
  }

  @override
  bool shouldRepaint(covariant BdoMapSearchEmphasisPainter oldDelegate) {
    return !identical(oldDelegate.overlayLayout, overlayLayout) ||
        !identical(oldDelegate.overlayLayoutProvider, overlayLayoutProvider) ||
        !setEquals(oldDelegate.emphasizedNodeIds, emphasizedNodeIds) ||
        oldDelegate.selectedNodeId != selectedNodeId ||
        oldDelegate.pulse != pulse ||
        oldDelegate.chromeTheme != chromeTheme;
  }
}

String _semanticCount(int count, String singular) {
  return '$count $singular${count == 1 ? '' : 's'}';
}

String _overviewGatheringLabel(String name) {
  for (final suffix in const <String>[
    ' Hunting Zone (Approx.)',
    ' Zone (Approx.)',
    ' Area',
  ]) {
    if (name.endsWith(suffix)) {
      return name.substring(0, name.length - suffix.length);
    }
  }
  return name;
}

String _workerNodeSiteName(
  BdoWorkerNode node,
  Map<String, BdoWorkerNode> workerNodesById,
) {
  if (node.siteName != node.name) {
    return node.siteName;
  }
  final parent = node.parentId == null ? null : workerNodesById[node.parentId!];
  return parent?.siteName ?? node.siteName;
}

String _workerNodeLabel(
  BdoWorkerNode node,
  Map<String, BdoWorkerNode> workerNodesById,
) {
  if (!node.isResourceNode) {
    return node.name;
  }
  final siteName = _workerNodeSiteName(node, workerNodesById);
  BdoNodeOutput? primaryOutput;
  for (final output in node.outputs) {
    primaryOutput ??= output;
    if (output.isPrimary) {
      primaryOutput = output;
      break;
    }
  }
  return primaryOutput == null
      ? '$siteName \u00B7 ${node.activityLabel}'
      : '${primaryOutput.name} \u00B7 $siteName';
}

IconData _workerNodeIcon(BdoWorkerNode node) {
  return node.isResourceNode
      ? bdoWorkerActivityIcon(node.activity)
      : Icons.account_balance_outlined;
}

Color _workerNodeColor(BdoWorkerNode node) {
  return node.isResourceNode
      ? bdoWorkerActivityColor(node.activity)
      : const Color(0xFFC8D0C8);
}

class _MapHoverLabel extends StatelessWidget {
  const _MapHoverLabel({
    required this.viewport,
    required this.pointer,
    required this.label,
    required this.chromeTheme,
  });

  final Size viewport;
  final Offset pointer;
  final String label;
  final ResourceMapChromeThemeData chromeTheme;

  @override
  Widget build(BuildContext context) {
    final width = math.max(0.0, math.min(260.0, viewport.width - 16));
    final maxLeft = math.max(8.0, viewport.width - width - 8);
    final left = (pointer.dx + 16).clamp(8.0, maxLeft).toDouble();
    final above = pointer.dy - 42;
    final top = (above >= 8 ? above : pointer.dy + 18)
        .clamp(8.0, math.max(8.0, viewport.height - 40))
        .toDouble();
    return Positioned(
      left: left,
      top: top,
      width: width,
      child: IgnorePointer(
        child: Align(
          alignment: Alignment.centerLeft,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: chromeTheme.chromeRaised.withAlpha(242),
              borderRadius: BorderRadius.circular(chromeTheme.inlineRadius),
              border: Border.all(color: chromeTheme.warmOutline),
              boxShadow: <BoxShadow>[chromeTheme.idleShadow],
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: chromeTheme.ink,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class BdoMapOverlayLayout {
  BdoMapOverlayLayout({
    required this.cameraController,
    required this.viewport,
    required this.workerNodes,
    this.workerNodesById = const <String, BdoWorkerNode>{},
    required this.gatheringSpots,
    this.gatheringPoints = const <BdoGatheringPoint>[],
    required this.gatheringRoutes,
    this.selectedNodeId,
    this.retainAllWorkerNodes = false,
  }) : cameraSnapshot = cameraController.camera,
       tileSourceSnapshot = cameraController.tileSource;

  static const double _hitIndexCellSize = 48;

  final BdoMapCameraController cameraController;
  final Size viewport;
  final List<BdoWorkerNode> workerNodes;
  final Map<String, BdoWorkerNode> workerNodesById;
  final List<BdoGatheringSpot> gatheringSpots;
  final List<BdoGatheringPoint> gatheringPoints;
  final List<BdoGatheringRoute> gatheringRoutes;
  final String? selectedNodeId;
  final bool retainAllWorkerNodes;
  final BdoMapCamera cameraSnapshot;
  final BdoTileSource tileSourceSnapshot;
  late final double _snapshotScale = tileSourceSnapshot.scaleForZoom(
    cameraSnapshot.zoom,
  );

  /// Fixed-zoom translation from retained layout space into the live camera.
  Offset get cameraTranslation {
    final liveCamera = cameraController.camera;
    if (liveCamera.zoom != cameraSnapshot.zoom ||
        !identical(cameraController.tileSource, tileSourceSnapshot)) {
      return Offset.zero;
    }
    return Offset(
      (cameraSnapshot.center.x - liveCamera.center.x) * _snapshotScale,
      (cameraSnapshot.center.y - liveCamera.center.y) * _snapshotScale,
    );
  }

  Offset livePositionFor(Offset retainedPosition) =>
      retainedPosition + cameraTranslation;

  Offset _worldToScreen(BdoMapPoint point) {
    return Offset(
      viewport.width / 2 + (point.x - cameraSnapshot.center.x) * _snapshotScale,
      viewport.height / 2 +
          (point.y - cameraSnapshot.center.y) * _snapshotScale,
    );
  }

  late final List<BdoNodeCluster> nodeClusters = _clusterNodes();
  late final List<BdoGatheringPointCluster> gatheringPointClusters =
      _clusterGatheringPoints();

  late final List<BdoMapHitTarget> hitTargets = _buildHitTargets();
  late final Map<(int, int), List<BdoMapHitTarget>> _hitIndex =
      _buildHitIndex();

  BdoMapHitTarget? hitTest(Offset position) {
    final retainedPosition = position - cameraTranslation;
    final key = (
      (retainedPosition.dx / _hitIndexCellSize).floor(),
      (retainedPosition.dy / _hitIndexCellSize).floor(),
    );
    BdoMapHitTarget? best;
    var bestDistance = double.infinity;
    for (final target in _hitIndex[key] ?? const <BdoMapHitTarget>[]) {
      final distance = (target.position - retainedPosition).distance;
      if (distance > target.hitRadius) {
        continue;
      }
      final higherPriority = best == null || target.priority > best.priority;
      final samePriorityAndCloser =
          best != null &&
          target.priority == best.priority &&
          distance < bestDistance;
      if (higherPriority || samePriorityAndCloser) {
        best = target;
        bestDistance = distance;
      }
    }
    return best;
  }

  Map<(int, int), List<BdoMapHitTarget>> _buildHitIndex() {
    final result = <(int, int), List<BdoMapHitTarget>>{};
    for (final target in hitTargets) {
      final minimumX =
          ((target.position.dx - target.hitRadius) / _hitIndexCellSize).floor();
      final maximumX =
          ((target.position.dx + target.hitRadius) / _hitIndexCellSize).floor();
      final minimumY =
          ((target.position.dy - target.hitRadius) / _hitIndexCellSize).floor();
      final maximumY =
          ((target.position.dy + target.hitRadius) / _hitIndexCellSize).floor();
      for (var x = minimumX; x <= maximumX; x++) {
        for (var y = minimumY; y <= maximumY; y++) {
          result.putIfAbsent((x, y), () => <BdoMapHitTarget>[]).add(target);
        }
      }
    }
    return result;
  }

  List<BdoMapHitTarget> _buildHitTargets() {
    final result = <BdoMapHitTarget>[];
    for (final cluster in nodeClusters) {
      if (cluster.nodes.length == 1) {
        result.add(
          BdoMapHitTarget(
            position: cluster.position,
            hitRadius: 20,
            label: _workerNodeLabel(cluster.nodes.single, workerNodesById),
            priority: 30,
            hit: BdoMapHit(
              kind: BdoMapHitKind.workerNode,
              id: cluster.nodes.single.id,
            ),
          ),
        );
      } else {
        final activity = cluster.singleActivity;
        final activityNames =
            cluster.activities.map((entry) => entry.label).toList()..sort();
        final siteNames = cluster.nodes
            .map((node) => _workerNodeSiteName(node, workerNodesById))
            .toSet();
        final label = activity != null && siteNames.length == 1
            ? '${activity.label} \u00B7 ${siteNames.single} \u00B7 '
                  '${cluster.nodes.length} production options'
            : activity != null
            ? '${activity.label} \u00B7 ${cluster.nodes.length} nearby '
                  'worker nodes'
            : activityNames.isEmpty
            ? '${cluster.nodes.length} nearby connection nodes'
            : '${cluster.nodes.length} nearby worker nodes \u00B7 '
                  '${activityNames.take(3).join(', ')}';
        result.add(
          BdoMapHitTarget(
            position: cluster.position,
            hitRadius: 22,
            label: '$label \u00B7 Click to zoom',
            priority: 10,
            hit: BdoMapHit(
              kind: BdoMapHitKind.workerCluster,
              id: 'cluster',
              clusterNodeIds: cluster.nodes
                  .map((node) => node.id)
                  .toList(growable: false),
            ),
          ),
        );
      }
    }
    for (final spot in gatheringSpots) {
      final position = _worldToScreen(spot.location.mapPoint);
      const hitRadius = 19.0;
      if (_screenContains(position, viewport, padding: hitRadius + 32)) {
        result.add(
          BdoMapHitTarget(
            position: position,
            hitRadius: hitRadius,
            label: spot.name,
            priority: 20,
            hit: BdoMapHit(kind: BdoMapHitKind.gatheringSpot, id: spot.id),
          ),
        );
      }
    }
    if (cameraSnapshot.zoom >= _gatheringPointMinimumZoom) {
      for (final point in gatheringPoints) {
        final position = _worldToScreen(point.location.mapPoint);
        if (_screenContains(position, viewport, padding: 18)) {
          result.add(
            BdoMapHitTarget(
              position: position,
              hitRadius: 10,
              label: point.label,
              priority: 40,
              hit: BdoMapHit(kind: BdoMapHitKind.gatheringPoint, id: point.id),
            ),
          );
        }
      }
    } else {
      for (final cluster in gatheringPointClusters) {
        result.add(
          BdoMapHitTarget(
            position: cluster.position,
            hitRadius: 12,
            label:
                '${cluster.points.length} gathering '
                '${cluster.points.length == 1 ? 'location' : 'locations'}'
                ' · Click to zoom',
            priority: 35,
            hit: BdoMapHit(
              kind: BdoMapHitKind.gatheringPointCluster,
              id: cluster.id,
              clusterPointIds: cluster.points
                  .map((point) => point.id)
                  .toList(growable: false),
              clusterBounds: cluster.bounds,
            ),
          ),
        );
      }
    }
    for (final route in gatheringRoutes) {
      for (final waypoint in route.waypoints) {
        final position = _worldToScreen(waypoint.location.mapPoint);
        if (_screenContains(position, viewport, padding: 24)) {
          result.add(
            BdoMapHitTarget(
              position: position,
              hitRadius: 17,
              label: waypoint.label.isEmpty ? route.name : waypoint.label,
              priority: 25,
              hit: BdoMapHit(kind: BdoMapHitKind.gatheringRoute, id: route.id),
            ),
          );
        }
      }
    }
    return result;
  }

  List<BdoGatheringPointCluster> _clusterGatheringPoints() {
    final zoom = cameraSnapshot.zoom;
    if (zoom >= _gatheringPointMinimumZoom || gatheringPoints.isEmpty) {
      return const <BdoGatheringPointCluster>[];
    }
    final worldCellSize = 28 / _snapshotScale;
    final buckets =
        <(int, int), List<({BdoGatheringPoint point, Offset position})>>{};
    for (final point in gatheringPoints) {
      final world = point.location.mapPoint;
      final position = _worldToScreen(world);
      if (!_screenContains(position, viewport, padding: 12)) {
        continue;
      }
      final key = (
        (world.x / worldCellSize).floor(),
        (world.y / worldCellSize).floor(),
      );
      buckets.putIfAbsent(key, () => []).add((
        point: point,
        position: position,
      ));
    }
    return buckets.entries
        .map((entry) {
          var screenX = 0.0;
          var screenY = 0.0;
          var minimumWorldX = double.infinity;
          var minimumWorldY = double.infinity;
          var maximumWorldX = double.negativeInfinity;
          var maximumWorldY = double.negativeInfinity;
          for (final member in entry.value) {
            screenX += member.position.dx;
            screenY += member.position.dy;
            final world = member.point.location.mapPoint;
            minimumWorldX = math.min(minimumWorldX, world.x);
            minimumWorldY = math.min(minimumWorldY, world.y);
            maximumWorldX = math.max(maximumWorldX, world.x);
            maximumWorldY = math.max(maximumWorldY, world.y);
          }
          final pointPadding = math.max(worldCellSize * 0.18, 1.0);
          final key = entry.key;
          return BdoGatheringPointCluster(
            id: 'gathering-point-cluster:${key.$1}:${key.$2}',
            position: Offset(
              screenX / entry.value.length,
              screenY / entry.value.length,
            ),
            points: entry.value
                .map((member) => member.point)
                .toList(growable: false),
            bounds: BdoMapBounds(
              left: minimumWorldX - pointPadding,
              top: minimumWorldY - pointPadding,
              right: maximumWorldX + pointPadding,
              bottom: maximumWorldY + pointPadding,
            ),
          );
        })
        .toList(growable: false);
  }

  List<BdoNodeCluster> _clusterNodes() {
    final zoom = cameraSnapshot.zoom;
    final cellSize = zoom < 2.8
        ? 94.0
        : zoom < 4.1
        ? 74.0
        : zoom < 5.25
        ? 54.0
        : zoom < 6.25
        ? 38.0
        : 0.0;
    final visible = <({BdoWorkerNode node, Offset position})>[];
    for (final node in workerNodes) {
      final position = _worldToScreen(node.location.mapPoint);
      if (retainAllWorkerNodes ||
          _screenContains(position, viewport, padding: 40)) {
        visible.add((node: node, position: position));
      }
    }
    if (cellSize == 0) {
      return _clusterCloseZoomNodes(visible);
    }
    final worldCellSize = cellSize / _snapshotScale;
    final buckets =
        <(int, int), List<({BdoWorkerNode node, Offset position})>>{};
    ({BdoWorkerNode node, Offset position})? selected;
    for (final entry in visible) {
      if (entry.node.id == selectedNodeId) {
        selected = entry;
        continue;
      }
      final world = entry.node.location.mapPoint;
      final key = (
        (world.x / worldCellSize).floor(),
        (world.y / worldCellSize).floor(),
      );
      buckets.putIfAbsent(key, () => []).add(entry);
    }
    final clusters = buckets.values
        .map((entries) {
          var x = 0.0;
          var y = 0.0;
          for (final entry in entries) {
            x += entry.position.dx;
            y += entry.position.dy;
          }
          return BdoNodeCluster(
            position: Offset(x / entries.length, y / entries.length),
            nodes: entries.map((entry) => entry.node).toList(growable: false),
          );
        })
        .toList(growable: true);
    if (selected case final selectedEntry?) {
      clusters.add(
        BdoNodeCluster(
          position: selectedEntry.position,
          nodes: <BdoWorkerNode>[selectedEntry.node],
        ),
      );
    }
    return clusters;
  }

  List<BdoNodeCluster> _clusterCloseZoomNodes(
    List<({BdoWorkerNode node, Offset position})> visible,
  ) {
    ({BdoWorkerNode node, Offset position})? selected;
    for (final entry in visible) {
      if (entry.node.id == selectedNodeId) {
        selected = entry;
        break;
      }
    }
    final remaining =
        visible
            .where((entry) => entry.node.id != selectedNodeId)
            .toList(growable: false)
          ..sort((left, right) => left.node.id.compareTo(right.node.id));
    final groups = <List<({BdoWorkerNode node, Offset position})>>[];
    final collisionDistanceSquared =
        _closeZoomNodeCollisionDistance * _closeZoomNodeCollisionDistance;

    for (final entry in remaining) {
      List<({BdoWorkerNode node, Offset position})>? matchingGroup;
      for (final group in groups) {
        if (group.any(
          (member) =>
              (member.position - entry.position).distanceSquared <
              collisionDistanceSquared,
        )) {
          matchingGroup = group;
          break;
        }
      }
      if (matchingGroup == null) {
        groups.add(<({BdoWorkerNode node, Offset position})>[entry]);
      } else {
        matchingGroup.add(entry);
      }
    }

    Offset groupCenter(List<({BdoWorkerNode node, Offset position})> group) {
      var x = 0.0;
      var y = 0.0;
      for (final member in group) {
        x += member.position.dx;
        y += member.position.dy;
      }
      return Offset(x / group.length, y / group.length);
    }

    var mergedOverlappingAnchors = true;
    while (mergedOverlappingAnchors) {
      mergedOverlappingAnchors = false;
      mergeSearch:
      for (var first = 0; first < groups.length; first += 1) {
        final firstCenter = groupCenter(groups[first]);
        for (var second = first + 1; second < groups.length; second += 1) {
          final secondCenter = groupCenter(groups[second]);
          if ((firstCenter - secondCenter).distanceSquared >=
              collisionDistanceSquared) {
            continue;
          }
          groups[first].addAll(groups[second]);
          groups.removeAt(second);
          mergedOverlappingAnchors = true;
          break mergeSearch;
        }
      }
    }

    final clusters = groups
        .map((group) {
          return BdoNodeCluster(
            position: groupCenter(group),
            nodes: group.map((member) => member.node).toList(growable: false),
          );
        })
        .toList(growable: true);
    if (selected != null) {
      clusters.add(
        BdoNodeCluster(
          position: selected.position,
          nodes: <BdoWorkerNode>[selected.node],
        ),
      );
    }
    return clusters;
  }
}

class BdoNodeCluster {
  BdoNodeCluster({required this.position, required this.nodes});

  final Offset position;
  final List<BdoWorkerNode> nodes;

  late final Set<BdoWorkerActivity> activities = nodes
      .where((node) => node.isResourceNode)
      .map((node) => node.activity)
      .toSet();

  late final BdoWorkerActivity? singleActivity = _singleActivity();

  BdoWorkerActivity? _singleActivity() {
    final values = activities;
    return values.length == 1 ? values.single : null;
  }
}

class BdoGatheringPointCluster {
  const BdoGatheringPointCluster({
    required this.id,
    required this.position,
    required this.points,
    required this.bounds,
  });

  final String id;
  final Offset position;
  final List<BdoGatheringPoint> points;
  final BdoMapBounds bounds;
}

class BdoMapHitTarget {
  const BdoMapHitTarget({
    required this.position,
    required this.hitRadius,
    required this.hit,
    required this.label,
    this.priority = 0,
  });

  final Offset position;
  final double hitRadius;
  final BdoMapHit hit;
  final String label;
  final int priority;
}

class BdoMapPainter extends CustomPainter {
  BdoMapPainter({
    super.repaint,
    required this.cameraController,
    required this.tileManager,
    required this.workerNodes,
    required this.workerNodesById,
    required this.gatheringSpots,
    this.gatheringPoints = const <BdoGatheringPoint>[],
    required this.gatheringRoutes,
    required this.showConnections,
    this.showAllNetworkConnections = false,
    this.nodeNetworkEdgeChanges = const <BdoNodeNetworkEdgeChange>[],
    this.nodeNetworkChangeKinds = const <String, BdoNodeNetworkChangeKind>{},
    this.activeNodeIds = const <String>{},
    this.emphasizedNodeIds = const <String>{},
    this.nodeIconImages = const <BdoNodeIconImageKey, ui.Image>{},
    this.prioritizePlannedNetwork = true,
    this.declutterWorkerLabelsForOutputArtwork = false,
    this.workerOutputArtworkMinimumZoom = double.infinity,
    this.visualStyle = BdoMapVisualStyle.standard,
    this.chromeTheme = ResourceMapChromeThemeData.sakuraCartographer,
    required this.selectedNodeId,
    required this.selectedSpotId,
    this.selectedPointId,
    required this.selectedRouteId,
    required this.colorScheme,
    this.overlayLayout,
    this.overlayLayoutProvider,
    this.tilePaintRevision = 0,
    this.tilePaintRevisionListenable,
    this.tileFadeProgress = 1,
  }) : cameraSnapshot = cameraController.camera,
       tileSourceSnapshot = cameraController.tileSource;

  final BdoMapCameraController cameraController;
  final BdoTileManager tileManager;
  final List<BdoWorkerNode> workerNodes;
  final Map<String, BdoWorkerNode> workerNodesById;
  final List<BdoGatheringSpot> gatheringSpots;
  final List<BdoGatheringPoint> gatheringPoints;
  final List<BdoGatheringRoute> gatheringRoutes;
  final bool showConnections;
  final bool showAllNetworkConnections;
  final List<BdoNodeNetworkEdgeChange> nodeNetworkEdgeChanges;
  final Map<String, BdoNodeNetworkChangeKind> nodeNetworkChangeKinds;
  final Set<String> activeNodeIds;
  final Set<String> emphasizedNodeIds;
  final Map<BdoNodeIconImageKey, ui.Image> nodeIconImages;
  final bool prioritizePlannedNetwork;
  final bool declutterWorkerLabelsForOutputArtwork;
  final double workerOutputArtworkMinimumZoom;
  final BdoMapVisualStyle visualStyle;
  final ResourceMapChromeThemeData chromeTheme;
  final String? selectedNodeId;
  final String? selectedSpotId;
  final String? selectedPointId;
  final String? selectedRouteId;
  final ColorScheme colorScheme;
  final BdoMapOverlayLayout? overlayLayout;
  final BdoMapOverlayLayout Function()? overlayLayoutProvider;
  final int tilePaintRevision;
  final ValueListenable<int>? tilePaintRevisionListenable;
  final double tileFadeProgress;
  final BdoMapCamera cameraSnapshot;
  final BdoTileSource tileSourceSnapshot;

  _BdoNodeNetworkPathGeometry? _nodeNetworkPathGeometry;
  int _nodeNetworkGeometryBuildCount = 0;
  _BdoNodeNetworkRingGeometry? _nodeNetworkRingGeometry;
  int _nodeNetworkRingGeometryBuildCount = 0;
  _BdoPlannedNodeMarkerPicture? _plannedNodeMarkerPicture;
  int _plannedNodeMarkerPictureBuildCount = 0;
  int _plannedNodeMarkerPictureReplayCount = 0;

  /// Exposes retained-path behavior to focused performance regression tests.
  @visibleForTesting
  int get debugNodeNetworkGeometryBuildCount => _nodeNetworkGeometryBuildCount;

  /// Exposes retained planned-node ring behavior to performance regressions.
  @visibleForTesting
  int get debugNodeNetworkRingGeometryBuildCount =>
      _nodeNetworkRingGeometryBuildCount;

  /// Exposes marker-picture retention to focused pan-performance tests.
  @visibleForTesting
  int get debugPlannedNodeMarkerPictureBuildCount =>
      _plannedNodeMarkerPictureBuildCount;

  /// Counts cheap picture replays separately from expensive marker recording.
  @visibleForTesting
  int get debugPlannedNodeMarkerPictureReplayCount =>
      _plannedNodeMarkerPictureReplayCount;

  bool get _plannedNetworkFocus =>
      prioritizePlannedNetwork && nodeNetworkEdgeChanges.isNotEmpty;

  late final Set<String> _plannedNetworkNodeIds = _plannedNodeIds(
    nodeNetworkEdgeChanges,
    nodeNetworkChangeKinds,
  );

  late final List<BdoWorkerNode> _paintedWorkerNodes = _plannedNetworkFocus
      ? workerNodes
            .where(
              (node) =>
                  _plannedNetworkNodeIds.contains(node.id) &&
                  _isPlannedNetworkPrimaryNode(
                    node,
                    changeKinds: nodeNetworkChangeKinds,
                    selectedNodeId: selectedNodeId,
                  ),
            )
            .toList(growable: false)
      : workerNodes;

  late final Set<String> _plannedEdgeKeys = nodeNetworkEdgeChanges.isEmpty
      ? const <String>{}
      : <String>{
          for (final edge in nodeNetworkEdgeChanges)
            _networkEdgeKey(edge.firstNodeId, edge.secondNodeId),
        };

  late final List<_BdoPaintedNetworkEdge> _cachedRelevantNetworkEdges =
      showConnections && !_plannedNetworkFocus
      ? _relevantNetworkEdges()
      : const <_BdoPaintedNetworkEdge>[];

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    try {
      final layout =
          overlayLayoutProvider?.call() ??
          overlayLayout ??
          BdoMapOverlayLayout(
            cameraController: cameraController,
            viewport: size,
            workerNodes: _paintedWorkerNodes,
            workerNodesById: workerNodesById,
            gatheringSpots: gatheringSpots,
            gatheringPoints: gatheringPoints,
            gatheringRoutes: gatheringRoutes,
            selectedNodeId: selectedNodeId,
            retainAllWorkerNodes: _plannedNetworkFocus,
          );
      canvas.drawRect(Offset.zero & size, Paint()..color = chromeTheme.canvas);
      _paintTiles(canvas, size);
      _paintMapShade(canvas, size);
      // Paint each edge only in its strongest applicable tier. This keeps
      // relevant and planned routes crisp instead of stacking translucent
      // neutral strokes beneath them.
      if (showAllNetworkConnections && !_plannedNetworkFocus) {
        final suppressedEdgeKeys = _cachedRelevantNetworkEdges.isEmpty
            ? _plannedEdgeKeys
            : <String>{
                ..._plannedEdgeKeys,
                for (final edge in _cachedRelevantNetworkEdges) edge.key,
              };
        _paintAllNetworkConnections(
          canvas,
          size,
          suppressedEdgeKeys: suppressedEdgeKeys,
        );
      }
      if (showConnections && !_plannedNetworkFocus) {
        _paintConnections(
          canvas,
          size,
          _cachedRelevantNetworkEdges,
          suppressedEdgeKeys: _plannedEdgeKeys,
        );
      }
      _paintNodeNetworkEdgeChanges(canvas, size);
      _paintRoutes(canvas, size);
      _paintNodes(
        canvas,
        size,
        layout.nodeClusters,
        positionOffset: layout.cameraTranslation,
      );
      _paintNodeNetworkChangeRings(canvas, size);
      _paintGatheringSpots(canvas, size);
      _paintGatheringPoints(canvas, size);
    } finally {
      canvas.restore();
    }
  }

  void _paintTiles(Canvas canvas, Size size) {
    final coordinates = tileManager.visibleCoordinates.toList()
      ..sort((a, b) {
        final byY = a.y.compareTo(b.y);
        return byY != 0 ? byY : a.x.compareTo(b.x);
      });
    for (final coordinate in coordinates) {
      final destination = _screenRectForTile(coordinate, size);
      final exact = tileManager.tile(coordinate);
      final ancestor = tileManager.nearestAncestor(coordinate);
      if (exact == null) {
        if (ancestor != null) {
          _drawAncestor(canvas, ancestor, coordinate, destination, 1);
        }
        continue;
      }
      final tileOpacity = _tileOpacity(exact);
      if (ancestor != null && tileOpacity < 1) {
        _drawAncestor(canvas, ancestor, coordinate, destination, 1);
      }
      canvas.drawImageRect(
        exact.image,
        Rect.fromLTWH(
          0,
          0,
          exact.image.width.toDouble(),
          exact.image.height.toDouble(),
        ),
        destination.inflate(0.35),
        Paint()
          ..filterQuality = FilterQuality.low
          ..color = Color.fromRGBO(255, 255, 255, tileOpacity)
          ..colorFilter = _basemapColorFilter,
      );
    }
  }

  double _tileOpacity(BdoDecodedTile tile) {
    const fadeDuration = Duration(milliseconds: 180);
    final elapsed = DateTime.now().difference(tile.loadedAt);
    final progress = elapsed.inMicroseconds / fadeDuration.inMicroseconds;
    return Curves.easeOut.transform(progress.clamp(0.0, 1.0));
  }

  void _drawAncestor(
    Canvas canvas,
    BdoDecodedTile ancestor,
    BdoTileCoordinate target,
    Rect destination,
    double opacity,
  ) {
    final difference = target.zoom - ancestor.coordinate.zoom;
    final factor = 1 << difference;
    final localX = target.x - ancestor.coordinate.x * factor;
    final localY = target.y - ancestor.coordinate.y * factor;
    final sourceWidth = ancestor.image.width / factor;
    final sourceHeight = ancestor.image.height / factor;
    final source = Rect.fromLTWH(
      localX * sourceWidth,
      localY * sourceHeight,
      sourceWidth,
      sourceHeight,
    );
    canvas.drawImageRect(
      ancestor.image,
      source,
      destination.inflate(0.5),
      Paint()
        ..filterQuality = FilterQuality.low
        ..color = Color.fromRGBO(255, 255, 255, opacity)
        ..colorFilter = _basemapColorFilter,
    );
  }

  Rect _screenRectForTile(BdoTileCoordinate coordinate, Size size) {
    final bounds = cameraController.tileSource.boundsFor(coordinate);
    final topLeft = cameraController.worldToScreen(
      BdoMapPoint(bounds.left, bounds.top),
      size,
    );
    final bottomRight = cameraController.worldToScreen(
      BdoMapPoint(bounds.right, bounds.bottom),
      size,
    );
    return Rect.fromPoints(topLeft, bottomRight);
  }

  void _paintMapShade(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[Color(0x0C071112), Color(0x19050C0D)],
        ).createShader(Offset.zero & size),
    );
  }

  ColorFilter? get _basemapColorFilter => visualStyle == BdoMapVisualStyle.vivid
      ? const ColorFilter.matrix(<double>[
          1.10,
          -0.08,
          -0.01,
          0,
          -4,
          -0.04,
          1.11,
          -0.03,
          0,
          -2,
          -0.03,
          -0.08,
          1.16,
          0,
          -1,
          0,
          0,
          0,
          1,
          0,
        ])
      : null;

  List<_BdoPaintedNetworkEdge> _relevantNetworkEdges() {
    final visibleIds = workerNodes.map((node) => node.id).toSet();
    final seen = <String>{};
    final edges = <_BdoPaintedNetworkEdge>[];
    for (final node in workerNodes) {
      for (final linkId in node.linkIds) {
        if (!visibleIds.contains(linkId)) {
          continue;
        }
        final link = workerNodesById[linkId];
        if (link == null) {
          continue;
        }
        final key = _networkEdgeKey(node.id, link.id);
        if (!seen.add(key)) {
          continue;
        }
        edges.add((key: key, first: node, second: link));
      }
    }
    return edges;
  }

  void _paintConnections(
    Canvas canvas,
    Size size,
    List<_BdoPaintedNetworkEdge> edges, {
    required Set<String> suppressedEdgeKeys,
  }) {
    final zoom = cameraController.camera.zoom;
    final detail = ((zoom - 1.5) / 4.5).clamp(0.0, 1.0).toDouble();
    for (final edge in edges) {
      if (suppressedEdgeKeys.contains(edge.key)) {
        continue;
      }
      final start = cameraController.worldToScreen(
        edge.first.location.mapPoint,
        size,
      );
      final end = cameraController.worldToScreen(
        edge.second.location.mapPoint,
        size,
      );
      if (!_lineNearScreen(start, end, size)) {
        continue;
      }
      _drawConnectionLine(
        canvas,
        start,
        end,
        innerColor: Color.fromRGBO(211, 226, 219, 0.82 + 0.12 * detail),
        innerWidth: 1.45 + 0.35 * detail,
        haloOpacity: 0.42 + 0.12 * detail,
        haloExpansion: 3,
      );
    }
  }

  void _paintAllNetworkConnections(
    Canvas canvas,
    Size size, {
    required Set<String> suppressedEdgeKeys,
  }) {
    final seen = <String>{};
    final zoom = cameraController.camera.zoom;
    final detail = ((zoom - 1.6) / 4.0).clamp(0.0, 1.0).toDouble();
    // Preserve every landmark edge while progressively thinning only the
    // neutral background mesh at overview zooms.
    final overviewStride = zoom < 2.45
        ? 6
        : zoom < 3.25
        ? 4
        : zoom < 4.25
        ? 2
        : 1;
    for (final node in workerNodesById.values) {
      for (final linkId in node.linkIds) {
        final link = workerNodesById[linkId];
        if (link == null) {
          continue;
        }
        final key = _networkEdgeKey(node.id, link.id);
        if (!seen.add(key)) {
          continue;
        }
        if (suppressedEdgeKeys.contains(key)) {
          continue;
        }
        if (node.isProductionNode || link.isProductionNode) {
          continue;
        }
        final landmarkEdge = _isRouteLandmark(node) || _isRouteLandmark(link);
        if (!landmarkEdge &&
            overviewStride > 1 &&
            _stableEdgeBucket(key, overviewStride) != 0) {
          continue;
        }
        final start = cameraController.worldToScreen(
          node.location.mapPoint,
          size,
        );
        final end = cameraController.worldToScreen(
          link.location.mapPoint,
          size,
        );
        if (_lineNearScreen(start, end, size)) {
          _drawConnectionLine(
            canvas,
            start,
            end,
            innerColor: Color.fromRGBO(202, 220, 213, 0.7 + 0.12 * detail),
            innerWidth: 1 + 0.25 * detail,
            haloOpacity: 0.42 + 0.1 * detail,
            haloExpansion: 3.2,
          );
        }
      }
    }
  }

  void _drawConnectionLine(
    Canvas canvas,
    Offset start,
    Offset end, {
    required Color innerColor,
    required double innerWidth,
    required double haloOpacity,
    required double haloExpansion,
  }) {
    canvas.drawLine(
      start,
      end,
      Paint()
        ..color = Color.fromRGBO(3, 9, 10, haloOpacity)
        ..strokeWidth = innerWidth + haloExpansion
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke,
    );
    canvas.drawLine(
      start,
      end,
      Paint()
        ..color = innerColor
        ..strokeWidth = innerWidth
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke,
    );
  }

  bool _isRouteLandmark(BdoWorkerNode node) => switch (node.nodeType) {
    'City' || 'Town' || 'Gateway' => true,
    _ => false,
  };

  int _stableEdgeBucket(String key, int bucketCount) {
    var hash = 0x811C9DC5;
    for (final unit in key.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0x7FFFFFFF;
    }
    return hash % bucketCount;
  }

  void _paintNodeNetworkEdgeChanges(Canvas canvas, Size size) {
    if (nodeNetworkEdgeChanges.isEmpty) {
      return;
    }
    final geometry = _nodeNetworkPathGeometryFor(size);
    final liveCamera = cameraController.camera;
    final scale = geometry.tileSource.scaleForZoom(geometry.camera.zoom);
    final translation = Offset(
      (geometry.camera.center.x - liveCamera.center.x) * scale,
      (geometry.camera.center.y - liveCamera.center.y) * scale,
    );

    canvas.save();
    canvas.translate(translation.dx, translation.dy);
    try {
      _paintNodeNetworkPathGeometry(canvas, geometry);
    } finally {
      canvas.restore();
    }
  }

  _BdoNodeNetworkPathGeometry _nodeNetworkPathGeometryFor(Size size) {
    final liveCamera = cameraController.camera;
    final liveTileSource = cameraController.tileSource;
    final cached = _nodeNetworkPathGeometry;
    if (cached != null &&
        cached.viewport == size &&
        cached.camera.zoom == liveCamera.zoom &&
        identical(cached.tileSource, liveTileSource)) {
      return cached;
    }

    // On the first paint, use the immutable construction snapshots whenever
    // their projection still matches. A center-only camera update can then
    // reuse these paths exactly, even if it happened before the first frame.
    final canUseConstructionSnapshot =
        cached == null &&
        cameraSnapshot.zoom == liveCamera.zoom &&
        identical(tileSourceSnapshot, liveTileSource);
    final basisCamera = canUseConstructionSnapshot
        ? cameraSnapshot
        : liveCamera;
    final basisTileSource = canUseConstructionSnapshot
        ? tileSourceSnapshot
        : liveTileSource;
    final geometry = _buildNodeNetworkPathGeometry(
      camera: basisCamera,
      tileSource: basisTileSource,
      viewport: size,
    );
    _nodeNetworkPathGeometry = geometry;
    _nodeNetworkGeometryBuildCount += 1;
    return geometry;
  }

  _BdoNodeNetworkPathGeometry _buildNodeNetworkPathGeometry({
    required BdoMapCamera camera,
    required BdoTileSource tileSource,
    required Size viewport,
  }) {
    final solidPaths = <BdoNodeNetworkChangeKind, Path>{};
    final disconnectSegments = <(Offset, Offset)>[];
    for (final edge in nodeNetworkEdgeChanges) {
      final first = workerNodesById[edge.firstNodeId];
      final second = workerNodesById[edge.secondNodeId];
      if (first == null || second == null) {
        continue;
      }
      final start = _worldToScreenForCamera(
        first.location.mapPoint,
        viewport: viewport,
        camera: camera,
        tileSource: tileSource,
      );
      final end = _worldToScreenForCamera(
        second.location.mapPoint,
        viewport: viewport,
        camera: camera,
        tileSource: tileSource,
      );
      if (edge.kind == BdoNodeNetworkChangeKind.disconnect) {
        disconnectSegments.add((start, end));
        continue;
      }
      (solidPaths[edge.kind] ??= Path())
        ..moveTo(start.dx, start.dy)
        ..lineTo(end.dx, end.dy);
    }

    final disconnectSolidPath = disconnectSegments.isEmpty ? null : Path();
    final disconnectDashedPath = disconnectSegments.isEmpty ? null : Path();
    for (final segment in disconnectSegments) {
      disconnectSolidPath!
        ..moveTo(segment.$1.dx, segment.$1.dy)
        ..lineTo(segment.$2.dx, segment.$2.dy);
      _appendDashedLine(disconnectDashedPath!, segment.$1, segment.$2);
    }
    return _BdoNodeNetworkPathGeometry(
      camera: camera,
      tileSource: tileSource,
      viewport: viewport,
      solidPaths: solidPaths,
      disconnectSolidPath: disconnectSolidPath,
      disconnectDashedPath: disconnectDashedPath,
    );
  }

  Offset _worldToScreenForCamera(
    BdoMapPoint point, {
    required Size viewport,
    required BdoMapCamera camera,
    required BdoTileSource tileSource,
  }) {
    final scale = tileSource.scaleForZoom(camera.zoom);
    return Offset(
      viewport.width / 2 + (point.x - camera.center.x) * scale,
      viewport.height / 2 + (point.y - camera.center.y) * scale,
    );
  }

  void _paintNodeNetworkPathGeometry(
    Canvas canvas,
    _BdoNodeNetworkPathGeometry geometry,
  ) {
    // A 500-CP recommendation can contain hundreds of edges. Drawing each
    // edge as four independent GPU operations made map panning needlessly
    // expensive. Batching equal visual tiers preserves the exact line styling
    // while reducing the dense route to a handful of draw calls per frame.
    for (final kind in const <BdoNodeNetworkChangeKind>[
      BdoNodeNetworkChangeKind.retained,
      BdoNodeNetworkChangeKind.connect,
    ]) {
      final path = geometry.solidPaths[kind];
      if (path == null) {
        continue;
      }
      final width = switch (kind) {
        BdoNodeNetworkChangeKind.retained => 2.35,
        BdoNodeNetworkChangeKind.connect => 3.1,
        BdoNodeNetworkChangeKind.disconnect => 2.9,
      };
      final edgeColor = _nodeNetworkChangeColor(kind);
      canvas.drawPath(
        path,
        Paint()
          ..color = edgeColor.withAlpha(38)
          ..strokeWidth = width + 4.6
          ..strokeCap = StrokeCap.round
          ..style = PaintingStyle.stroke,
      );
      canvas.drawPath(
        path,
        Paint()
          ..color = const Color(0xC9000000)
          ..strokeWidth = width + 2.1
          ..strokeCap = StrokeCap.round
          ..style = PaintingStyle.stroke,
      );
      canvas.drawPath(
        path,
        Paint()
          ..color = edgeColor
          ..strokeWidth = width
          ..strokeCap = StrokeCap.round
          ..style = PaintingStyle.stroke,
      );
      canvas.drawPath(
        path,
        Paint()
          ..color = Color.lerp(edgeColor, Colors.white, 0.22)!.withAlpha(220)
          ..strokeWidth = .7
          ..strokeCap = StrokeCap.round
          ..style = PaintingStyle.stroke,
      );
    }

    final disconnectSolidPath = geometry.disconnectSolidPath;
    final disconnectDashedPath = geometry.disconnectDashedPath;
    if (disconnectSolidPath != null && disconnectDashedPath != null) {
      const width = 2.9;
      final edgeColor = _nodeNetworkChangeColor(
        BdoNodeNetworkChangeKind.disconnect,
      );
      canvas.drawPath(
        disconnectSolidPath,
        Paint()
          ..color = edgeColor.withAlpha(38)
          ..strokeWidth = width + 4.6
          ..strokeCap = StrokeCap.round
          ..style = PaintingStyle.stroke,
      );
      canvas.drawPath(
        disconnectSolidPath,
        Paint()
          ..color = const Color(0xC9000000)
          ..strokeWidth = width + 2.1
          ..strokeCap = StrokeCap.round
          ..style = PaintingStyle.stroke,
      );
      canvas.drawPath(
        disconnectDashedPath,
        Paint()
          ..color = edgeColor
          ..strokeWidth = width
          ..strokeCap = StrokeCap.round
          ..style = PaintingStyle.stroke,
      );
    }
  }

  void _paintNodeNetworkChangeRings(Canvas canvas, Size size) {
    if (nodeNetworkChangeKinds.isEmpty) {
      return;
    }
    final geometry = _nodeNetworkRingGeometryFor(size);
    final liveCamera = cameraController.camera;
    final scale = geometry.tileSource.scaleForZoom(geometry.camera.zoom);
    final translation = Offset(
      (geometry.camera.center.x - liveCamera.center.x) * scale,
      (geometry.camera.center.y - liveCamera.center.y) * scale,
    );

    canvas.save();
    canvas.translate(translation.dx, translation.dy);
    try {
      for (final entry in geometry.paths.entries) {
        canvas.drawPath(
          entry.value.outline,
          Paint()
            ..color = const Color(0xC9000000)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3.4,
        );
        canvas.drawPath(
          entry.value.inner,
          Paint()
            ..color = _nodeNetworkChangeColor(entry.key.kind)
            ..style = PaintingStyle.stroke
            ..strokeWidth = entry.key.width,
        );
      }
    } finally {
      canvas.restore();
    }
  }

  _BdoNodeNetworkRingGeometry _nodeNetworkRingGeometryFor(Size size) {
    final liveCamera = cameraController.camera;
    final liveTileSource = cameraController.tileSource;
    final cached = _nodeNetworkRingGeometry;
    if (cached != null &&
        cached.viewport == size &&
        cached.camera.zoom == liveCamera.zoom &&
        identical(cached.tileSource, liveTileSource)) {
      return cached;
    }

    final canUseConstructionSnapshot =
        cached == null &&
        cameraSnapshot.zoom == liveCamera.zoom &&
        identical(tileSourceSnapshot, liveTileSource);
    final basisCamera = canUseConstructionSnapshot
        ? cameraSnapshot
        : liveCamera;
    final basisTileSource = canUseConstructionSnapshot
        ? tileSourceSnapshot
        : liveTileSource;
    final paths =
        <
          ({BdoNodeNetworkChangeKind kind, double radius, double width}),
          ({Path outline, Path inner})
        >{};
    for (final entry in nodeNetworkChangeKinds.entries) {
      final node = workerNodesById[entry.key];
      if (node == null) {
        continue;
      }
      if (_plannedNetworkFocus &&
          !_isPlannedNetworkPrimaryNode(
            node,
            changeKinds: nodeNetworkChangeKinds,
            selectedNodeId: selectedNodeId,
          )) {
        continue;
      }
      final retainedPosition = _worldToScreenForCamera(
        node.location.mapPoint,
        viewport: size,
        camera: basisCamera,
        tileSource: basisTileSource,
      );
      final selected = node.id == selectedNodeId;
      final radius = selected
          ? 13.5
          : node.isProductionNode
          ? 11.0
          : 9.5;
      final width = entry.value == BdoNodeNetworkChangeKind.connect
          ? 2.25
          : 1.9;
      final pathsForStyle = paths.putIfAbsent((
        kind: entry.value,
        radius: radius,
        width: width,
      ), () => (outline: Path(), inner: Path()));
      pathsForStyle.outline.addOval(
        Rect.fromCircle(center: retainedPosition, radius: radius + 1),
      );
      pathsForStyle.inner.addOval(
        Rect.fromCircle(center: retainedPosition, radius: radius),
      );
    }
    final geometry = _BdoNodeNetworkRingGeometry(
      camera: basisCamera,
      tileSource: basisTileSource,
      viewport: size,
      paths: paths,
    );
    _nodeNetworkRingGeometry = geometry;
    _nodeNetworkRingGeometryBuildCount += 1;
    return geometry;
  }

  void _appendDashedLine(Path path, Offset start, Offset end) {
    final delta = end - start;
    final distance = delta.distance;
    if (distance <= 0) {
      return;
    }
    const dashLength = 7.0;
    const gapLength = 4.5;
    final direction = delta / distance;
    var cursor = 0.0;
    while (cursor < distance) {
      final dashEnd = math.min(distance, cursor + dashLength);
      final dashStart = start + direction * cursor;
      final dashFinish = start + direction * dashEnd;
      path
        ..moveTo(dashStart.dx, dashStart.dy)
        ..lineTo(dashFinish.dx, dashFinish.dy);
      cursor += dashLength + gapLength;
    }
  }

  void _paintRoutes(Canvas canvas, Size size) {
    for (final route in gatheringRoutes) {
      if (route.waypoints.isEmpty) {
        continue;
      }
      final selected = route.id == selectedRouteId;
      final path = Path();
      for (var index = 0; index < route.waypoints.length; index++) {
        final point = cameraController.worldToScreen(
          route.waypoints[index].location.mapPoint,
          size,
        );
        if (index == 0) {
          path.moveTo(point.dx, point.dy);
        } else {
          path.lineTo(point.dx, point.dy);
        }
      }
      if (route.loop && route.waypoints.length > 2) {
        path.close();
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = selected ? const Color(0xFFFFC46A) : const Color(0xDDF0A451)
          ..strokeWidth = selected ? 4.5 : 3
          ..style = PaintingStyle.stroke
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round,
      );
      for (final waypoint in route.waypoints) {
        final position = cameraController.worldToScreen(
          waypoint.location.mapPoint,
          size,
        );
        if (!_screenContains(position, size, padding: 24)) {
          continue;
        }
        canvas.drawCircle(
          position,
          selected ? 10 : 8,
          Paint()..color = const Color(0xFF2B2922),
        );
        canvas.drawCircle(
          position,
          selected ? 8 : 6,
          Paint()..color = const Color(0xFFFFBF5E),
        );
        _paintCenteredText(
          canvas,
          waypoint.order.toString(),
          position,
          const TextStyle(
            color: Color(0xFF2A2215),
            fontSize: 9,
            fontWeight: FontWeight.w800,
          ),
        );
      }
    }
  }

  bool _nodeIsActive(BdoWorkerNode node) {
    final plannedKind = nodeNetworkChangeKinds[node.id];
    return node.isNaturalWorkerRoot ||
        activeNodeIds.contains(node.id) ||
        plannedKind == BdoNodeNetworkChangeKind.retained ||
        plannedKind == BdoNodeNetworkChangeKind.connect;
  }

  bool _paintSourceNodeIcon(
    Canvas canvas,
    BdoWorkerNode node,
    Offset center, {
    required bool selected,
    required bool dimmed,
    double? extent,
  }) {
    final sourceIconType = node.supportedSourceIconType;
    if (sourceIconType == null) {
      return false;
    }
    final active = _nodeIsActive(node);
    final image =
        nodeIconImages[(
          sourceIconType: sourceIconType,
          active: active,
          highlighted: selected,
        )] ??
        nodeIconImages[(
          sourceIconType: sourceIconType,
          active: active,
          highlighted: false,
        )];
    if (image == null) {
      return false;
    }
    final side = extent ?? (selected ? 47.0 : 36.0);
    final destination = Rect.fromCenter(
      center: center,
      width: side,
      height: side,
    );
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      destination,
      Paint()
        ..filterQuality = FilterQuality.medium
        ..color = Color.fromRGBO(255, 255, 255, dimmed ? 0.48 : 1),
    );
    return true;
  }

  void _paintNodeGlyph(
    Canvas canvas,
    Map<(IconData, double, Color), TextPainter> glyphPainters, {
    required IconData icon,
    required Offset center,
    required double size,
    required Color color,
  }) {
    final key = (icon, size, color);
    final painter = glyphPainters.putIfAbsent(key, () {
      return TextPainter(
        text: TextSpan(
          text: String.fromCharCode(icon.codePoint),
          style: TextStyle(
            inherit: false,
            color: color,
            fontSize: size,
            fontFamily: icon.fontFamily,
            package: icon.fontPackage,
            height: 1,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
    });
    painter.paint(
      canvas,
      center - Offset(painter.width / 2, painter.height / 2),
    );
  }

  void _paintNodeClusterMarker(
    Canvas canvas,
    BdoNodeCluster cluster,
    Offset position,
    Map<(IconData, double, Color), TextPainter> glyphPainters,
  ) {
    if (cluster.nodes.length > 1) {
      final emphasized = cluster.nodes.any(
        (node) => emphasizedNodeIds.contains(node.id),
      );
      final selected = cluster.nodes.any((node) => node.id == selectedNodeId);
      final activity = cluster.singleActivity;
      final markerColor = activity == null
          ? const Color(0xFFD8BF75)
          : bdoWorkerActivityColor(activity);
      final radius = _plannedNetworkFocus
          ? activity == null
                ? 10.5
                : 9.5
          : activity == null
          ? 15.0
          : 14.0;
      final dimmed = selectedNodeId != null && !selected && !emphasized;
      final representative = cluster.nodes.first;
      final paintedSourceIcon = _paintSourceNodeIcon(
        canvas,
        representative,
        position,
        selected: false,
        dimmed: dimmed,
        extent: _plannedNetworkFocus
            ? _plannedNodeMarkerExtent(clustered: true)
            : 38,
      );
      if (!paintedSourceIcon) {
        canvas.drawCircle(
          position,
          radius + 3,
          Paint()..color = chromeTheme.chromeBase.withAlpha(dimmed ? 125 : 210),
        );
        canvas.drawCircle(
          position,
          radius,
          Paint()
            ..color = chromeTheme.chromeRaised.withAlpha(dimmed ? 170 : 245),
        );
        canvas.drawCircle(
          position,
          radius,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.6
            ..color = markerColor.withAlpha(dimmed ? 115 : 225),
        );
        _paintNodeGlyph(
          canvas,
          glyphPainters,
          icon: activity == null
              ? Icons.category_outlined
              : bdoWorkerActivityIcon(activity),
          center: position,
          size: activity == null ? 16 : 15,
          color: markerColor.withAlpha(dimmed ? 130 : 255),
        );
      }
      return;
    }

    final node = cluster.nodes.single;
    final selected = node.id == selectedNodeId;
    final emphasized = emphasizedNodeIds.contains(node.id);
    final dimmed = selectedNodeId != null && !selected && !emphasized;
    final markerColor = _workerNodeColor(node);
    final radius = selected
        ? 13.0
        : _plannedNetworkFocus
        ? 8.5
        : 10.5;
    if (selected) {
      canvas.drawCircle(
        position,
        radius + 8,
        Paint()..color = chromeTheme.accent.withAlpha(55),
      );
      canvas.drawCircle(
        position,
        radius + 3.5,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = chromeTheme.accent,
      );
    }
    final paintedSourceIcon = _paintSourceNodeIcon(
      canvas,
      node,
      position,
      selected: selected,
      dimmed: dimmed,
      extent: _plannedNetworkFocus
          ? _plannedNodeMarkerExtent(selected: selected, clustered: false)
          : null,
    );
    if (!paintedSourceIcon) {
      canvas.drawCircle(
        position,
        radius + 2,
        Paint()..color = chromeTheme.chromeBase.withAlpha(dimmed ? 105 : 220),
      );
      canvas.drawCircle(
        position,
        radius,
        Paint()..color = chromeTheme.chromeRaised.withAlpha(dimmed ? 135 : 248),
      );
      canvas.drawCircle(
        position,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = selected ? 1.8 : 1.4
          ..color = markerColor.withAlpha(dimmed ? 100 : 240),
      );
      _paintNodeGlyph(
        canvas,
        glyphPainters,
        icon: _workerNodeIcon(node),
        center: position,
        size: selected ? 15.5 : 13,
        color: markerColor.withAlpha(dimmed ? 115 : 255),
      );
    }
  }

  void _paintRetainedPlannedNodeMarkers(
    Canvas canvas,
    Size size,
    List<BdoNodeCluster> nodeClusters,
    Offset positionOffset,
  ) {
    final visibleBasisBounds = Rect.fromLTWH(
      -positionOffset.dx,
      -positionOffset.dy,
      size.width,
      size.height,
    ).inflate(64);
    var markerPicture = _plannedNodeMarkerPicture;
    final canReplay =
        markerPicture != null &&
        identical(markerPicture.nodeClusters, nodeClusters) &&
        markerPicture.zoom == cameraController.camera.zoom &&
        _rectContainsRect(markerPicture.coverageBounds, visibleBasisBounds);
    if (!canReplay) {
      final overscan = math.max(
        _plannedMarkerPictureMinimumOverscan,
        size.longestSide * .8,
      );
      final coverageBounds = visibleBasisBounds.inflate(overscan);
      final recorder = ui.PictureRecorder();
      final pictureCanvas = Canvas(recorder, coverageBounds.inflate(64));
      final glyphPainters = <(IconData, double, Color), TextPainter>{};
      for (final cluster in nodeClusters) {
        if (!coverageBounds.inflate(64).contains(cluster.position)) {
          continue;
        }
        _paintNodeClusterMarker(
          pictureCanvas,
          cluster,
          cluster.position,
          glyphPainters,
        );
      }
      for (final painter in glyphPainters.values) {
        painter.dispose();
      }
      final picture = recorder.endRecording();
      markerPicture?.picture.dispose();
      markerPicture = _BdoPlannedNodeMarkerPicture(
        nodeClusters: nodeClusters,
        zoom: cameraController.camera.zoom,
        coverageBounds: coverageBounds,
        picture: picture,
      );
      _plannedNodeMarkerPicture = markerPicture;
      _plannedNodeMarkerPictureBuildCount += 1;
    }

    canvas.save();
    canvas.translate(positionOffset.dx, positionOffset.dy);
    canvas.drawPicture(markerPicture.picture);
    canvas.restore();
    _plannedNodeMarkerPictureReplayCount += 1;
  }

  void _paintNodes(
    Canvas canvas,
    Size size,
    List<BdoNodeCluster> nodeClusters, {
    Offset positionOffset = Offset.zero,
  }) {
    final outputArtworkOwnsUnselectedLabels =
        declutterWorkerLabelsForOutputArtwork &&
        cameraController.camera.zoom >= workerOutputArtworkMinimumZoom;
    final labelCandidates = <({BdoWorkerNode node, Offset labelPosition})>[];
    ({BdoWorkerNode node, Offset labelPosition})? selectedLabel;
    final glyphPainters = <(IconData, double, Color), TextPainter>{};
    final retainPlannedMarkers =
        _plannedNetworkFocus &&
        nodeClusters.length >= _plannedMarkerPictureMinimumClusterCount;
    if (retainPlannedMarkers) {
      _paintRetainedPlannedNodeMarkers(
        canvas,
        size,
        nodeClusters,
        positionOffset,
      );
    }

    for (final cluster in nodeClusters) {
      final position = cluster.position + positionOffset;
      if (!_screenContains(position, size, padding: 64)) {
        continue;
      }
      if (!retainPlannedMarkers) {
        _paintNodeClusterMarker(canvas, cluster, position, glyphPainters);
      }
      if (cluster.nodes.length > 1) {
        continue;
      }
      final node = cluster.nodes.single;
      final selected = node.id == selectedNodeId;
      final candidate = (
        node: node,
        labelPosition:
            position +
            Offset(
              0,
              selected && outputArtworkOwnsUnselectedLabels ? 31.0 : -23.0,
            ),
      );
      if (selected) {
        selectedLabel = candidate;
      } else if (!outputArtworkOwnsUnselectedLabels &&
          (!_plannedNetworkFocus ||
              _isWorkerNetworkLandmark(node) ||
              (node.isProductionNode &&
                  cameraController.camera.zoom >= 5.15))) {
        labelCandidates.add(candidate);
      }
    }

    final occupiedLabelBounds = <Rect>[];
    if (selectedLabel case final selected?) {
      final layout = _layoutLabel(
        _workerNodeLabel(selected.node, workerNodesById),
        selected.labelPosition,
        selected: true,
      );
      _paintLabelLayout(canvas, layout);
      occupiedLabelBounds.add(layout.rect);
    }

    final labelBudget = outputArtworkOwnsUnselectedLabels
        ? 0
        : _plannedNetworkFocus
        ? _plannedNetworkLabelBudget(
            labelCandidates.length,
            cameraController.camera.zoom,
          )
        : _workerNodeLabelBudget(
            workerNodes.length,
            cameraController.camera.zoom,
          );
    if (labelBudget == 0) {
      for (final painter in glyphPainters.values) {
        painter.dispose();
      }
      return;
    }
    final viewportCenter = size.center(Offset.zero);
    labelCandidates.sort((a, b) {
      final resourceOrder =
          (b.node.isResourceNode ? 1 : 0) - (a.node.isResourceNode ? 1 : 0);
      if (resourceOrder != 0) {
        return resourceOrder;
      }
      final distanceOrder = (a.labelPosition - viewportCenter).distance
          .compareTo((b.labelPosition - viewportCenter).distance);
      return distanceOrder != 0
          ? distanceOrder
          : a.node.id.compareTo(b.node.id);
    });

    var paintedLabels = 0;
    final viewportBounds = Offset.zero & size;
    final controlsBounds = size.width >= 700 && size.height >= 400
        ? Rect.fromLTWH(size.width - 220, 0, 220, 278)
        : Rect.zero;
    for (final candidate in labelCandidates) {
      if (paintedLabels >= labelBudget) {
        break;
      }
      final layout = _layoutLabel(
        _workerNodeLabel(candidate.node, workerNodesById),
        candidate.labelPosition,
        selected: false,
      );
      final collides = occupiedLabelBounds.any(
        (bounds) => bounds.inflate(5).overlaps(layout.rect),
      );
      if (collides ||
          !layout.rect.overlaps(viewportBounds) ||
          layout.rect.overlaps(controlsBounds)) {
        layout.painter.dispose();
        continue;
      }
      _paintLabelLayout(canvas, layout);
      occupiedLabelBounds.add(layout.rect);
      paintedLabels += 1;
    }
    for (final painter in glyphPainters.values) {
      painter.dispose();
    }
  }

  double _plannedNodeMarkerExtent({
    bool selected = false,
    required bool clustered,
  }) {
    if (selected) {
      return 42;
    }
    final zoom = cameraController.camera.zoom;
    if (zoom < 2.75) {
      return clustered ? 27 : 23;
    }
    if (zoom < 4.25) {
      return clustered ? 31 : 27;
    }
    return clustered ? 35 : 32;
  }

  void _paintGatheringSpots(Canvas canvas, Size size) {
    final labelCandidates = <({BdoGatheringSpot spot, Offset position})>[];
    ({BdoGatheringSpot spot, Offset position})? selectedLabel;
    for (final spot in gatheringSpots) {
      final position = cameraController.worldToScreen(
        spot.location.mapPoint,
        size,
      );
      if (!_screenContains(position, size, padding: 32)) {
        continue;
      }
      final selected = spot.id == selectedSpotId;
      final radius = selected ? 10.0 : 7.5;
      canvas.drawCircle(
        position,
        radius + 3,
        Paint()..color = chromeTheme.chromeBase.withAlpha(216),
      );
      canvas.drawCircle(
        position,
        radius,
        Paint()
          ..shader = const RadialGradient(
            colors: <Color>[Color(0xFFB7E4CB), Color(0xFF4FA57D)],
          ).createShader(Rect.fromCircle(center: position, radius: radius)),
      );
      final leaf = Path()
        ..moveTo(position.dx - 4, position.dy + 4)
        ..quadraticBezierTo(
          position.dx - 6,
          position.dy - 5,
          position.dx + 4,
          position.dy - 6,
        )
        ..quadraticBezierTo(
          position.dx + 6,
          position.dy + 3,
          position.dx - 4,
          position.dy + 4,
        );
      canvas.drawPath(leaf, Paint()..color = const Color(0xFF17352B));
      final candidate = (spot: spot, position: position);
      if (selected) {
        selectedLabel = candidate;
      } else {
        labelCandidates.add(candidate);
      }
    }

    final occupiedLabelBounds = <Rect>[];
    if (selectedLabel case final selected?) {
      final layout = _layoutLabel(
        selected.spot.name,
        selected.position + const Offset(0, -21),
        selected: true,
      );
      _paintLabelLayout(canvas, layout);
      occupiedLabelBounds.add(layout.rect);
    }

    final overview = _showGatheringOverviewLabels;
    if (!overview && cameraController.camera.zoom < 5.1) {
      return;
    }

    final candidatesToLayout = labelCandidates.toList(growable: true);
    if (!overview && candidatesToLayout.length > 3) {
      final viewportCenter = size.center(Offset.zero);
      candidatesToLayout.sort((a, b) {
        final distanceOrder = (a.position - viewportCenter).distance.compareTo(
          (b.position - viewportCenter).distance,
        );
        return distanceOrder != 0
            ? distanceOrder
            : a.spot.id.compareTo(b.spot.id);
      });
      candidatesToLayout.removeRange(3, candidatesToLayout.length);
    }

    final layouts = _layoutGatheringZoneLabels(
      candidates: candidatesToLayout
          .map(
            (candidate) => (
              id: candidate.spot.id,
              text: overview
                  ? _overviewGatheringLabel(candidate.spot.name)
                  : candidate.spot.name,
              position: candidate.position,
            ),
          )
          .toList(growable: false),
      size: size,
      occupiedLabelBounds: occupiedLabelBounds,
    );
    for (final layout in layouts) {
      _paintLabelLayout(canvas, layout);
    }
  }

  bool get _showGatheringOverviewLabels {
    return gatheringSpots.length == 5 &&
        gatheringSpots.every((spot) => spot.radiusWorld != null) &&
        workerNodes.isEmpty &&
        gatheringPoints.isEmpty &&
        gatheringRoutes.isEmpty &&
        selectedNodeId == null &&
        selectedSpotId == null &&
        selectedPointId == null &&
        selectedRouteId == null;
  }

  List<_MapLabelLayout> _layoutGatheringZoneLabels({
    required List<({String id, String text, Offset position})> candidates,
    required Size size,
    required List<Rect> occupiedLabelBounds,
  }) {
    final pending = <_GatheringZoneLabelCandidate>[];
    for (final candidate in candidates) {
      final painter = _createLabelPainter(
        candidate.text,
        selected: false,
        maxLines: 2,
        maxWidth: 184,
        textAlign: TextAlign.center,
      );
      final rects = _gatheringZoneLabelRects(
        marker: candidate.position,
        labelSize: Size(painter.width + 12, painter.height + 6),
        viewportSize: size,
      );
      if (rects.isEmpty) {
        painter.dispose();
        continue;
      }
      pending.add(
        _GatheringZoneLabelCandidate(
          id: candidate.id,
          painter: painter,
          rects: rects,
        ),
      );
    }

    final layouts = <_MapLabelLayout>[];
    while (pending.isNotEmpty) {
      final availableByCandidate = pending.map((candidate) {
        final available = candidate.rects
            .where(
              (rect) => !occupiedLabelBounds.any(
                (occupied) => occupied.inflate(5).overlaps(rect),
              ),
            )
            .toList(growable: false);
        return (candidate: candidate, available: available);
      }).toList();
      availableByCandidate.sort((a, b) {
        final optionOrder = a.available.length.compareTo(b.available.length);
        return optionOrder != 0
            ? optionOrder
            : a.candidate.id.compareTo(b.candidate.id);
      });

      final next = availableByCandidate.first;
      pending.remove(next.candidate);
      if (next.available.isEmpty) {
        next.candidate.painter.dispose();
        continue;
      }

      Rect? bestRect;
      var bestConflictScore = 1 << 30;
      var bestPreference = 1 << 30;
      for (final rect in next.available) {
        var conflictScore = 0;
        for (final other in pending) {
          for (final option in other.rects) {
            if (rect.inflate(5).overlaps(option)) {
              conflictScore += 1;
            }
          }
        }
        final preference = next.candidate.rects.indexOf(rect);
        if (conflictScore < bestConflictScore ||
            (conflictScore == bestConflictScore &&
                preference < bestPreference)) {
          bestRect = rect;
          bestConflictScore = conflictScore;
          bestPreference = preference;
        }
      }

      final rect = bestRect!;
      occupiedLabelBounds.add(rect);
      layouts.add(
        _MapLabelLayout(
          painter: next.candidate.painter,
          rect: rect,
          textOffset: rect.topLeft + const Offset(6, 3),
        ),
      );
    }
    return layouts;
  }

  List<Rect> _gatheringZoneLabelRects({
    required Offset marker,
    required Size labelSize,
    required Size viewportSize,
  }) {
    const gap = 15.0;
    const margin = 5.0;
    final viewportBounds = Rect.fromLTWH(
      margin,
      margin,
      math.max(0, viewportSize.width - margin * 2),
      math.max(0, viewportSize.height - margin * 2),
    );
    if (labelSize.width > viewportBounds.width ||
        labelSize.height > viewportBounds.height) {
      return const <Rect>[];
    }

    Rect above({required bool alignLeft}) {
      return Rect.fromLTWH(
        alignLeft ? marker.dx - labelSize.width : marker.dx,
        marker.dy - gap - labelSize.height,
        labelSize.width,
        labelSize.height,
      );
    }

    Rect below({required bool alignLeft}) {
      return Rect.fromLTWH(
        alignLeft ? marker.dx - labelSize.width : marker.dx,
        marker.dy + gap,
        labelSize.width,
        labelSize.height,
      );
    }

    final centeredAbove = Rect.fromLTWH(
      marker.dx - labelSize.width / 2,
      marker.dy - gap - labelSize.height,
      labelSize.width,
      labelSize.height,
    );
    final centeredBelow = Rect.fromLTWH(
      marker.dx - labelSize.width / 2,
      marker.dy + gap,
      labelSize.width,
      labelSize.height,
    );
    final centeredLeft = Rect.fromLTWH(
      marker.dx - gap - labelSize.width,
      marker.dy - labelSize.height / 2,
      labelSize.width,
      labelSize.height,
    );
    final centeredRight = Rect.fromLTWH(
      marker.dx + gap,
      marker.dy - labelSize.height / 2,
      labelSize.width,
      labelSize.height,
    );

    final inwardIsLeft = marker.dx >= viewportSize.width / 2;
    final inwardIsAbove = marker.dy >= viewportSize.height / 2;
    final verticalInward = inwardIsAbove ? centeredAbove : centeredBelow;
    final verticalOutward = inwardIsAbove ? centeredBelow : centeredAbove;
    final horizontalInward = inwardIsLeft ? centeredLeft : centeredRight;
    final horizontalOutward = inwardIsLeft ? centeredRight : centeredLeft;
    final diagonalInward = inwardIsAbove
        ? above(alignLeft: inwardIsLeft)
        : below(alignLeft: inwardIsLeft);
    final verticalOutwardHorizontalInward = inwardIsAbove
        ? below(alignLeft: inwardIsLeft)
        : above(alignLeft: inwardIsLeft);
    final verticalInwardHorizontalOutward = inwardIsAbove
        ? above(alignLeft: !inwardIsLeft)
        : below(alignLeft: !inwardIsLeft);
    final diagonalOutward = inwardIsAbove
        ? below(alignLeft: !inwardIsLeft)
        : above(alignLeft: !inwardIsLeft);

    final rects = <Rect>[];
    for (final raw in <Rect>[
      verticalInward,
      horizontalInward,
      diagonalInward,
      verticalOutward,
      verticalOutwardHorizontalInward,
      horizontalOutward,
      verticalInwardHorizontalOutward,
      diagonalOutward,
    ]) {
      final dx = raw.left < viewportBounds.left
          ? viewportBounds.left - raw.left
          : raw.right > viewportBounds.right
          ? viewportBounds.right - raw.right
          : 0.0;
      final dy = raw.top < viewportBounds.top
          ? viewportBounds.top - raw.top
          : raw.bottom > viewportBounds.bottom
          ? viewportBounds.bottom - raw.bottom
          : 0.0;
      final fitted = raw.shift(Offset(dx, dy));
      if (fitted.inflate(7).contains(marker) ||
          rects.any(
            (existing) =>
                (existing.topLeft - fitted.topLeft).distanceSquared < 0.01,
          )) {
        continue;
      }
      rects.add(fitted);
    }
    return rects;
  }

  void _paintGatheringPoints(Canvas canvas, Size size) {
    final zoom = cameraController.camera.zoom;
    for (final point in gatheringPoints) {
      final selected = point.id == selectedPointId;
      final position = cameraController.worldToScreen(
        point.location.mapPoint,
        size,
      );
      if (!_screenContains(position, size, padding: 16)) {
        continue;
      }
      final radius = selected
          ? 6.5
          : zoom < 3
          ? 1.7
          : zoom < _gatheringPointMinimumZoom
          ? 2.1
          : zoom >= 5.5
          ? 3.8
          : 3.1;
      canvas.drawCircle(
        position,
        radius + (selected ? 3.5 : 1.25),
        Paint()
          ..color = selected
              ? chromeTheme.accent.withAlpha(213)
              : chromeTheme.chromeBase.withAlpha(213),
      );
      canvas.drawCircle(
        position,
        radius,
        Paint()
          ..color = switch (point.verification) {
            BdoGatheringVerification.independentSurvey => const Color(
              0xFFA8E4C2,
            ),
            BdoGatheringVerification.crossChecked => const Color(0xFF79CBA2),
            BdoGatheringVerification.communityReported => const Color(
              0xFF83B99E,
            ),
            BdoGatheringVerification.stale => const Color(0xFFD0A36F),
          },
      );
      if (selected) {
        _paintLabel(
          canvas,
          point.label,
          position + const Offset(0, -16),
          selected: selected,
        );
      }
    }
  }

  void _paintLabel(
    Canvas canvas,
    String text,
    Offset position, {
    required bool selected,
  }) {
    _paintLabelLayout(canvas, _layoutLabel(text, position, selected: selected));
  }

  _MapLabelLayout _layoutLabel(
    String text,
    Offset position, {
    required bool selected,
  }) {
    final painter = _createLabelPainter(text, selected: selected);
    final rect = Rect.fromLTWH(
      position.dx - painter.width / 2 - 6,
      position.dy - painter.height / 2 - 3,
      painter.width + 12,
      painter.height + 6,
    );
    return _MapLabelLayout(
      painter: painter,
      rect: rect,
      textOffset: Offset(
        position.dx - painter.width / 2,
        position.dy - painter.height / 2,
      ),
    );
  }

  TextPainter _createLabelPainter(
    String text, {
    required bool selected,
    int maxLines = 1,
    double maxWidth = 220,
    TextAlign textAlign = TextAlign.start,
  }) {
    return TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: chromeTheme.ink,
          fontSize: selected ? 12 : 10.5,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
          shadows: <Shadow>[
            Shadow(color: chromeTheme.idleShadow.color, blurRadius: 4),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: textAlign,
      textWidthBasis: TextWidthBasis.longestLine,
      maxLines: maxLines,
      ellipsis: '…',
    )..layout(maxWidth: maxWidth);
  }

  void _paintLabelLayout(Canvas canvas, _MapLabelLayout layout) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(layout.rect, const Radius.circular(6)),
      Paint()..color = chromeTheme.chromeBase.withAlpha(180),
    );
    layout.painter.paint(canvas, layout.textOffset);
    layout.painter.dispose();
  }

  void _paintCenteredText(
    Canvas canvas,
    String text,
    Offset center,
    TextStyle style,
  ) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    );
    try {
      painter.layout();
      painter.paint(
        canvas,
        center - Offset(painter.width / 2, painter.height / 2),
      );
    } finally {
      painter.dispose();
    }
  }

  @override
  bool shouldRepaint(covariant BdoMapPainter oldDelegate) {
    return oldDelegate.cameraController != cameraController ||
        oldDelegate.cameraSnapshot.center != cameraSnapshot.center ||
        oldDelegate.cameraSnapshot.zoom != cameraSnapshot.zoom ||
        oldDelegate.tileSourceSnapshot != tileSourceSnapshot ||
        oldDelegate.tileManager != tileManager ||
        oldDelegate.tilePaintRevision != tilePaintRevision ||
        oldDelegate.tileFadeProgress != tileFadeProgress ||
        !identical(oldDelegate.overlayLayout, overlayLayout) ||
        oldDelegate.overlayLayoutProvider != overlayLayoutProvider ||
        !identical(oldDelegate.workerNodes, workerNodes) ||
        !identical(oldDelegate.workerNodesById, workerNodesById) ||
        !identical(oldDelegate.gatheringSpots, gatheringSpots) ||
        !identical(oldDelegate.gatheringPoints, gatheringPoints) ||
        !identical(oldDelegate.gatheringRoutes, gatheringRoutes) ||
        oldDelegate.showConnections != showConnections ||
        oldDelegate.showAllNetworkConnections != showAllNetworkConnections ||
        !identical(
          oldDelegate.nodeNetworkEdgeChanges,
          nodeNetworkEdgeChanges,
        ) ||
        !identical(
          oldDelegate.nodeNetworkChangeKinds,
          nodeNetworkChangeKinds,
        ) ||
        !identical(oldDelegate.activeNodeIds, activeNodeIds) ||
        !setEquals(oldDelegate.emphasizedNodeIds, emphasizedNodeIds) ||
        !identical(oldDelegate.nodeIconImages, nodeIconImages) ||
        oldDelegate.prioritizePlannedNetwork != prioritizePlannedNetwork ||
        oldDelegate.declutterWorkerLabelsForOutputArtwork !=
            declutterWorkerLabelsForOutputArtwork ||
        oldDelegate.workerOutputArtworkMinimumZoom !=
            workerOutputArtworkMinimumZoom ||
        oldDelegate.visualStyle != visualStyle ||
        oldDelegate.selectedNodeId != selectedNodeId ||
        oldDelegate.selectedSpotId != selectedSpotId ||
        oldDelegate.selectedPointId != selectedPointId ||
        oldDelegate.selectedRouteId != selectedRouteId ||
        oldDelegate.colorScheme != colorScheme ||
        oldDelegate.chromeTheme != chromeTheme;
  }
}

class _BdoNodeNetworkPathGeometry {
  const _BdoNodeNetworkPathGeometry({
    required this.camera,
    required this.tileSource,
    required this.viewport,
    required this.solidPaths,
    required this.disconnectSolidPath,
    required this.disconnectDashedPath,
  });

  final BdoMapCamera camera;
  final BdoTileSource tileSource;
  final Size viewport;
  final Map<BdoNodeNetworkChangeKind, Path> solidPaths;
  final Path? disconnectSolidPath;
  final Path? disconnectDashedPath;
}

class _BdoNodeNetworkRingGeometry {
  const _BdoNodeNetworkRingGeometry({
    required this.camera,
    required this.tileSource,
    required this.viewport,
    required this.paths,
  });

  final BdoMapCamera camera;
  final BdoTileSource tileSource;
  final Size viewport;
  final Map<
    ({BdoNodeNetworkChangeKind kind, double radius, double width}),
    ({Path outline, Path inner})
  >
  paths;
}

class _BdoPlannedNodeMarkerPicture {
  const _BdoPlannedNodeMarkerPicture({
    required this.nodeClusters,
    required this.zoom,
    required this.coverageBounds,
    required this.picture,
  });

  final List<BdoNodeCluster> nodeClusters;
  final double zoom;
  final Rect coverageBounds;
  final ui.Picture picture;
}

class _MapLabelLayout {
  const _MapLabelLayout({
    required this.painter,
    required this.rect,
    required this.textOffset,
  });

  final TextPainter painter;
  final Rect rect;
  final Offset textOffset;
}

class _GatheringZoneLabelCandidate {
  const _GatheringZoneLabelCandidate({
    required this.id,
    required this.painter,
    required this.rects,
  });

  final String id;
  final TextPainter painter;
  final List<Rect> rects;
}

String _networkEdgeKey(String firstNodeId, String secondNodeId) =>
    firstNodeId.compareTo(secondNodeId) < 0
    ? '$firstNodeId\u0000$secondNodeId'
    : '$secondNodeId\u0000$firstNodeId';

Set<String> _plannedNodeIds(
  Iterable<BdoNodeNetworkEdgeChange> edges,
  Map<String, BdoNodeNetworkChangeKind> changeKinds,
) {
  return <String>{
    ...changeKinds.keys,
    for (final edge in edges) edge.firstNodeId,
    for (final edge in edges) edge.secondNodeId,
  };
}

bool _isWorkerNetworkLandmark(BdoWorkerNode node) => switch (node.nodeType) {
  'City' || 'Town' || 'Gateway' => true,
  _ => false,
};

bool _isPlannedNetworkPrimaryNode(
  BdoWorkerNode node, {
  required Map<String, BdoNodeNetworkChangeKind> changeKinds,
  required String? selectedNodeId,
}) {
  return node.id == selectedNodeId ||
      node.isProductionNode ||
      _isWorkerNetworkLandmark(node) ||
      changeKinds[node.id] == BdoNodeNetworkChangeKind.disconnect;
}

bool _screenContains(Offset point, Size size, {required double padding}) {
  return point.dx >= -padding &&
      point.dy >= -padding &&
      point.dx <= size.width + padding &&
      point.dy <= size.height + padding;
}

bool _rectContainsRect(Rect outer, Rect inner) {
  return outer.left <= inner.left &&
      outer.top <= inner.top &&
      outer.right >= inner.right &&
      outer.bottom >= inner.bottom;
}

Color _nodeNetworkChangeColor(BdoNodeNetworkChangeKind kind) => switch (kind) {
  BdoNodeNetworkChangeKind.retained => const Color(0xFFE1C66F),
  BdoNodeNetworkChangeKind.connect => const Color(0xFF55D69A),
  BdoNodeNetworkChangeKind.disconnect => const Color(0xFFFF766A),
};

int _workerNodeLabelBudget(int nodeCount, double zoom) {
  if (nodeCount > 40 || zoom < 5.25) {
    return 0;
  }
  if (nodeCount <= 8) {
    return math.min(nodeCount, 6);
  }
  return zoom >= 6.25 ? 6 : 3;
}

int _plannedNetworkLabelBudget(int candidateCount, double zoom) {
  if (candidateCount == 0 || zoom < 2.2) {
    return 0;
  }
  if (zoom < 4.6) {
    return math.min(candidateCount, 4);
  }
  return math.min(candidateCount, 6);
}

bool _lineNearScreen(Offset start, Offset end, Size size) {
  final bounds = Rect.fromPoints(start, end).inflate(20);
  return bounds.overlaps(Offset.zero & size);
}
