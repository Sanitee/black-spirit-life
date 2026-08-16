import 'package:bdo_map_core/bdo_map_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'bundled Royal Workshop catalog retains real production and goods',
    () async {
      final goods = await const BdoRoyalWorkshopGoodsLoader().load();
      final byId = <int, BdoRoyalWorkshopGood>{
        for (final good in goods) good.id: good,
      };

      expect(goods, hasLength(124));
      expect(
        goods.where((good) => good.kind == BdoRoyalWorkshopKind.production),
        hasLength(40),
      );
      expect(
        goods.where((good) => good.kind == BdoRoyalWorkshopKind.processing),
        hasLength(84),
      );
      expect(byId[821044]?.name, 'Hyojason');
      expect(byId[821044]?.kind, BdoRoyalWorkshopKind.processing);
      expect(byId[821136]?.name, 'Bountiful Feast');
      expect(byId[821136]?.rareRoll, isTrue);
      expect(byId[821136]?.durationAt150WorkerSpeedHours, 29);
    },
  );
}
