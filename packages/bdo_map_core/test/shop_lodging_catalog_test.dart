import 'dart:io';

import 'package:bdo_map_core/bdo_map_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('all submitted town-specific Pearl products map to lodging towns', () {
    final dataset = LodgingDataset.fromJsonString(
      File('assets/data/lodging_houses.json').readAsStringSync(),
    );

    expect(WorkerLodgingShopCatalog.towns, hasLength(28));
    expect(WorkerLodgingShopCatalog.townsByNodeId, hasLength(28));
    for (final offer in WorkerLodgingShopCatalog.towns) {
      final town = dataset.townsByNodeId[offer.townNodeId];
      expect(town, isNotNull, reason: offer.townName);
      expect(town!.isWorkerTown, isTrue, reason: offer.townName);
      expect(town.name, offer.townName, reason: offer.townNodeId);
      expect(offer.pearlCouponLimit, 5, reason: offer.townName);
    }
  });

  test('only explicitly shown town Loyalty products have a verified limit', () {
    const expected = <String>{
      'Heidel',
      'Valencia City',
      'Duvencrune',
      'Velia',
      'Calpheon City',
      'Altinova',
      'Grána',
      'O\'draxxia',
      'Eilton',
    };
    final observed = WorkerLodgingShopCatalog.towns
        .where((town) => town.hasVerifiedLoyaltyCoupon)
        .map((town) => town.townName)
        .toSet();

    expect(observed, expected);
    for (final town in WorkerLodgingShopCatalog.towns) {
      if (expected.contains(town.townName)) {
        expect(town.loyaltyCouponLimit, 1, reason: town.townName);
        expect(town.verifiedStandardSlotLimit, 6, reason: town.townName);
      } else {
        expect(town.loyaltyCouponLimit, isNull, reason: town.townName);
        expect(town.verifiedStandardSlotLimit, 5, reason: town.townName);
      }
    }
  });

  test(
    'source and player-facing aliases resolve without duplicating towns',
    () {
      expect(
        WorkerLodgingShopCatalog.findTown('Moodle Village')?.townNodeId,
        '1785',
      );
      expect(
        WorkerLodgingShopCatalog.findTown(
          'Nampo\'s Moodle Village',
        )?.townNodeId,
        '1785',
      );
      expect(
        WorkerLodgingShopCatalog.findTown('Byeot County')?.townNodeId,
        '1795',
      );
      expect(
        WorkerLodgingShopCatalog.findTown('Nopsae\'s Byeot County')?.townNodeId,
        '1795',
      );
      expect(WorkerLodgingShopCatalog.findTown('Grana')?.townNodeId, '1623');
      expect(WorkerLodgingShopCatalog.findTown('Grána')?.townNodeId, '1623');
      expect(
        WorkerLodgingShopCatalog.findTown('O’draxxia')?.townNodeId,
        '1691',
      );
      expect(WorkerLodgingShopCatalog.findTown('ODRAXXIA')?.townNodeId, '1691');
      expect(WorkerLodgingShopCatalog.findTown('Calpheon')?.townNodeId, '601');
      expect(WorkerLodgingShopCatalog.findTown('Seoul')?.townNodeId, '1853');
      expect(
        WorkerLodgingShopCatalog.findTown('1853')?.townName,
        'Yukjo Street',
      );
      expect(WorkerLodgingShopCatalog.findTown('unknown town'), isNull);
    },
  );

  test('generic promotional choice boxes stay unassigned to every town', () {
    const promotion = WorkerLodgingShopCatalog.resplendentWorkerLodgingBox;

    expect(promotion.purchaseLimit, 2);
    expect(promotion.slotsPerPurchase, 1);
    expect(promotion.maximumUnassignedSlots, 2);
    expect(promotion.requiresPlayerSelectedTown, isTrue);
    for (final town in WorkerLodgingShopCatalog.towns) {
      expect(
        town.verifiedStandardSlotLimit,
        town.pearlCouponLimit + (town.loyaltyCouponLimit ?? 0),
      );
    }
  });

  test(
    'catalog contains product limits only, never personal purchase state',
    () {
      final source = File(
        'lib/src/lodging/shop_lodging_catalog.dart',
      ).readAsStringSync();

      expect(source, isNot(contains('remainingPurchases')));
      expect(source, isNot(contains('purchasedCount')));
      expect(source, isNot(contains('ownedCoupon')));
    },
  );
}
