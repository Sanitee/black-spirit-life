import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

// Diagnostic-only read of live canvas counters; not a new package API.
// ignore: implementation_imports
import 'package:bdo_map_core/src/widgets/map_canvas.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Temporary, opt-in diagnostic. Never persisted or enabled in ordinary builds.
const resourceFrameCaptureEnabled = bool.fromEnvironment(
  'BSL_DIAGNOSTIC_RESOURCE_FRAME_CAPTURE',
);

typedef ResourceFrameReadback =
    Future<ResourceFramePixels> Function(RenderRepaintBoundary, double);
typedef ResourceFrameWriter = Future<void> Function(ResourceFrameRecord);

class ResourceFramePixels {
  const ResourceFramePixels({
    required this.png,
    required this.width,
    required this.height,
  });

  final Uint8List png;
  final int width;
  final int height;
}

class ResourceFrameRecord {
  const ResourceFrameRecord({required this.metadata, this.pixels});

  final Map<String, Object?> metadata;
  final ResourceFramePixels? pixels;
}

/// Local app-view images only: no desktop APIs, uploads or profile access.
/// A unique directory per instance prevents replacing earlier recordings.
class ResourceFrameFileStore {
  ResourceFrameFileStore({required this.parent});

  final Directory parent;
  Future<Directory>? _directory;

  Future<Directory> _createDirectory() async {
    await parent.create(recursive: true);
    final stamp = DateTime.now().toUtc().toIso8601String().replaceAll(':', '-');
    return parent.createTemp('capture-$stamp-$pid-');
  }

  Future<void> write(ResourceFrameRecord record) async {
    final directory = await (_directory ??= _createDirectory());
    final index = record.metadata['requestIndex'];
    if (index != 1 && index != 2) {
      throw ArgumentError('Only two diagnostic captures are supported.');
    }
    final stem = '${directory.path}${Platform.pathSeparator}0$index';
    final metadata = Map<String, Object?>.of(record.metadata);
    final pixels = record.pixels;
    if (pixels != null) {
      try {
        await File('$stem.png').writeAsBytes(pixels.png, flush: true);
      } catch (_) {
        metadata['status'] = 'storage-failed';
      }
    }
    await File('$stem.json').writeAsString(
      const JsonEncoder.withIndent('  ').convert(metadata),
      flush: true,
    );
  }
}

/// F8 snapshots the existing Resource layer; it never requests a new frame.
/// Layer replay is not a readback of the Windows compositor or physical screen.
/// The extra boundary/readback can itself perturb the graphics path, so this
/// wrapper is absent entirely unless the diagnostic build flag is set.
class ResourceMapFrameCapture extends StatefulWidget {
  const ResourceMapFrameCapture({
    required this.active,
    required this.child,
    this.readback,
    this.writer,
    super.key,
  });

  final bool active;
  final Widget child;
  final ResourceFrameReadback? readback;
  final ResourceFrameWriter? writer;

  @override
  State<ResourceMapFrameCapture> createState() =>
      _ResourceMapFrameCaptureState();
}

