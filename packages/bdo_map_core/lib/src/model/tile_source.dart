import 'dart:math' as math;

import 'map_geometry.dart';

class BdoTileCoordinate {
  const BdoTileCoordinate({
    required this.zoom,
    required this.x,
    required this.y,
  });

  final int zoom;
  final int x;
  final int y;

  String get cacheKey => '${zoom}_${x}_$y';

  @override
  bool operator ==(Object other) {
    return other is BdoTileCoordinate &&
        other.zoom == zoom &&
        other.x == x &&
        other.y == y;
  }

  @override
  int get hashCode => Object.hash(zoom, x, y);

  @override
  String toString() => 'BdoTileCoordinate($zoom, $x, $y)';
}

/// Describes a Cartesian, signed-index tile pyramid.
class BdoTileSource {
  const BdoTileSource({
    required this.id,
    required this.displayName,
    required this.urlTemplate,
    required this.worldBounds,
    required this.attribution,
    required this.usageNotice,
    this.minimumZoom = 0,
    this.maximumZoom = 7,
    this.tileSize = 256,
    this.worldUnitsAtZoomZero = 3276800,
    this.fileExtension = 'webp',
    this.headers = const <String, String>{},
  }) : assert(minimumZoom >= 0),
       assert(maximumZoom >= minimumZoom),
       assert(tileSize > 0),
       assert(worldUnitsAtZoomZero > 0);

  final String id;
  final String displayName;
  final String urlTemplate;
  final BdoMapBounds worldBounds;
  final String attribution;
  final String usageNotice;
  final int minimumZoom;
  final int maximumZoom;
  final int tileSize;
  final double worldUnitsAtZoomZero;
  final String fileExtension;
  final Map<String, String> headers;

  static const workermanCommunity = BdoTileSource(
    id: 'workerman-community-120138d',
    displayName: 'Community world map',
    urlTemplate: 'https://shrddr.github.io/maptiles/{z}/{x}_{y}.webp',
    worldBounds: BdoMapBounds(
      left: -1715200,
      top: -1817600,
      right: 1484800,
      bottom: 896000,
    ),
    attribution: 'Basemap tiles hosted by shrddr / Workerman',
    usageNotice:
        'External community basemap reviewed at tile revision 120138d. '
        'Visited tiles use a bounded, removable local cache and '
        'are never bundled with this application.',
  );

  int tileZoomFor(double zoom) => zoom.floor().clamp(minimumZoom, maximumZoom);

  double scaleForZoom(double zoom) {
    return tileSize / worldUnitsAtZoomZero * math.pow(2, zoom);
  }

  double worldUnitsPerTile(int zoom) {
    return worldUnitsAtZoomZero / math.pow(2, zoom);
  }

  BdoTileCoordinate coordinateFor(BdoMapPoint point, int zoom) {
    final span = worldUnitsPerTile(zoom);
    return BdoTileCoordinate(
      zoom: zoom,
      x: (point.x / span).floor(),
      y: (point.y / span).floor(),
    );
  }

  BdoMapBounds boundsFor(BdoTileCoordinate coordinate) {
    final span = worldUnitsPerTile(coordinate.zoom);
    final left = coordinate.x * span;
    final top = coordinate.y * span;
    return BdoMapBounds(
      left: left,
      top: top,
      right: left + span,
      bottom: top + span,
    );
  }

  Uri uriFor(BdoTileCoordinate coordinate) {
    return Uri.parse(
      urlTemplate
          .replaceAll('{z}', coordinate.zoom.toString())
          .replaceAll('{x}', coordinate.x.toString())
          .replaceAll('{y}', coordinate.y.toString()),
    );
  }

  bool contains(BdoTileCoordinate coordinate) {
    if (coordinate.zoom < minimumZoom || coordinate.zoom > maximumZoom) {
      return false;
    }
    return boundsFor(coordinate).intersects(worldBounds);
  }
}
