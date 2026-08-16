import 'package:bdo_map_core/bdo_map_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'Calpheon maximum is unique mapped capacity and exact plans are stable',
    () async {
      final dataset = await LodgingDataLoader.loadBundled();
      final town = dataset.towns.singleWhere(
        (candidate) => candidate.name == 'Calpheon City',
      );

      expect(town.houses, hasLength(267));
      expect(town.housesById, hasLength(267));
      expect(
        town.houses.map((house) => house.sourceKey).toSet(),
        hasLength(267),
      );
      expect(town.lodgingHouses, hasLength(48));
      final mappedLodgingSlots = town.lodgingHouses.fold<int>(
        0,
        (total, house) => total + house.lodgingSpaces,
      );
      expect(town.baseWorkerSlots, 1);
      expect(mappedLodgingSlots, 94);
      expect(town.baseWorkerSlots + mappedLodgingSlots, 95);

      for (
        var required = town.baseWorkerSlots;
        required <= town.baseWorkerSlots + mappedLodgingSlots;
        required += 1
      ) {
        final first = LodgingOptimizer.solve(
          town: town,
          requiredCapacity: required,
          existingCapacity: town.baseWorkerSlots,
        );
        final repeated = LodgingOptimizer.solve(
          town: town,
          requiredCapacity: required,
          existingCapacity: town.baseWorkerSlots,
        );
        expect(repeated.selectedLodgingHouseIds, first.selectedLodgingHouseIds);
        expect(repeated.newlyRequiredHouseIds, first.newlyRequiredHouseIds);
        expect(
          repeated.incrementalContributionPoints,
          first.incrementalContributionPoints,
        );
        expect(repeated.addedCapacity, first.addedCapacity);
        expect(
          first.selectedLodgingHouseIds.toSet(),
          hasLength(first.selectedLodgingHouseIds.length),
        );
        expect(
          first.selectedLodgingHouseIds.fold<int>(
            0,
            (total, houseId) => total + town.housesById[houseId]!.lodgingSpaces,
          ),
          first.addedCapacity,
        );
      }

      final maximum = LodgingOptimizer.solve(
        town: town,
        requiredCapacity: 95,
        existingCapacity: town.baseWorkerSlots,
      );
      expect(maximum.isFeasible, isTrue);
      expect(maximum.selectedLodgingHouseIds, hasLength(48));
      expect(maximum.addedCapacity, 94);
    },
  );
}
