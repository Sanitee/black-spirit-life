import 'dart:async';

import 'package:bdo_craft_planner_flutter/domain/state/state_copy.dart';
import 'package:bdo_craft_planner_flutter/features/planner/planner.dart';
import 'package:bdo_craft_planner_flutter/visual/visual.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'planner_test_fixture.dart';

const _ids = {
  'marketIds': {
    'Sunrise Herb': '5401',
    'Silver Azalea': '5402',
    'High-Quality Sunrise Herb': '5403',
    'Special Sunrise Herb': '5404',
    'High-Quality Silver Azalea': '5405',
    'Special Silver Azalea': '5406',
  },
};
const _market = PlannerMarketRefresh(
  prices: {
    'Sunrise Herb': 1,
    'High-Quality Sunrise Herb': 400,
    'Special Sunrise Herb': 100,
  },
  stock: {
    'Sunrise Herb': 0,
    'High-Quality Sunrise Herb': 15,
    'Special Sunrise Herb': 2,
    'Silver Azalea': 0,
    'High-Quality Silver Azalea': 0,
    'Special Silver Azalea': 0,
  },
  unlistedItemNames: {},
  fetchedAt: 42,
  summary: 'Prices checked.',
);

Finder quality(Finder parent, String label) => find.descendant(
  of: parent,
  matching: find.byWidgetPredicate(
    (widget) =>
        widget is Semantics && widget.properties.label == '$label quality',
  ),
);

void main() {
  for (final spec in [
    StandardSpec.theme,
    IlluminatedLedgerSpec.theme,
    SakuraNightGardenSpec.theme,
  ]) {
    testWidgets(
      'manual qualities stick and Need First refreshes in ${spec.id}',
      (tester) async {
        await setPlannerTestSize(tester, const Size(1500, 940));
        final requests = <PlannerMarketRequest>[];
        final harness = PlannerTestHarness(
          sunriseNpcPrice: 0,
          supportingDataOverrides: _ids,
          checkPrices: (request) async {
            requests.add(request);
            return _market;
          },
        );
        addTearDown(harness.controller.dispose);
        await tester.pumpWidget(harness.plannerHost(spec: spec));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(PlannerActionKeys.p15));
        await tester.pumpAndSettle();
        final mode = harness.controller.active;
        expect(mode.plan.value.missing.single.name, 'Special Sunrise Herb');
        final queue = find.byKey(
          PlannerActionKeys.row('P14', 'Intermediate Reagent:Sunrise Herb'),
        );
        await tester.tap(quality(queue, 'Normal'));
        await tester.pumpAndSettle();
        expect(mode.plan.value.missing.single.name, 'Sunrise Herb');
        expect(find.text('Out of stock'), findsOneWidget);
        expect(requests.last.forceRefresh, isTrue);
        expect(requests.last.namesForRefresh.toSet(), {'Sunrise Herb'});
        final need = find.byKey(const ValueKey('need-quality:Sunrise Herb'));
        expect(need, findsOneWidget);
        await tester.tap(quality(need, 'High Grade'));
        await tester.pumpAndSettle();
        expect(
          mode.plan.value.missing.single.name,
          'High-Quality Sunrise Herb',
        );
        expect(requests.last.namesForRefresh.toSet(), {
          'High-Quality Sunrise Herb',
        });
        expect(find.text('Stock 15'), findsOneWidget);
        expect(
          tester
              .widget<Semantics>(quality(queue, 'High Grade'))
              .properties
              .selected,
          isTrue,
        );
        mode.updateState(
          (s) => s.copyWith(
            market: s.market.copyWith(
              stock: {...s.market.stock, 'High-Quality Sunrise Herb': 0},
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          mode.plan.value.missing.single.name,
          'High-Quality Sunrise Herb',
        );
        expect(
          requests,
          hasLength(3),
          reason: 'Market results do not trigger a request loop',
        );
        await tester.tap(
          find.descendant(
            of: find.byKey(
              const ValueKey('need-quality:High-Quality Sunrise Herb'),
            ),
            matching: find.text('Auto'),
          ),
        );
        await tester.pumpAndSettle();
        expect(mode.plan.value.missing.single.name, 'Special Sunrise Herb');
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'rapid switches queue the last item behind an in-flight refresh',
    (tester) async {
      await setPlannerTestSize(tester, const Size(1500, 940));
      final pending = Completer<PlannerMarketRefresh>();
      final requests = <PlannerMarketRequest>[];
      final harness = PlannerTestHarness(
        sunriseNpcPrice: 0,
        supportingDataOverrides: _ids,
        checkPrices: (request) {
          requests.add(request);
          return requests.length == 1 ? pending.future : Future.value(_market);
        },
      );
      addTearDown(harness.controller.dispose);
      await tester.pumpWidget(harness.plannerHost());
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(PlannerActionKeys.p15));
      await tester.pump();
      final queue = find.byKey(
        PlannerActionKeys.row('P14', 'Intermediate Reagent:Sunrise Herb'),
      );
      await tester.tap(quality(queue, 'Special Grade'));
      await tester.pump();
      await tester.tap(quality(queue, 'High Grade'));
      await tester.pump();
      expect(requests, hasLength(1));
      pending.complete(_market);
      await tester.pumpAndSettle();
      expect(requests, hasLength(2));
      expect(requests.last.namesForRefresh.toSet(), {
        'High-Quality Sunrise Herb',
      });
      expect(
        harness.controller.active.plan.value.missing.single.name,
        'High-Quality Sunrise Herb',
      );
      expect(tester.takeException(), isNull);
    },
  );
}
