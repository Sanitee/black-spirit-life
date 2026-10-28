import 'package:bdo_craft_planner_flutter/app/first_run_setup.dart';
import 'package:bdo_craft_planner_flutter/app/first_run_setup_view.dart';
import 'package:bdo_craft_planner_flutter/domain/state/planner_state.dart';
import 'package:bdo_craft_planner_flutter/domain/state/state_copy.dart';
import 'package:bdo_craft_planner_flutter/visual/visual.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import '../domain/state/state_test_fixture.dart';
import '../support/application_test_harness.dart';

PlannerState setupDocument({bool filled = false}) {
  final doc = buildStateFixture();
  return doc.copyWith(
    alchemy: doc.alchemy.copyWith(alchemyMastery: filled ? 1914 : 0),
    cooking: doc.cooking.copyWith(cookingMastery: filled ? 1894 : 0),
    processing: doc.processing.copyWith(
      processingMastery: filled ? 1767 : 0,
      useMassProcessing: filled,
    ),
    afkWeightProfile: doc.afkWeightProfile.copyWith(
      maximumWeightLt: filled ? 4024 : 0,
      currentCarriedWeightLt: filled ? 107.1 : 0,
      safetyBufferLt: filled ? 100 : 0,
      featheryStepsLevel: filled ? 5 : 0,
    ),
    marketTax: doc.marketTax.copyWith(
      valuePack: filled,
      merchantRing: false,
      familyFameBonus: filled ? .015 : 0,
    ),
  );
}

