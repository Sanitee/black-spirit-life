import 'package:bdo_gathering_companion/domain/bairog_benchmarks.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'Bairog benchmark set retains source, assumptions and exact coverage',
    () {
      expect(bairogBenchmarkSet.creator, 'Bairog Haan');
      expect(bairogBenchmarkSet.publisher, 'BDO Workshop');
      expect(
        bairogBenchmarkSet.calculatorUrl,
        'https://bdoworkshop.com/gathering-calculator',
      );
      expect(bairogBenchmarkSet.routes, hasLength(20));
      expect(bairogBenchmarkSet.mappedRoutes, hasLength(16));
      expect(bairogBenchmarkSet.unmappedRoutes, hasLength(4));
      expect(bairogBenchmarkSet.conditions.mastery, 2000);
      expect(bairogBenchmarkSet.conditions.gatheringDropRatePercent, 60);
      expect(bairogBenchmarkSet.conditions.includeEvergreenShard, isTrue);
      expect(bairogBenchmarkSet.conditions.marketNetRate, 0.845);
      expect(bairogBenchmarkSet.conditions.energyPotionUnitsPerHour, 6);
      expect(bairogBenchmarkSet.conditions.energyPotionCostPerHour, 18800000);
    },
  );

  test(
    'mapped spot and method pairs are unique and source links are exact',
    () {
      final pairs = <String>{};
      for (final route in bairogBenchmarkSet.routes) {
        expect(route.sourceRouteId, greaterThan(0));
        expect(route.videoUrl, startsWith('https://'));
        expect(route.gathersPerHour, greaterThan(0));
        expect(route.sourceSessionCount, greaterThan(0));
        expect(route.sourceHours, greaterThan(0));
        expect(route.sharpPerHour, greaterThan(0));
        expect(route.dustPerHour, greaterThan(0));
        expect(route.caphrasPerHour, greaterThan(0));
        expect(route.sourceSilverAfterTaxPerHour, greaterThan(0));
        if (route.spotId case final spotId?) {
          expect(pairs.add('$spotId|${route.methodId}'), isTrue);
        }
      }
    },
  );

  test('source leaders and separate Caphras materials stay factual', () {
    BairogRouteBenchmark leader(BairogBenchmarkGoal goal) => bairogBenchmarkSet
        .routes
        .reduce((a, b) => b.score(goal) > a.score(goal) ? b : a);

    expect(
      leader(BairogBenchmarkGoal.sharp).sourceRouteName,
      'Northwestern Gateway Lizard',
    );
    expect(
      leader(BairogBenchmarkGoal.dust).sourceRouteName,
      'North Kaia Mountaintop',
    );
    expect(
      leader(BairogBenchmarkGoal.caphras).sourceRouteName,
      'North Kaia Mountaintop',
    );
    expect(
      leader(BairogBenchmarkGoal.sourceValue).sourceRouteName,
      "Eilton's snowfield cedar sap",
    );
    final northKaia = leader(BairogBenchmarkGoal.caphras);
    expect(northKaia.dustPerHour, 1353);
    expect(northKaia.caphrasPerHour, 130);
    expect(northKaia.dustPerHour, isNot(northKaia.caphrasPerHour));
  });

  test('every route exposes the complete immutable item yield profile', () {
    for (final route in bairogBenchmarkSet.routes) {
      final items = route.itemYields.toList(growable: false);
      expect(items, hasLength(19), reason: route.sourceRouteName);
      expect(
        items.map((item) => item.itemId).toSet(),
        hasLength(19),
        reason: route.sourceRouteName,
      );
      expect(
        items.every((item) => item.name.isNotEmpty && item.perHour > 0),
        isTrue,
        reason: route.sourceRouteName,
      );
      expect(route.itemYield(4998)!.perHour, route.sharpPerHour);
      expect(route.itemYield(721002)!.perHour, route.dustPerHour);
      expect(route.itemYield(721003)!.perHour, route.caphrasPerHour);
      expect(route.itemYield(5651)!.vendorUnitPrice, 10000);
      expect(
        items
            .where((item) => item.itemId != 5651)
            .every((item) => item.vendorUnitPrice == null),
        isTrue,
      );
    }
  });

  test('captured route profiles retain exact Bairog hourly quantities', () {
    final eilton = bairogBenchmarkSet.routes.singleWhere(
      (route) => route.sourceRouteId == 45,
    );
    expect(eilton.itemYield(5024)!.name, 'Snowfield Cedar Sap');
    expect(eilton.itemYield(5024)!.perHour, 28322);
    expect(eilton.itemYield(821469)!.name, 'Evergreen Shard');
    expect(eilton.itemYield(821469)!.perHour, 0.28);
    expect(eilton.itemYield(821371)!.perHour, 1251);

    final northwestern = bairogBenchmarkSet.routes.singleWhere(
      (route) => route.sourceRouteId == 36,
    );
    expect(northwestern.itemYield(6008)!.perHour, 22279);
    expect(northwestern.itemYield(4998)!.perHour, 381);
    expect(northwestern.itemYield(735352)!.perHour, 0.23);

    final caphrasLumbering = bairogBenchmarkSet.routes.singleWhere(
      (route) => route.sourceRouteId == 42,
    );
    expect(caphrasLumbering.itemYield(821116)!.perHour, 15269);
    expect(caphrasLumbering.itemYield(721002)!.perHour, 1151);
    expect(caphrasLumbering.itemYield(721003)!.perHour, 117);
  });

  test('all six Star of Nostos materials map to exact routes and rates', () {
    expect(bairogNostosMaterials.map((material) => material.itemId), <int>[
      821350,
      821348,
      821349,
      821353,
      821351,
      821352,
    ]);
    expect(
      bairogNostosMaterials.map((material) => material.gatheringActivity),
      <String>[
        'Hoe Gathering',
        'Lumbering',
        'Fluid Collecting',
        'Mining',
        'Butchering',
        'Tanning',
      ],
    );

    const expectedByMaterial = <int, Map<int, double>>{
      821350: <int, double>{39: 109},
      821348: <int, double>{35: 105, 42: 92},
      821349: <int, double>{40: 107, 44: 104, 45: 101, 43: 99, 52: 95, 46: 85},
      821353: <int, double>{41: 115, 34: 74},
      821351: <int, double>{17: 116, 51: 104, 48: 93, 49: 92, 50: 77},
      821352: <int, double>{47: 100, 36: 80, 38: 78, 37: 78},
    };

    final routesCovered = <int>{};
    for (final material in bairogNostosMaterials) {
      expect(material.iconAssetPath, contains('${material.itemId}.webp'));
      expect(material.nativeIconPath, contains('00${material.itemId}.webp'));
      final actual = <int, double>{};
      for (final route in bairogBenchmarkSet.routes) {
        if (route.nostosYield.itemId != material.itemId) continue;
        expect(route.methodId, material.methodId);
        actual[route.sourceRouteId] = route.nostosYield.perHour;
        routesCovered.add(route.sourceRouteId);
      }
      expect(actual, expectedByMaterial[material.itemId]);
      expect(bairogNostosMaterialFor(material.itemId), same(material));
    }
    expect(routesCovered, hasLength(20));
    expect(bairogNostosMaterialFor(-1), isNull);
  });
}
