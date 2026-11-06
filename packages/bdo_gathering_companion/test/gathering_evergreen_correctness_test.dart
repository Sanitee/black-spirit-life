import 'dart:convert';
import 'dart:io';

import 'package:bdo_gathering_companion/src/domain/bairog_calculator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final raw =
      jsonDecode(File('assets/data/bairog_calculator.json').readAsStringSync())
          as Map<String, dynamic>;
  final data = BairogCalculatorData.fromJson(raw);
  final current = BairogCalculator(data);
  final oldRaw = jsonDecode(jsonEncode(raw)) as Map<String, dynamic>;
  (oldRaw['gatheringItemTypes'] as List).singleWhere(
    (e) => e['id'] == 27,
  )['procs_with_minigame'] = false;
  final old = BairogCalculator(BairogCalculatorData.fromJson(oldRaw));

  for (final route in data.rotations) {
    for (final mode in BairogMinigameMode.values) {
      test(
        '${route.name} $mode: only the shard minigame contribution changes',
        () {
          final settings = BairogCalculatorSettings(
            minigameMode: mode,
            hedgehogTier: BairogHedgehogTier.tier4,
            enabledExpenseItemIds: {},
            showTaxed: false,
          );
          const prices = {821469: 1000000.0};
          final before = old.projectRoute(
            routeId: route.id,
            settings: settings,
            marketPricesByBdoItemId: prices,
          );
          final after = current.projectRoute(
            routeId: route.id,
            settings: settings,
            marketPricesByBdoItemId: prices,
          );
          for (final item in after.items) {
            final previous = before.itemByBdoId(item.itemType.item.id)!;
            if (item.itemType.item.id != 821469) {
              expect(item.totalPerHour, previous.totalPerHour);
              continue;
            }
            final factor = mode.expectedYieldFactor / (1 - mode.procChance);
            expect(
              item.basePerHour,
              closeTo(previous.basePerHour * factor, 1e-10),
            );
            expect(item.hedgehogPerHour, previous.hedgehogPerHour);
            expect(item.afuaruPerHour, previous.afuaruPerHour);
            expect(item.chestPerHour, previous.chestPerHour);
            expect(item.chestX10PerHour, previous.chestX10PerHour);
            expect(item.feverTimePerHour, previous.feverTimePerHour);
            expect(
              after.totalSilverPerHour - before.totalSilverPerHour,
              closeTo(
                (item.basePerHour - previous.basePerHour) * 1000000,
                1e-6,
              ),
            );
          }
          expect(
            after.sourceBenchmark?.sourceHours,
            before.sourceBenchmark?.sourceHours,
          );
          expect(
            after.sourceBenchmark?.sourceSessionCount,
            before.sourceBenchmark?.sourceSessionCount,
          );
        },
      );
    }
  }
}