class _ResourceMapFrameCaptureState extends State<ResourceMapFrameCapture>
    with WidgetsBindingObserver {
  final GlobalKey _boundaryKey = GlobalKey();
  late final ResourceFrameFileStore _store = ResourceFrameFileStore(
    parent: Directory(
      '${Directory.systemTemp.path}${Platform.pathSeparator}BSLife-Resource-Frames',
    ),
  );
  bool _tickerEnabled = true;
  bool _routeCurrent = true;
  double? _devicePixelRatio;
  AppLifecycleState? _lifecycle;
  bool _busy = false;
  int _requests = 0;
  int _generation = 0;

  bool get _eligible =>
      mounted &&
      widget.active &&
      _tickerEnabled &&
      _routeCurrent &&
      (_lifecycle == null || _lifecycle == AppLifecycleState.resumed);

  @override
  void initState() {
    super.initState();
    _lifecycle = WidgetsBinding.instance.lifecycleState;
    WidgetsBinding.instance.addObserver(this);
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final tickerEnabled = TickerMode.valuesOf(context).enabled;
    final pixelRatio = View.of(context).devicePixelRatio;
    final routeCurrent = ModalRoute.of(context)?.isCurrent ?? true;
    if (_tickerEnabled != tickerEnabled ||
        _devicePixelRatio != pixelRatio ||
        _routeCurrent != routeCurrent) {
      _generation++;
    }
    _tickerEnabled = tickerEnabled;
    _routeCurrent = routeCurrent;
    _devicePixelRatio = pixelRatio;
  }

  @override
  void didUpdateWidget(ResourceMapFrameCapture oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active) _generation++;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_lifecycle != state) _generation++;
    _lifecycle = state;
  }

  @override
  void didChangeMetrics() {
    _generation++;
  }

  @override
  void dispose() {
    _generation++;
    WidgetsBinding.instance.removeObserver(this);
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    super.dispose();
  }

  bool _handleKeyEvent(KeyEvent event) {
    // App-local dispatch, not an OS/global keyboard hook. Nothing is recorded.
    // Chrome may hold focus on first entry: do not require a map click, which
    // could itself clear the symptom before the requested capture.
    if (!_eligible ||
        !const SingleActivator(
          LogicalKeyboardKey.f8,
          includeRepeats: false,
        ).accepts(event, HardwareKeyboard.instance)) {
      return false;
    }
    _requestCapture();
    return true;
  }

  static Future<ResourceFramePixels> _readPixels(
    RenderRepaintBoundary boundary,
    double pixelRatio,
  ) async {
    // toImage constructs its Scene synchronously before its first await.
    final image = await boundary.toImage(pixelRatio: pixelRatio);
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) throw StateError('PNG encoding failed.');
      return ResourceFramePixels(
        png: bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
        width: image.width,
        height: image.height,
      );
    } finally {
      image.dispose();
    }
  }

  void _requestCapture() {
    if (!_eligible || _busy || _requests >= 2) return;
    final boundaryContext = _boundaryKey.currentContext;
    final boundary = boundaryContext?.findRenderObject();
    if (boundaryContext == null ||
        boundary is! _ResourceCaptureRenderBoundary ||
        !boundary.attached ||
        !boundary.hasSize ||
        !boundary.hasPainted ||
        boundary.size.isEmpty) {
      return;
    }
    final size = boundary.size;
    final pixelRatio = View.of(boundaryContext).devicePixelRatio;
    final generation = _generation;
    final writer = widget.writer ?? _store.write;
    final readback = widget.readback ?? _readPixels;
    _busy = true;
    final metadata = <String, Object?>{
      'diagnostic': 'resource-frame-capture-v1',
      'requestIndex': ++_requests,
      'requestedAtUtc': DateTime.now().toUtc().toIso8601String(),
      'captureScope':
          'Resource Map content only; excludes title bar and desktop',
      'stateTiming': 'request-time; not guaranteed to describe the last paint',
      'logicalWidth': size.width,
      'logicalHeight': size.height,
      'devicePixelRatio': pixelRatio,
      'hasScheduledFrame': SchedulerBinding.instance.hasScheduledFrame,
      'schedulerPhase': SchedulerBinding.instance.schedulerPhase.name,
      ..._mapState(boundaryContext),
    };
    unawaited(
      _capture(
        boundary,
        size,
        pixelRatio,
        generation,
        metadata,
        readback,
        writer,
      ),
    );
  }

  Future<void> _capture(
    _ResourceCaptureRenderBoundary boundary,
    Size size,
    double pixelRatio,
    int generation,
    Map<String, Object?> metadata,
    ResourceFrameReadback readback,
    ResourceFrameWriter writer,
  ) async {
    final timer = Stopwatch()..start();
    ResourceFramePixels? pixels;
    var status = 'captured';
    try {
      pixels = await readback(boundary, pixelRatio);
    } catch (_) {
      status = 'readback-failed';
    }
    timer.stop();
    if (!_eligible ||
        generation != _generation ||
        !boundary.attached ||
        !boundary.hasSize ||
        boundary.size != size) {
      status = 'cancelled';
      pixels = null;
    }
    final record = ResourceFrameRecord(
      pixels: pixels,
      metadata: Map<String, Object?>.unmodifiable({
        ...metadata,
        'status': status,
        'readbackMilliseconds': timer.elapsedMilliseconds,
        if (pixels != null) 'pixelWidth': pixels.width,
        if (pixels != null) 'pixelHeight': pixels.height,
      }),
    );
    try {
      // Only frozen Resource pixels reach disk, even if tabs change during IO.
      await writer(record);
    } catch (_) {
      // Diagnostic IO must not interrupt the app or open a focus-changing UI.
    } finally {
      _busy = false;
    }
  }

  static Map<String, Object?> _mapState(BuildContext root) {
    BdoMapCanvas? canvas;
    int? iconCount;
    void visit(Element element) {
      final widget = element.widget;
      if (widget is BdoMapCanvas) canvas ??= widget;
      if (widget is CustomPaint && widget.painter is BdoMapPainter) {
        iconCount ??= (widget.painter! as BdoMapPainter).nodeIconImages.length;
      }
      element.visitChildren(visit);
    }

    root.visitChildElements(visit);
    final map = canvas;
    if (map == null) return {'mapCanvasPresent': false};
    final camera = map.cameraController.camera;
    final tiles = map.tileManager;
    return {
      'mapCanvasPresent': true,
      'cameraZoom': camera.zoom,
      'cameraCenterX': camera.center.x,
      'cameraCenterY': camera.center.y,
      'visualStyle': map.visualStyle.name,
      'visibleTileCoordinates': tiles.visibleCoordinates.length,
      'decodedTileCount': tiles.decodedTileCount,
      'decodedTileRevision': tiles.decodedTileRevision,
      'activeTileRequests': tiles.activeRequestCount,
      'queuedTileRequests': tiles.queuedRequestCount,
      'failedVisibleTiles': tiles.failedVisibleTileCount,
      'decodedNodeIcons': iconCount,
    };
  }

  @override
  Widget build(BuildContext context) =>
      _ResourceCaptureBoundary(key: _boundaryKey, child: widget.child);
}

class _ResourceCaptureBoundary extends SingleChildRenderObjectWidget {
  const _ResourceCaptureBoundary({required super.child, super.key});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _ResourceCaptureRenderBoundary();
}

class _ResourceCaptureRenderBoundary extends RenderRepaintBoundary {
  bool hasPainted = false;

  @override
  void paint(PaintingContext context, Offset offset) {
    super.paint(context, offset);
    hasPainted = true;
  }
}
