import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../model/map_geometry.dart';
import '../model/tile_source.dart';

class BdoMapCamera {
  const BdoMapCamera({required this.center, required this.zoom});

  final BdoMapPoint center;
  final double zoom;

  BdoMapCamera copyWith({BdoMapPoint? center, double? zoom}) {
    return BdoMapCamera(center: center ?? this.center, zoom: zoom ?? this.zoom);
  }
}

class BdoMapCameraController extends ChangeNotifier {
  /// Keeps the highest-detail tile visible while allowing a closer inspection
  /// of dense cities and housing layouts.
  static const double maximumOverzoom = 2;

  static double maximumZoomFor(BdoTileSource tileSource) =>
      tileSource.maximumZoom.toDouble() + maximumOverzoom;

  BdoMapCameraController({
    required BdoTileSource tileSource,
    BdoMapCamera? initialCamera,
  }) : _tileSource = tileSource,
       _camera =
           initialCamera ??
           BdoMapCamera(
             center: tileSource.worldBounds.center,
             zoom: tileSource.minimumZoom.toDouble(),
           ) {
    _scale = _tileSource.scaleForZoom(_camera.zoom);
  }

  BdoTileSource _tileSource;
  BdoMapCamera _camera;
  late double _scale;

  BdoTileSource get tileSource => _tileSource;
  BdoMapCamera get camera => _camera;
  double get minimumZoom => _tileSource.minimumZoom.toDouble();
  double get maximumZoom => maximumZoomFor(_tileSource);

  set tileSource(BdoTileSource value) {
    if (identical(value, _tileSource)) {
      return;
    }
    _tileSource = value;
    _scale = _tileSource.scaleForZoom(
      _camera.zoom.clamp(minimumZoom, maximumZoom),
    );
    _camera = _clamp(_camera, Size.zero);
    _scale = _tileSource.scaleForZoom(_camera.zoom);
    notifyListeners();
  }

  Offset worldToScreen(BdoMapPoint point, Size viewport) {
    return Offset(
      viewport.width / 2 + (point.x - _camera.center.x) * _scale,
      viewport.height / 2 + (point.y - _camera.center.y) * _scale,
    );
  }

  BdoMapPoint screenToWorld(Offset point, Size viewport) {
    return BdoMapPoint(
      _camera.center.x + (point.dx - viewport.width / 2) / _scale,
      _camera.center.y + (point.dy - viewport.height / 2) / _scale,
    );
  }

  BdoMapBounds visibleWorldBounds(Size viewport) {
    final topLeft = screenToWorld(Offset.zero, viewport);
    final bottomRight = screenToWorld(
      Offset(viewport.width, viewport.height),
      viewport,
    );
    return BdoMapBounds(
      left: topLeft.x,
      top: topLeft.y,
      right: bottomRight.x,
      bottom: bottomRight.y,
    );
  }

  void panBy(Offset screenDelta, Size viewport) {
    setCamera(
      _camera.copyWith(
        center: _camera.center.translate(
          -screenDelta.dx / _scale,
          -screenDelta.dy / _scale,
        ),
      ),
      viewport,
    );
  }

  void zoomAround({
    required double zoom,
    required Offset anchor,
    required Size viewport,
  }) {
    final clampedZoom = zoom.clamp(minimumZoom, maximumZoom);
    final anchorWorld = screenToWorld(anchor, viewport);
    final newScale = _tileSource.scaleForZoom(clampedZoom);
    final newCenter = BdoMapPoint(
      anchorWorld.x - (anchor.dx - viewport.width / 2) / newScale,
      anchorWorld.y - (anchor.dy - viewport.height / 2) / newScale,
    );
    setCamera(BdoMapCamera(center: newCenter, zoom: clampedZoom), viewport);
  }

  void showPoint(
    BdoWorldPoint point, {
    required Size viewport,
    double zoom = 5.4,
  }) {
    setCamera(BdoMapCamera(center: point.mapPoint, zoom: zoom), viewport);
  }

  void fitBounds(
    BdoMapBounds bounds, {
    required Size viewport,
    double padding = 80,
    double maximumZoom = 6.4,
    double insetLeft = 0,
    double insetTop = 0,
    double insetRight = 0,
    double insetBottom = 0,
  }) {
    assert(padding >= 0);
    assert(insetLeft >= 0);
    assert(insetTop >= 0);
    assert(insetRight >= 0);
    assert(insetBottom >= 0);
    final usableWidth = math.max(
      1,
      viewport.width - insetLeft - insetRight - padding * 2,
    );
    final usableHeight = math.max(
      1,
      viewport.height - insetTop - insetBottom - padding * 2,
    );
    final baseScale = _tileSource.tileSize / _tileSource.worldUnitsAtZoomZero;
    final requiredScale = math.min(
      usableWidth / math.max(bounds.width, 1),
      usableHeight / math.max(bounds.height, 1),
    );
    final minimumZoom = this.minimumZoom;
    final maximumAllowedZoom = math.max(
      minimumZoom,
      math.min(maximumZoom, this.maximumZoom),
    );
    final zoom = (math.log(requiredScale / baseScale) / math.ln2)
        .clamp(minimumZoom, maximumAllowedZoom)
        .toDouble();
    final scale = _tileSource.scaleForZoom(zoom);
    final targetCenter = Offset(
      insetLeft + padding + usableWidth / 2,
      insetTop + padding + usableHeight / 2,
    );
    final viewportCenter = Offset(viewport.width / 2, viewport.height / 2);
    setCamera(
      BdoMapCamera(
        center: BdoMapPoint(
          bounds.center.x - (targetCenter.dx - viewportCenter.dx) / scale,
          bounds.center.y - (targetCenter.dy - viewportCenter.dy) / scale,
        ),
        zoom: zoom,
      ),
      viewport,
    );
  }

  void reset(Size viewport) {
    fitBounds(
      _tileSource.worldBounds,
      viewport: viewport,
      padding: 24,
      maximumZoom: 3,
    );
  }

  void setCamera(BdoMapCamera value, Size viewport) {
    final next = _clamp(value, viewport);
    if (next.center == _camera.center && next.zoom == _camera.zoom) {
      return;
    }
    final zoomChanged = next.zoom != _camera.zoom;
    _camera = next;
    if (zoomChanged) {
      _scale = _tileSource.scaleForZoom(next.zoom);
    }
    notifyListeners();
  }

  BdoMapCamera _clamp(BdoMapCamera value, Size viewport) {
    final zoom = value.zoom.clamp(minimumZoom, maximumZoom);
    final scale = zoom == _camera.zoom
        ? _scale
        : _tileSource.scaleForZoom(zoom);
    final halfWorldWidth = viewport.width <= 0
        ? 0.0
        : viewport.width / scale / 2;
    final halfWorldHeight = viewport.height <= 0
        ? 0.0
        : viewport.height / scale / 2;
    final bounds = _tileSource.worldBounds;

    double clampAxis(
      double coordinate,
      double minimum,
      double maximum,
      double halfViewport,
    ) {
      final paddedMinimum = minimum - halfViewport * 0.35;
      final paddedMaximum = maximum + halfViewport * 0.35;
      if (paddedMinimum >= paddedMaximum) {
        return (minimum + maximum) / 2;
      }
      return coordinate.clamp(paddedMinimum, paddedMaximum).toDouble();
    }

    return BdoMapCamera(
      center: BdoMapPoint(
        clampAxis(value.center.x, bounds.left, bounds.right, halfWorldWidth),
        clampAxis(value.center.y, bounds.top, bounds.bottom, halfWorldHeight),
      ),
      zoom: zoom,
    );
  }
}
