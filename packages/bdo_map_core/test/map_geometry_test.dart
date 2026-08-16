import 'package:bdo_map_core/bdo_map_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Bdo world geometry', () {
    test('converts canonical X/Z to map X/-Z', () {
      const world = BdoWorldPoint(12500, -42000);

      expect(world.mapPoint, const BdoMapPoint(12500, 42000));
      expect(world.mapPoint.worldPoint, world);
    });

    test('bounds intersection includes touching edges', () {
      const first = BdoMapBounds(left: 0, top: 0, right: 10, bottom: 10);
      const second = BdoMapBounds(left: 10, top: 5, right: 20, bottom: 15);

      expect(first.intersects(second), isTrue);
      expect(first.contains(const BdoMapPoint(10, 10)), isTrue);
    });
  });
}
