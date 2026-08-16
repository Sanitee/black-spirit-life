import 'package:bdo_map_core/bdo_map_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const source = BdoTileSource.workermanCommunity;

  test('maps signed world coordinates to the expected tile', () {
    expect(
      source.coordinateFor(const BdoMapPoint(-1, -1), 0),
      const BdoTileCoordinate(zoom: 0, x: -1, y: -1),
    );
    expect(
      source.coordinateFor(const BdoMapPoint(1, 1), 0),
      const BdoTileCoordinate(zoom: 0, x: 0, y: 0),
    );
    expect(
      source.coordinateFor(const BdoMapPoint(-1, -1), 7),
      const BdoTileCoordinate(zoom: 7, x: -1, y: -1),
    );
  });

  test('creates the community tile URL without losing negative indices', () {
    final uri = source.uriFor(const BdoTileCoordinate(zoom: 6, x: -17, y: 3));

    expect(uri.toString(), 'https://shrddr.github.io/maptiles/6/-17_3.webp');
  });

  test('each zoom level halves the world span per tile', () {
    expect(source.worldUnitsPerTile(0), 3276800);
    expect(source.worldUnitsPerTile(1), 1638400);
    expect(source.worldUnitsPerTile(7), 25600);
  });
}