Future<void> pumpSetup(
  WidgetTester tester, {
  PlannerState? document,
  bool busy = false,
  List<FirstRunSetupGroup> groups = FirstRunSetupSchema.groups,
  double scale = 1,
  ThemeSpec? theme,
  ValueChanged<FirstRunSetupAnswers>? onFinish,
  VoidCallback? onSkip,
}) async {
  final spec = theme ?? SakuraNightGardenSpec.theme;
  await tester.pumpWidget(
    MaterialApp(
      theme: spec.materialTheme(),
      home: ThemeSpecScope(
        spec: spec,
        child: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: RepaintBoundary(
            key: const ValueKey('setup-capture'),
            child: FirstRunSetupView(
              document: document ?? setupDocument(),
              groups: groups,
              busy: busy,
              error: null,
              onSkip: onSkip ?? () {},
              onFinish: onFinish ?? (_) {},
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder setupField(String key) => find.descendant(
  of: find.byKey(ValueKey(key)),
  matching: find.byType(EditableText),
);
AppButton saveButton(WidgetTester tester) => tester.widget<AppButton>(
  find.byKey(const ValueKey('first-run-setup-finish')),
);
Future<void> openSetup(WidgetTester tester, FirstRunSetupGroup group) async {
  final header = find.byKey(ValueKey('setup-section-${group.name}'));
  await tester.ensureVisible(header);
  await tester.tap(header);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('zero and blank setup disables Save but Skip is non-mutating', (
    tester,
  ) async {
    configureApplicationTestSurface(tester, const Size(1200, 752));
    final doc = setupDocument(), before = doc.toJson();
    var skipped = 0, saved = 0;
    await pumpSetup(
      tester,
      document: doc,
      onSkip: () => skipped++,
      onFinish: (_) => saved++,
    );
    expect(saveButton(tester).onPressed, isNull);
    await tester.tap(find.byKey(const ValueKey('first-run-setup-finish')));
    await tester.pump();
    expect(saved, 0);
    await tester.enterText(setupField('setup-alchemy-mastery'), '1');
    await tester.pumpAndSettle();
    expect(saveButton(tester).onPressed, isNotNull);
    await tester.enterText(setupField('setup-alchemy-mastery'), '');
    await tester.pumpAndSettle();
    expect(saveButton(tester).onPressed, isNull);
    await tester.tap(find.byKey(const ValueKey('first-run-setup-skip')));
    expect(skipped, 1);
    expect(saved, 0);
    expect(doc.toJson(), before);
  });
  testWidgets(
    'partial answers survive folding and finish without visiting all groups',
    (tester) async {
      configureApplicationTestSurface(tester, const Size(1200, 752));
      FirstRunSetupAnswers? saved;
      await pumpSetup(tester, onFinish: (value) => saved = value);
      await tester.enterText(setupField('setup-cooking-mastery'), '1200');
      await openSetup(tester, FirstRunSetupGroup.afkLoad);
      await tester.enterText(
        setupField('setup-maximum-weight-lt'),
        '10000,125',
      );
      await tester.tap(find.byKey(const ValueKey('setup-feathery-steps-5')));
      await tester.pumpAndSettle();
      await openSetup(tester, FirstRunSetupGroup.masteryAndOutput);
      expect(
        tester
            .widget<EditableText>(setupField('setup-cooking-mastery'))
            .controller
            .text,
        '1200',
      );
      await tester.tap(find.byKey(const ValueKey('first-run-setup-finish')));
      expect(saved!.cookingMastery, 1200);
      expect(saved!.alchemyMastery, 0);
      expect(saved!.maximumWeightLt, 10000.125);
      expect(saved!.featheryStepsLevel, 5);
      expect(saved!.valuePack, isFalse);
    },
  );
  testWidgets('bonus-only setup saves and invalid LT blocks Save', (
    tester,
  ) async {
    configureApplicationTestSurface(tester, const Size(1200, 752));
    await pumpSetup(tester);
    await openSetup(tester, FirstRunSetupGroup.marketSales);
    await tester.tap(find.byKey(const ValueKey('setup-value-pack')));
    await tester.pumpAndSettle();
    expect(saveButton(tester).onPressed, isNotNull);
    await openSetup(tester, FirstRunSetupGroup.afkLoad);
    await tester.enterText(setupField('setup-maximum-weight-lt'), '.');
    await tester.pumpAndSettle();
    expect(saveButton(tester).onPressed, isNull);
    expect(find.byKey(const ValueKey('first-run-setup-error')), findsOneWidget);
    await tester.enterText(setupField('setup-maximum-weight-lt'), '0');
    await tester.pumpAndSettle();
    expect(saveButton(tester).onPressed, isNotNull);
  });
  testWidgets('pending group cannot be enabled by hidden preexisting data', (
    tester,
  ) async {
    configureApplicationTestSurface(tester, const Size(1200, 752));
    final doc = setupDocument(filled: true);
    await pumpSetup(
      tester,
      document: doc.copyWith(
        afkWeightProfile: setupDocument().afkWeightProfile,
      ),
      groups: [FirstRunSetupGroup.afkLoad],
    );
    expect(saveButton(tester).onPressed, isNull);
    expect(find.text('Mastery'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('setup-feathery-steps-1')));
    await tester.pumpAndSettle();
    expect(saveButton(tester).onPressed, isNotNull);
  });
  testWidgets('matching actions, busy guards and untouched precise values', (
    tester,
  ) async {
    configureApplicationTestSurface(tester, const Size(1200, 752));
    final doc = setupDocument(filled: true);
    FirstRunSetupAnswers? saved;
    await pumpSetup(
      tester,
      document: doc.copyWith(
        afkWeightProfile: doc.afkWeightProfile.copyWith(
          safetyBufferLt: 25.000000123,
        ),
      ),
      onFinish: (a) => saved = a,
    );
    final skip = find.byKey(const ValueKey('first-run-setup-skip')),
        save = find.byKey(const ValueKey('first-run-setup-finish'));
    expect(tester.getSize(skip), tester.getSize(save));
    expect(tester.widget<AppButton>(skip).role, saveButton(tester).role);
    await tester.tap(save);
    expect(saved!.safetyBufferLt, 25.000000123);
    expect(saved!.alchemyMastery, 1914);
    await pumpSetup(tester, document: doc, busy: true);
    for (final e in find.byType(AppButton).evaluate()) {
      expect((e.widget as AppButton).onPressed, isNull);
    }
    for (final e in find.byType(AppTextField).evaluate()) {
      expect((e.widget as AppTextField).enabled, isFalse);
    }
  });
  testWidgets('whole section headers collapse and activate by keyboard', (
    tester,
  ) async {
    configureApplicationTestSurface(tester, const Size(1200, 752));
    await pumpSetup(tester);
    await openSetup(tester, FirstRunSetupGroup.masteryAndOutput);
    expect(find.byType(EditableText), findsNothing);
    final header = find.byKey(const ValueKey('setup-section-afkLoad'));
    final detector = tester.widget<FocusableActionDetector>(
      find.descendant(
        of: header,
        matching: find.byType(FocusableActionDetector),
      ),
    );
    detector.focusNode!.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(setupField('setup-maximum-weight-lt'), findsOneWidget);
    expect(detector.focusNode!.hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byType(EditableText), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
