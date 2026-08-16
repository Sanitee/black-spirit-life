import 'dart:async';
import 'dart:io';

import 'package:bdo_craft_planner_flutter/app/app.dart';
import 'package:bdo_craft_planner_flutter/app/first_run_setup.dart';
import 'package:bdo_craft_planner_flutter/app/first_run_setup_view.dart';
import 'package:bdo_craft_planner_flutter/domain/state/state_copy.dart';
import 'package:bdo_craft_planner_flutter/features/planner/planner.dart';
import 'package:bdo_craft_planner_flutter/visual/components/app_button.dart';
import 'package:bdo_craft_planner_flutter/visual/components/app_form_controls.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/application_test_harness.dart';

void main() {
  testWidgets('setup skips for one launch, then completes durably', (
    tester,
  ) async {
    configureApplicationTestSurface(tester, const Size(1200, 800));
    var harness = (await tester.runAsync(
      () => ApplicationTestHarness.create(setupCompleted: false),
    ))!;
    await tester.runAsync(harness.disposeControllerOnly);
    harness = harness.rebindControllerInCurrentZone();
    final masteryBeforeSkip =
        harness.bundle.controller.documentSnapshot.alchemy.alchemyMastery;

    await tester.pumpWidget(
      BdoCraftPlannerApp(applicationFuture: Future.value(harness.bundle)),
    );
    await tester.pumpAndSettle();

    expect(find.byType(FirstRunSetupView), findsOneWidget);
    expect(find.text('Set up your planner'), findsOneWidget);
    expect(find.textContaining('Enter your Alchemy'), findsNothing);
    expect(find.text('Mastery'), findsOneWidget);
    expect(find.text('Mastery & output'), findsNothing);
    expect(find.textContaining('Enter each Mastery'), findsNothing);
    _expectMasteryValue(tester, 'setup-alchemy-mastery', '0');
    _expectMasteryValue(tester, 'setup-cooking-mastery', '0');
    _expectMasteryValue(tester, 'setup-processing-mastery', '0');
    expect(
      tester
          .widget<AppToggle>(
            find.byKey(const ValueKey<String>('setup-mass-processing')),
          )
          .value,
      isFalse,
    );
    _expectSmallerThanSetupHeading(tester, 'Mastery');
    expect(find.byType(PlannerView), findsNothing);

    await tester.ensureVisible(
      find.byKey(const ValueKey<String>('first-run-setup-skip')),
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('first-run-setup-skip')),
    );
    await tester.pumpAndSettle();

    expect(find.byType(FirstRunSetupView), findsNothing);
    expect(find.byType(PlannerView), findsOneWidget);
    final deferred = FirstRunSetupProgress.fromDocument(
      harness.bundle.controller.documentSnapshot,
    );
    expect(deferred.completed, isFalse);
    expect(deferred.shouldShow, isTrue);
    expect(
      harness.bundle.controller.documentSnapshot.alchemy.alchemyMastery,
      masteryBeforeSkip,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    harness = harness.rebindControllerInCurrentZone();
    await tester.pumpWidget(
      BdoCraftPlannerApp(applicationFuture: Future.value(harness.bundle)),
    );
    await tester.pumpAndSettle();

    expect(find.byType(FirstRunSetupView), findsOneWidget);
    _expectMasteryValue(tester, 'setup-alchemy-mastery', '0');
    _expectMasteryValue(tester, 'setup-cooking-mastery', '0');
    _expectMasteryValue(tester, 'setup-processing-mastery', '0');
    await _enterMastery(
      tester,
      'setup-alchemy-mastery',
      '9999999999999999999999999999999999999999999999999999999999999999'
          '9999999999999999999999999999999999999999999999999999999999999999',
    );
    _expectMasteryValue(tester, 'setup-alchemy-mastery', '3000');
    await _enterMastery(tester, 'setup-cooking-mastery', '-10');
    _expectMasteryValue(tester, 'setup-cooking-mastery', '0');
    await _enterMastery(tester, 'setup-cooking-mastery', '875');
    await _enterMastery(tester, 'setup-processing-mastery', '3000');
    _expectMasteryValue(tester, 'setup-processing-mastery', '3000');
    await _enterMastery(tester, 'setup-processing-mastery', '1450');
    await tester.tap(
      find.byKey(const ValueKey<String>('setup-mass-processing')),
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey<String>('first-run-setup-next')),
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('first-run-setup-next')),
    );
    await tester.pumpAndSettle();

    expect(find.text('AFK Load'), findsOneWidget);
    _expectSmallerThanSetupHeading(tester, 'AFK Load');
    _expectFieldValue(tester, 'setup-maximum-weight-lt', '0');
    _expectFieldValue(tester, 'setup-current-carried-weight-lt', '0');
    _expectFieldValue(tester, 'setup-safety-buffer-lt', '0');
    expect(find.text('LT to keep free'), findsOneWidget);
    expect(find.text('Leave unused'), findsNothing);
    expect(find.text('Fairy · Feathery Steps'), findsOneWidget);
    expect(find.text('None · 100%'), findsOneWidget);
    await _enterField(tester, 'setup-current-carried-weight-lt', '-10');
    _expectFieldValue(tester, 'setup-current-carried-weight-lt', '0');
    await _enterField(tester, 'setup-maximum-weight-lt', '1850,5');
    await _enterField(tester, 'setup-current-carried-weight-lt', '125.25');
    await _enterField(tester, 'setup-safety-buffer-lt', '30');
    final feathery = tester.widget<AppSelect<int>>(
      find.byKey(const ValueKey<String>('setup-feathery-steps')),
    );
    expect(feathery.value, 0);
    feathery.onChanged!(4);
    await tester.pump();
    await tester.ensureVisible(
      find.byKey(const ValueKey<String>('first-run-setup-next')),
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('first-run-setup-next')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Market sales'), findsOneWidget);
    expect(find.textContaining('Choose the bonuses that apply'), findsNothing);
    _expectSmallerThanSetupHeading(tester, 'Market sales');
    expect(
      find.byKey(const ValueKey<String>('market-bonus:valuePack')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('market-bonus:richMerchantsRing')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<AppToggle>(
            find.byKey(const ValueKey<String>('setup-value-pack')),
          )
          .value,
      isFalse,
    );
    expect(
      tester
          .widget<AppToggle>(
            find.byKey(const ValueKey<String>('setup-merchant-ring')),
          )
          .value,
      isFalse,
    );
    expect(
      tester
          .widget<AppSelect<double>>(
            find.byKey(const ValueKey<String>('setup-family-fame')),
          )
          .value,
      0,
    );
    expect(find.text('Below 1,000 - +0%'), findsOneWidget);
    expect(
      find.text('Estimated silver received: 65% of the sale price.'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey<String>('setup-value-pack')));
    await tester.ensureVisible(
      find.byKey(const ValueKey<String>('first-run-setup-finish')),
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('first-run-setup-finish')),
    );
    await tester.pumpAndSettle();

    final notice = find.byKey(
      const ValueKey<String>('first-run-setup-location-notice'),
    );
    expect(notice, findsOneWidget);
    expect(
      find.text('You can change these settings later in Craft Profile.'),
      findsOneWidget,
    );
    expect(
      find.descendant(of: notice, matching: find.byType(AppButton)),
      findsOneWidget,
    );
    expect(find.byType(PlannerView), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('first-run-setup-error')),
      findsNothing,
    );
    final document = harness.bundle.controller.documentSnapshot;
    expect(
      FirstRunSetupProgress.fromDocument(document).shouldShow,
      isFalse,
      reason: 'saved extensions: ${document.extensions}',
    );
    expect(document.alchemy.alchemyMastery, 3000);
    expect(document.cooking.cookingMastery, 875);
    expect(document.processing.processingMastery, 1450);
    expect(document.processing.useMassProcessing, isTrue);
    expect(document.afkWeightProfile.maximumWeightLt, 1850.5);
    expect(document.afkWeightProfile.currentCarriedWeightLt, 125.25);
    expect(document.afkWeightProfile.safetyBufferLt, 30);
    expect(document.afkWeightProfile.featheryStepsLevel, 4);
    expect(document.marketTax.valuePack, isTrue);

    await tester.tapAt(const Offset(8, 8));
    await tester.pumpAndSettle();
    expect(notice, findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(notice, findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey<String>('first-run-setup-location-okay')),
    );
    await tester.pumpAndSettle();

    expect(find.byType(FirstRunSetupView), findsNothing);
    expect(find.byType(PlannerView), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(harness.dispose);
  });

  testWidgets('setup skip remains session-only when profile writes fail', (
    tester,
  ) async {
    configureApplicationTestSurface(tester, const Size(1200, 800));
    var saveAttempts = 0;
    var harness = (await tester.runAsync(
      () => ApplicationTestHarness.create(setupCompleted: false),
    ))!;
    await tester.runAsync(harness.disposeControllerOnly);
    harness = harness.rebindControllerInCurrentZone(
      saveStateFactory: (_) => (state) async {
        saveAttempts += 1;
        throw const FileSystemException('profile is read-only');
      },
    );

    await tester.pumpWidget(
      BdoCraftPlannerApp(applicationFuture: Future.value(harness.bundle)),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('first-run-setup-skip')),
    );
    await tester.pumpAndSettle();

    expect(saveAttempts, 0);
    expect(find.byType(FirstRunSetupView), findsNothing);
    expect(find.byType(PlannerView), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(harness.dispose);
  });

  testWidgets('incomplete imported mastery values remain visible', (
    tester,
  ) async {
    configureApplicationTestSurface(tester, const Size(1200, 800));
    var harness = (await tester.runAsync(() async {
      final value = await ApplicationTestHarness.create(setupCompleted: false);
      await value.bundle.controller.updateDocumentDurably(
        (document) => document.copyWith(
          alchemy: document.alchemy.copyWith(alchemyMastery: 1900),
          cooking: document.cooking.copyWith(cookingMastery: 875),
          processing: document.processing.copyWith(processingMastery: 1450),
        ),
      );
      await value.disposeControllerOnly();
      return value;
    }))!;
    harness = harness.rebindControllerInCurrentZone();

    await tester.pumpWidget(
      BdoCraftPlannerApp(applicationFuture: Future.value(harness.bundle)),
    );
    await tester.pumpAndSettle();

    _expectMasteryValue(tester, 'setup-alchemy-mastery', '1900');
    _expectMasteryValue(tester, 'setup-cooking-mastery', '875');
    _expectMasteryValue(tester, 'setup-processing-mastery', '1450');

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(harness.dispose);
  });

  testWidgets('completed setup stays closed and preserves precise LT values', (
    tester,
  ) async {
    configureApplicationTestSurface(tester, const Size(1200, 800));
    var harness = (await tester.runAsync(() async {
      final value = await ApplicationTestHarness.create(setupCompleted: true);
      await value.bundle.controller.updateDocumentDurably((document) {
        final extensions = Map<String, Object?>.of(document.extensions);
        extensions[firstRunSetupExtensionKey] = <String, Object?>{
          firstRunSetupCompletedKey: true,
          firstRunSetupSchemaVersionKey: FirstRunSetupSchema.currentVersion,
          firstRunSetupCompletedBetaVersionsKey: <String, Object?>{
            '0.1.0-beta.5': FirstRunSetupSchema.currentVersion,
          },
        };
        return document.copyWith(
          afkWeightProfile: document.afkWeightProfile.copyWith(
            maximumWeightLt: 50.125,
            currentCarriedWeightLt: 1.234,
            safetyBufferLt: 25.000000123,
          ),
          extensions: extensions,
        );
      });
      await value.disposeControllerOnly();
      return value;
    }))!;
    harness = harness.rebindControllerInCurrentZone();
    final original =
        harness.bundle.controller.documentSnapshot.afkWeightProfile;

    await tester.pumpWidget(
      BdoCraftPlannerApp(applicationFuture: Future.value(harness.bundle)),
    );
    await tester.pumpAndSettle();
    expect(find.byType(FirstRunSetupView), findsNothing);
    expect(find.byType(PlannerView), findsOneWidget);

    final saved = harness.bundle.controller.documentSnapshot.afkWeightProfile;
    expect(identical(saved, original), isTrue);
    expect(saved.maximumWeightLt, 50.125);
    expect(saved.currentCarriedWeightLt, 1.234);
    expect(saved.safetyBufferLt, 25.000000123);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(harness.dispose);
  });

  testWidgets('schema one profiles see only AFK Load and keep prior settings', (
    tester,
  ) async {
    configureApplicationTestSurface(tester, const Size(1200, 800));
    var harness = (await tester.runAsync(() async {
      final value = await ApplicationTestHarness.create(setupCompleted: true);
      await value.bundle.controller.updateDocumentDurably((document) {
        final extensions = Map<String, Object?>.of(document.extensions)
          ..[firstRunSetupExtensionKey] = <String, Object?>{
            firstRunSetupCompletedKey: true,
            firstRunSetupSchemaVersionKey: 1,
            'futureSetupField': 'kept',
          };
        return document.copyWith(
          alchemy: document.alchemy.copyWith(
            alchemyMastery: 1937,
            compatibility: document.alchemy.compatibility.copyWith(
              alchemyYield: 3.14159,
            ),
          ),
          cooking: document.cooking.copyWith(cookingMastery: 842),
          processing: document.processing.copyWith(
            processingMastery: 1264,
            useMassProcessing: true,
          ),
          marketTax: document.marketTax.copyWith(
            enabled: false,
            valuePack: false,
            merchantRing: true,
            familyFameBonus: .0125,
          ),
          afkWeightProfile: document.afkWeightProfile.copyWith(
            maximumWeightLt: 1750,
            currentCarriedWeightLt: 80,
            safetyBufferLt: 25,
            featheryStepsLevel: 2,
            extensions: const <String, Object?>{'futureAfkField': 'kept'},
          ),
          extensions: extensions,
        );
      });
      await value.disposeControllerOnly();
      return value;
    }))!;
    harness = harness.rebindControllerInCurrentZone();

    await tester.pumpWidget(
      BdoCraftPlannerApp(
        applicationFuture: Future.value(harness.bundle),
        repeatFullSetupEveryApplicationVersion: false,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(FirstRunSetupView), findsOneWidget);
    expect(find.text('Step 1 of 1'), findsOneWidget);
    expect(find.text('AFK Load'), findsOneWidget);
    expect(find.text('Mastery'), findsNothing);
    expect(find.text('Market sales'), findsNothing);
    _expectFieldValue(tester, 'setup-maximum-weight-lt', '1750');
    _expectFieldValue(tester, 'setup-current-carried-weight-lt', '80');
    _expectFieldValue(tester, 'setup-safety-buffer-lt', '25');
    expect(find.text('II · 110%'), findsOneWidget);

    await _enterField(tester, 'setup-maximum-weight-lt', '2100.5');
    await tester.tap(
      find.byKey(const ValueKey<String>('first-run-setup-finish')),
    );
    await tester.pumpAndSettle();

    final document = harness.bundle.controller.documentSnapshot;
    expect(document.alchemy.alchemyMastery, 1937);
    expect(document.alchemy.compatibility.alchemyYield, 3.14159);
    expect(document.cooking.cookingMastery, 842);
    expect(document.processing.processingMastery, 1264);
    expect(document.processing.useMassProcessing, isTrue);
    expect(document.marketTax.enabled, isFalse);
    expect(document.marketTax.valuePack, isFalse);
    expect(document.marketTax.merchantRing, isTrue);
    expect(document.marketTax.familyFameBonus, .0125);
    expect(document.afkWeightProfile.maximumWeightLt, 2100.5);
    expect(document.afkWeightProfile.currentCarriedWeightLt, 80);
    expect(document.afkWeightProfile.safetyBufferLt, 25);
    expect(document.afkWeightProfile.featheryStepsLevel, 2);
    expect(document.afkWeightProfile.extensions['futureAfkField'], 'kept');
    final metadata = document.extensions[firstRunSetupExtensionKey] as Map;
    expect(metadata[firstRunSetupSchemaVersionKey], 2);
    expect(metadata['futureSetupField'], 'kept');

    await tester.tap(
      find.byKey(const ValueKey<String>('first-run-setup-location-okay')),
    );
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(harness.dispose);
  });

  testWidgets('location notice waits for the durable setup save', (
    tester,
  ) async {
    configureApplicationTestSurface(tester, const Size(1200, 800));
    var harness = (await tester.runAsync(
      () => ApplicationTestHarness.create(setupCompleted: false),
    ))!;
    await tester.runAsync(harness.disposeControllerOnly);
    final saveGate = Completer<void>();
    harness = harness.rebindControllerInCurrentZone(
      saveStateFactory: (_) => (state) async {
        await saveGate.future;
        return state;
      },
    );

    await tester.pumpWidget(
      BdoCraftPlannerApp(applicationFuture: Future.value(harness.bundle)),
    );
    await tester.pumpAndSettle();
    await _goToMarketAndSave(tester);
    await tester.pump();

    expect(
      find.byKey(const ValueKey<String>('first-run-setup-location-notice')),
      findsNothing,
    );
    expect(find.byType(FirstRunSetupView), findsOneWidget);

    saveGate.complete();
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('first-run-setup-location-notice')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('first-run-setup-location-okay')),
    );
    await tester.pumpAndSettle();

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(harness.dispose);
  });

  testWidgets('failed setup save never opens the location notice', (
    tester,
  ) async {
    configureApplicationTestSurface(tester, const Size(1200, 800));
    var harness = (await tester.runAsync(
      () => ApplicationTestHarness.create(setupCompleted: false),
    ))!;
    await tester.runAsync(harness.disposeControllerOnly);
    harness = harness.rebindControllerInCurrentZone(
      saveStateFactory: (_) =>
          (state) async => throw StateError('blocked'),
    );

    await tester.pumpWidget(
      BdoCraftPlannerApp(applicationFuture: Future.value(harness.bundle)),
    );
    await tester.pumpAndSettle();
    await _goToMarketAndSave(tester);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('first-run-setup-error')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('first-run-setup-location-notice')),
      findsNothing,
    );
    expect(find.byType(FirstRunSetupView), findsOneWidget);
    expect(find.byType(PlannerView), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(harness.dispose);
  });
}

