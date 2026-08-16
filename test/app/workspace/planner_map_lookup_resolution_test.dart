import 'package:bdo_craft_planner_flutter/app/workspace/application_workspace.dart';
import 'package:bdo_craft_planner_flutter/features/planner/planner.dart';
import 'package:bdo_map_core/bdo_map_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('planner lookup exposes only source types backed by map data', () async {
    final dataset = await BdoResourceMapLoader.loadBundled();

    final manualOnly = resolvePlannerMapLookupAvailability(
      dataset,
      'cobra meat',
    );
    expect(manualOnly.materialName, 'cobra meat');
    expect(manualOnly.hasManualGathering, isTrue);
    expect(manualOnly.manualResourceId, 'item:7922');
    expect(manualOnly.manualLocationCount, greaterThan(0));
    expect(manualOnly.hasWorkerNodes, isFalse);

    final workerOnly = resolvePlannerMapLookupAvailability(dataset, 'Wheat');
    expect(workerOnly.hasManualGathering, isFalse);
    expect(workerOnly.hasWorkerNodes, isTrue);
    expect(workerOnly.workerResourceId, 'item:7001');
    expect(workerOnly.workerNodeCount, greaterThan(0));

    final vendorOnly = resolvePlannerMapLookupAvailability(dataset, ' Salt ');
    expect(vendorOnly.materialName, 'Salt');
    expect(vendorOnly.hasNpcVendors, isTrue);
    expect(vendorOnly.npcVendorCount, 46);
    expect(vendorOnly.hasManualGathering, isFalse);
    expect(vendorOnly.hasWorkerNodes, isFalse);
    expect(vendorOnly.resourceIdFor(PlannerMapLookupSource.npcVendors), isNull);

    final both = resolvePlannerMapLookupAvailability(dataset, ' Thuja   Sap ');
    expect(both.hasManualGathering, isTrue);
    expect(both.manualResourceId, 'item:5020');
    expect(both.hasWorkerNodes, isTrue);
    expect(both.workerResourceId, 'item:5020');
    expect(both.manualLocationCount, greaterThan(0));
    expect(both.workerNodeCount, greaterThan(0));

    final citron = resolvePlannerMapLookupAvailability(dataset, 'Citron');
    expect(citron.hasManualGathering, isTrue);
    expect(citron.manualResourceId, 'item:7360');
    expect(citron.manualLocationCount, 1);
    expect(citron.hasWorkerNodes, isTrue);
    expect(citron.workerResourceId, 'item:7360');
    expect(citron.workerNodeCount, 1);

    final fieldSourceOnly = resolvePlannerMapLookupAvailability(
      dataset,
      'Insectivore Plant Flower',
    );
    expect(fieldSourceOnly.hasManualGathering, isTrue);
    expect(fieldSourceOnly.manualResourceId, 'item:5440');
    expect(
      fieldSourceOnly.manualLocationCount,
      0,
      reason:
          'Poisonous Swamp Plant is a truthful source entry without invented '
          'exact spawn dots.',
    );
    expect(fieldSourceOnly.hasWorkerNodes, isFalse);

    final absent = resolvePlannerMapLookupAvailability(
      dataset,
      'Definitely Not A BDO Material',
    );
    expect(absent.hasAnySource, isFalse);
    expect(absent.hasNpcVendors, isFalse);
    expect(absent.npcVendorCount, 0);
    expect(absent.manualResourceId, isNull);
    expect(absent.workerResourceId, isNull);
  });
}
