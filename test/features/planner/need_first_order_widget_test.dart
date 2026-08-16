import 'dart:async';

import 'package:bdo_craft_planner_flutter/domain/planner/planner_models.dart';
import 'package:bdo_craft_planner_flutter/features/planner/planner.dart';
import 'package:bdo_craft_planner_flutter/features/planner/planner_shared.dart';
import 'package:bdo_craft_planner_flutter/shared/overlays/anchored_popover.dart';
import 'package:bdo_craft_planner_flutter/visual/foundations/theme_spec.dart';
import 'package:bdo_craft_planner_flutter/visual/illuminated_ledger/ledger_spec.dart';
import 'package:bdo_craft_planner_flutter/visual/sakura_night_garden/sakura_spec.dart';
import 'package:bdo_craft_planner_flutter/visual/standard/standard_spec.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'planner_test_fixture.dart';

void main() {
  testWidgets(
    'Need First Tab walks the amount column without changing zero or geometry',
    (tester) async {
      await setPlannerTestSize(tester, const Size(1500, 940));
      const names = <String>[
        'Wolf Blood',
        'Powder of Flame',
        'Powder of Darkness',
      ];

      for (final spec in <ThemeSpec>[
        StandardSpec.theme,
        IlluminatedLedgerSpec.theme,
        SakuraNightGardenSpec.theme,
      ]) {
        final harness = PlannerTestHarness();
        await tester.pumpWidget(
          _host(
            PlannerPlanColumns(
              controller: harness.controller.active,
              plan: _initialPlan(),
              externalActions: harness.actions,
              allowCompletion: false,
              queueTitle: 'Craft Queue',
              needTitle: 'Need First',
            ),
            spec: spec,
          ),
        );
        await tester.pump();

        Finder amount(String name) => find.descendant(
          of: find.byKey(PlannerActionKeys.row('P18', name)),
          matching: find.byType(TextField),
        );
        TextField field(String name) => tester.widget<TextField>(amount(name));

        final initialRect = _inputContainerRect(tester, amount(names.first));
        expect(initialRect.size, const Size(82, 38));
        expect(field(names.first).controller!.text, '0');

        await tester.tap(amount(names.first));
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();

        expect(field(names.first).controller!.text, '0');
        expect(field(names[1]).focusNode!.hasFocus, isTrue);
        expect(
          _inputContainerRect(tester, amount(names.first)),
          initialRect,
          reason: '${spec.id} must not collapse a zero-value field on Tab.',
        );
        expect(find.text('Enter a nonnegative amount'), findsNothing);

        await tester.enterText(amount(names[1]), '12.5');
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        expect(field(names[1]).controller!.text, '12,5');
        expect(field(names[2]).focusNode!.hasFocus, isTrue);

        await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
        await tester.pump();
        expect(field(names[1]).focusNode!.hasFocus, isTrue);

        final validRect = _inputContainerRect(tester, amount(names[1]));
        await tester.enterText(amount(names[1]), 'not a number');
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        expect(find.text('Enter a nonnegative amount'), findsOneWidget);
        expect(
          _inputContainerRect(tester, amount(names[1])).size,
          validRect.size,
          reason: '${spec.id} validation must grow below, not crush the input.',
        );
        expect(tester.takeException(), isNull);
        await harness.controller.dispose();
      }
    },
  );

  testWidgets(
    'Need First keeps a substituted row in place until Check Prices',
    (tester) async {
      await setPlannerTestSize(tester, const Size(1500, 940));
      final harness = PlannerTestHarness();
      final plan = ValueNotifier<PlanResult>(_initialPlan());
      final marketResult = Completer<PlannerMarketRefresh>();
      final actions = PlannerExternalActions(
        openRecipeBook: (_) {},
        copyName: (_) async {},
        checkPrices: (_) => marketResult.future,
      );

      await tester.pumpWidget(
        _host(
          ValueListenableBuilder<PlanResult>(
            valueListenable: plan,
            builder: (context, value, _) => PlannerPlanColumns(
              controller: harness.controller.active,
              plan: value,
              externalActions: actions,
              allowCompletion: false,
              queueTitle: 'Craft Queue',
              needTitle: 'Need First',
            ),
          ),
        ),
      );
      await tester.pump();

      expect(
        _top(tester, 'Wolf Blood'),
        lessThan(_top(tester, 'Powder of Flame')),
      );

      // The new substitute has a lower missing quantity, so the engine sends
      // it last. The visible list keeps the edited choice in its old position.
      plan.value = _substitutedPlan();
      await tester.pump();
      expect(
        _top(tester, 'Sheep Blood'),
        lessThan(_top(tester, 'Powder of Flame')),
      );
      expect(
        _top(tester, 'Powder of Flame'),
        lessThan(_top(tester, 'Powder of Darkness')),
      );

      await tester.tap(find.byKey(PlannerActionKeys.p15));
      await tester.pump();
      expect(
        _top(tester, 'Sheep Blood'),
        lessThan(_top(tester, 'Powder of Flame')),
        reason:
            'An in-flight request must not continuously force engine order.',
      );

      marketResult.complete(
        const PlannerMarketRefresh(
          prices: <String, double>{},
          stock: <String, double>{},
          unlistedItemNames: <String>{},
          fetchedAt: 1,
          summary: 'Market refreshed.',
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(
        _top(tester, 'Powder of Flame'),
        lessThan(_top(tester, 'Powder of Darkness')),
      );
      expect(
        _top(tester, 'Powder of Darkness'),
        lessThan(_top(tester, 'Sheep Blood')),
      );
      plan.dispose();
      await harness.controller.dispose();
    },
  );

  testWidgets('Need First pins a choice that merges into an existing row', (
    tester,
  ) async {
    await setPlannerTestSize(tester, const Size(1500, 940));
    final harness = PlannerTestHarness();
    final marketResult = Completer<PlannerMarketRefresh>();
    final actions = PlannerExternalActions(
      openRecipeBook: (_) {},
      copyName: (_) async {},
      checkPrices: (_) => marketResult.future,
    );

    await tester.pumpWidget(
      _host(
        AnimatedBuilder(
          animation: harness.controller.active.state,
          builder: (context, _) {
            final merged = harness
                .controller
                .active
                .state
                .value
                .substituteChoices
                .values
                .any((value) => value == 'Silver Azalea');
            return PlannerPlanColumns(
              controller: harness.controller.active,
              plan: merged ? _mergedWildPlan() : _initialWildPlan(),
              externalActions: actions,
              allowCompletion: false,
              queueTitle: 'Craft Queue',
              needTitle: 'Need First',
            );
          },
        ),
      ),
    );
    await tester.pump();

    expect(
      _top(tester, 'Sunrise Herb'),
      lessThan(_top(tester, 'Powder of Flame')),
    );
    await tester.tap(find.byKey(PlannerActionKeys.p15));
    await tester.pump();
    await tester.tap(
      find.byKey(
        PlannerActionKeys.row('P12', 'missing:Sunrise Herb:Wild Herbs'),
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(PlannerActionKeys.row('P13', 'Silver Azalea')));
    await tester.pump();

    expect(
      _top(tester, 'Silver Azalea'),
      lessThan(_top(tester, 'Powder of Flame')),
    );
    expect(
      _top(tester, 'Powder of Flame'),
      lessThan(_top(tester, 'Sunrise Herb')),
    );

    marketResult.complete(
      const PlannerMarketRefresh(
        prices: <String, double>{},
        stock: <String, double>{},
        unlistedItemNames: <String>{},
        fetchedAt: 1,
        summary: 'Market refreshed.',
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(
      _top(tester, 'Silver Azalea'),
      lessThan(_top(tester, 'Powder of Flame')),
      reason: 'A later manual choice wins over an older in-flight refresh.',
    );
    expect(tester.takeException(), isNull);
    await harness.controller.dispose();
  });
}

double _top(WidgetTester tester, String name) =>
    tester.getTopLeft(find.byKey(PlannerActionKeys.row('P20', name))).dy;

Widget _host(Widget child, {ThemeSpec spec = StandardSpec.theme}) =>
    AppOverlayCoordinatorHost(
      child: MaterialApp(
        theme: spec.materialTheme(),
        home: ThemeSpecScope(
          spec: spec,
          child: Scaffold(
            body: ColoredBox(
              color: spec.palette.canvas,
              child: Padding(padding: const EdgeInsets.all(12), child: child),
            ),
          ),
        ),
      ),
    );

Rect _inputContainerRect(WidgetTester tester, Finder field) {
  final editable = find.descendant(
    of: field,
    matching: find.byType(EditableText),
  );
  final container = InputDecorator.containerOf(tester.element(editable))!;
  return container.localToGlobal(Offset.zero) & container.size;
}

PlanResult _initialPlan() => _plan(<MissingMaterial>[
  _material('Wolf Blood', 941, choice: _bloodChoice('Wolf Blood')),
  _material('Powder of Flame', 795),
  _material('Powder of Darkness', 730),
]);

PlanResult _substitutedPlan() => _plan(<MissingMaterial>[
  _material('Powder of Flame', 795),
  _material('Powder of Darkness', 730),
  _material('Sheep Blood', 700, choice: _bloodChoice('Sheep Blood')),
]);

PlanResult _initialWildPlan() => _plan(<MissingMaterial>[
  _material('Sunrise Herb', 900, choice: _wildChoice('Sunrise Herb')),
  _material('Powder of Flame', 800),
  _material(
    'Silver Azalea',
    700,
    choice: _otherChoice('Silver Azalea', 'Existing Wild Request'),
  ),
]);

PlanResult _mergedWildPlan() => _plan(<MissingMaterial>[
  _material('Powder of Flame', 800),
  _material(
    'Silver Azalea',
    750,
    choice: _otherChoice('Silver Azalea', 'Existing Wild Request'),
  ),
  _material(
    'Sunrise Herb',
    650,
    choice: _otherChoice('Sunrise Herb', 'Remaining Wild Request'),
  ),
]);

PlanResult _plan(List<MissingMaterial> missing) => PlanResult(
  target: 'Clear Liquid Reagent',
  want: 10,
  steps: const <PlanStep>[],
  missing: missing,
  empty: false,
);

ChoiceMeta _bloodChoice(String selected) => ChoiceMeta(
  parentName: 'Intermediate Reagent',
  original: 'Wolf Blood',
  substituteGroup: 'Blood Group 1',
  options: const <String>['Wolf Blood', 'Sheep Blood'],
  baseName: selected,
);

ChoiceMeta _wildChoice(String selected) => ChoiceMeta(
  parentName: 'Intermediate Reagent',
  original: 'Sunrise Herb',
  substituteGroup: 'Wild Herbs',
  options: const <String>['Sunrise Herb', 'Silver Azalea'],
  baseName: selected,
);

ChoiceMeta _otherChoice(String selected, String parent) => ChoiceMeta(
  parentName: parent,
  original: selected,
  substituteGroup: '$parent Group',
  options: <String>[selected, 'Other'],
  baseName: selected,
);

MissingMaterial _material(String name, double missing, {ChoiceMeta? choice}) =>
    MissingMaterial(
      name: name,
      key: name,
      category: 'Alchemy Materials',
      need: missing,
      have: 0,
      missing: missing,
      choice: choice,
      market: const MarketMaterialState(
        marketable: true,
        stock: 0,
        price: 0,
        buyable: 0,
        unavailable: 0,
        total: 0,
        status: 'missing',
        hasSourceInfo: false,
      ),
    );