Future<void> _enterMastery(WidgetTester tester, String key, String value) =>
    _enterField(tester, key, value);

Future<void> _enterField(WidgetTester tester, String key, String value) =>
    tester.enterText(
      find.descendant(
        of: find.byKey(ValueKey<String>(key)),
        matching: find.byType(EditableText),
      ),
      value,
    );

void _expectMasteryValue(WidgetTester tester, String key, String value) {
  _expectFieldValue(tester, key, value);
}

void _expectFieldValue(WidgetTester tester, String key, String value) {
  final field = tester.widget<EditableText>(
    find.descendant(
      of: find.byKey(ValueKey<String>(key)),
      matching: find.byType(EditableText),
    ),
  );
  expect(field.controller.text, value);
}

void _expectSmallerThanSetupHeading(WidgetTester tester, String text) {
  final setupHeading = tester.widget<Text>(find.text('Set up your planner'));
  final groupHeading = tester.widget<Text>(find.text(text));
  expect(groupHeading.style?.fontSize, lessThan(setupHeading.style!.fontSize!));
}

Future<void> _goToMarketAndSave(WidgetTester tester) async {
  await tester.ensureVisible(
    find.byKey(const ValueKey<String>('first-run-setup-next')),
  );
  await tester.tap(find.byKey(const ValueKey<String>('first-run-setup-next')));
  await tester.pumpAndSettle();
  await tester.ensureVisible(
    find.byKey(const ValueKey<String>('first-run-setup-next')),
  );
  await tester.tap(find.byKey(const ValueKey<String>('first-run-setup-next')));
  await tester.pumpAndSettle();
  await tester.ensureVisible(
    find.byKey(const ValueKey<String>('first-run-setup-finish')),
  );
  await tester.tap(
    find.byKey(const ValueKey<String>('first-run-setup-finish')),
  );
}
