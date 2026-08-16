import 'dart:convert';
import 'dart:io';

import 'package:bdo_craft_planner_flutter/app/state/planner_application_controller.dart';
import 'package:bdo_craft_planner_flutter/data/portable/portable_v4_codec.dart';
import 'package:bdo_craft_planner_flutter/domain/models/catalog_models.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/domain/state/planner_state.dart';
import 'package:bdo_craft_planner_flutter/domain/state/planner_state_json_codec.dart';
import 'package:bdo_craft_planner_flutter/domain/state/state_copy.dart';
import 'package:bdo_craft_planner_flutter/features/data/data_view.dart';
import 'package:bdo_craft_planner_flutter/visual/visual.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('editor settings unlock only after seven taps inside five seconds', () {
    final session = DataSessionController();
    addTearDown(session.dispose);
    final started = DateTime.utc(2026, 8, 12, 12);

    for (var tap = 1; tap < DataSessionController.editorUnlockTapCount; tap++) {
      expect(
        session.registerEditorUnlockTap(
          at: started.add(Duration(milliseconds: tap * 500)),
        ),
        DataSessionController.editorUnlockTapCount - tap,
      );
      expect(session.editorSettingsUnlocked, isFalse);
    }
    expect(
      session.registerEditorUnlockTap(
        at: started.add(const Duration(milliseconds: 3500)),
      ),
      0,
    );
    expect(session.editorSettingsUnlocked, isTrue);
  });

  test('editor unlock tap count resets after the five-second window', () {
    final session = DataSessionController();
    addTearDown(session.dispose);
    final started = DateTime.utc(2026, 8, 12, 12);

    for (var tap = 0; tap < 6; tap++) {
      session.registerEditorUnlockTap(
        at: started.add(Duration(milliseconds: tap * 500)),
      );
    }
    expect(
      session.registerEditorUnlockTap(
        at: started.add(const Duration(seconds: 8)),
      ),
      6,
    );
    expect(session.editorSettingsUnlocked, isFalse);
  });

  testWidgets('wide Craft Profile layout uses balanced two-column groups', (
    tester,
  ) async {
    final controller = _controller();
    await _pump(
      tester,
      controller,
      size: const Size(1425, 940),
      showDeveloperBackup: false,
    );

    expect(find.text('Mastery & Output'), findsOneWidget);
    expect(find.text('Market Sales'), findsOneWidget);
    expect(find.text('AFK Load'), findsOneWidget);
    expect(find.text('Portable Sharing'), findsNothing);
    expect(find.text('Developer Backup'), findsNothing);
    expect(find.text('Editor Settings'), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('data-editor-unlock-build')),
      findsOneWidget,
    );
    await _unlockEditorSettings(tester);
    expect(find.text('Editor Settings'), findsOneWidget);
    expect(find.text('Developer Backup'), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('data-portable-sharing-card')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey<String>('D04')), findsNothing);
    expect(find.text('PROCESSING RESULT'), findsNothing);

    final craft = tester.getRect(
      find.byKey(const ValueKey<String>('data-craft-output-card')),
    );
    final marketSale = tester.getRect(
      find.byKey(const ValueKey<String>('data-market-sale-card')),
    );
    final editor = tester.getRect(
      find.byKey(const ValueKey<String>('data-editor-settings-card')),
    );
    final afkLoad = tester.getRect(
      find.byKey(const ValueKey<String>('data-afk-load-card')),
    );
    expect(craft.width, closeTo(marketSale.width, 1));
    expect(marketSale.left - craft.right, 18);
    expect(editor.left, craft.left);
    expect(editor.width, craft.width);
    expect(afkLoad.left, craft.left);
    expect(afkLoad.width, lessThanOrEqualTo(540));
    expect(afkLoad.top - craft.bottom, 14);
    expect(editor.top - afkLoad.bottom, 14);

    await controller.dispose();
  });

  testWidgets(
    'Personal data explains local ownership and browses before move confirmation',
    (tester) async {
      const channel = MethodChannel('com.bdocraftplanner.flutter/window');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'pickDirectory') return r'D:\Planner data';
        return null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final controller = _controller();
      String? movedTo;
      await _pump(
        tester,
        controller,
        size: const Size(1200, 752),
        personalDataPath: r'C:\Current planner data',
        onMovePersonalData: (path) async => movedTo = path,
      );

      final card = find.byKey(
        const ValueKey<String>('data-personal-data-card'),
      );
      await tester.ensureVisible(card);
      await tester.pumpAndSettle();
      expect(card, findsOneWidget);
      expect(
        find.textContaining('They are not included in the installer.'),
        findsOneWidget,
      );
      final pathField = find.descendant(
        of: find.byKey(const ValueKey<String>('data-personal-data-path')),
        matching: find.byType(TextField),
      );
      expect(
        tester.widget<TextField>(pathField).controller?.text,
        r'C:\Current planner data',
      );

      await tester.tap(
        find.byKey(const ValueKey<String>('data-personal-data-browse')),
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(pathField).controller?.text,
        r'D:\Planner data',
      );

      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'pickDirectory') {
          throw PlatformException(
            code: 'folder_picker_unavailable',
            message: 'Folder picker unavailable.',
          );
        }
        return null;
      });
      await tester.tap(
        find.byKey(const ValueKey<String>('data-personal-data-browse')),
      );
      await tester.pump();
      expect(find.text('Folder picker unavailable.'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey<String>('data-personal-data-move')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Move personal data?'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(Dialog),
          matching: find.text(r'D:\Planner data'),
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Move and restart').last);
      await tester.pumpAndSettle();

      expect(movedTo, r'D:\Planner data');
      await controller.dispose();
    },
  );

  for (final variant in <(String, ThemeSpec)>[
    ('Standard', RetainedThemeRegistry.standard),
    ('Sakura Night Garden', RetainedThemeRegistry.sakuraNightGarden),
    ('Illuminated Ledger', RetainedThemeRegistry.illuminatedLedger),
  ]) {
    testWidgets(
      '${variant.$1} Data option controls keep Avalonia intrinsic geometry',
      (tester) async {
        final controller = _controller();

        // These are the Data viewport sizes after the protected shell removes
        // its sidebar and 40px native title bar at 1500x940 and 1200x752.
        for (final viewport in <(double, double)>[(1227, 900), (927, 712)]) {
          final viewportWidth = viewport.$1;
          final viewportHeight = viewport.$2;
          await _pump(
            tester,
            controller,
            size: Size(viewportWidth, viewportHeight),
            spec: variant.$2,
            showDeveloperBackup: false,
          );
          await _unlockEditorSettings(tester);

          final craft = tester.getRect(
            find.byKey(const ValueKey<String>('data-craft-output-card')),
          );
          final editor = tester.getRect(
            find.byKey(const ValueKey<String>('data-editor-settings-card')),
          );
          final marketSale = tester.getRect(
            find.byKey(const ValueKey<String>('data-market-sale-card')),
          );
          final massProcessing = tester.getRect(
            find.byKey(const ValueKey<String>('D05')),
          );
          final deleteTools = tester.getRect(
            find.byKey(const ValueKey<String>('D13')),
          );
          final restoreHidden = tester.getRect(
            find.byKey(const ValueKey<String>('D14')),
          );
          final cardInset = variant.$2.usesDenseSplitLayout ? 13.0 : 15.0;

          expect(massProcessing.left - craft.left, closeTo(cardInset, 1));
          expect(massProcessing.width, lessThan(craft.width - cardInset * 2));
          expect(deleteTools.left - editor.left, closeTo(cardInset, 1));
          expect(
            deleteTools.width,
            lessThanOrEqualTo(editor.width - cardInset * 2),
          );
          expect(editor.right - restoreHidden.right, closeTo(cardInset, 1));
          expect(
            restoreHidden.center.dy,
            closeTo(
              tester
                  .getRect(
                    find.byKey(const ValueKey<String>('data-hidden-summary')),
                  )
                  .center
                  .dy,
              1,
            ),
          );

          final valuePack = tester.getRect(
            find.byKey(const ValueKey<String>('D16')),
          );
          final ring = tester.getRect(
            find.byKey(const ValueKey<String>('D18')),
          );
          final familyFame = tester.getRect(
            find.byKey(const ValueKey<String>('D17')),
          );
          final netReturn = tester.getRect(
            find.byKey(const ValueKey<String>('data-market-net-summary')),
          );
          expect(
            ring.top,
            greaterThan(valuePack.top),
            reason:
                '${variant.$1} market choices must read top-to-bottom at '
                '$viewportWidth px',
          );
          expect(familyFame.top, greaterThan(ring.top));
          expect(netReturn.height, greaterThan(familyFame.height));
          expect(netReturn.left, greaterThan(familyFame.right));
          expect(
            marketSale.height,
            lessThanOrEqualTo(300),
            reason:
                '${variant.$1} market settings must stay compact and readable '
                'at $viewportWidth px',
          );
          if (viewportWidth == 927) {
            expect(editor.left, closeTo(craft.left, 1));
            expect(editor.top, greaterThan(marketSale.bottom));
          }
          await tester.pumpWidget(const SizedBox.shrink());
        }

        await controller.dispose();
      },
    );
  }

  for (final variant in <(String, ThemeSpec)>[
    ('Standard', RetainedThemeRegistry.standard),
    ('Sakura Night Garden', RetainedThemeRegistry.sakuraNightGarden),
    ('Illuminated Ledger', RetainedThemeRegistry.illuminatedLedger),
  ]) {
    testWidgets(
      '${variant.$1} Craft Output fields fill and align in wide and compact layouts',
      (tester) async {
        final controller = _controller();

        for (final viewportWidth in <double>[1227, 700]) {
          await _pump(
            tester,
            controller,
            size: Size(viewportWidth, 752),
            spec: variant.$2,
          );
          _expectCraftOutputFieldGeometry(tester);
        }

        await controller.dispose();
      },
    );
  }

  testWidgets('developer backup remains hidden after the build unlock', (
    tester,
  ) async {
    for (final spec in <ThemeSpec>[
      RetainedThemeRegistry.standard,
      RetainedThemeRegistry.sakuraNightGarden,
      RetainedThemeRegistry.illuminatedLedger,
    ]) {
      for (final viewportWidth in <double>[1227, 927]) {
        final controller = _controller();
        await _pump(
          tester,
          controller,
          size: Size(viewportWidth, 752),
          spec: spec,
          showDeveloperBackup: false,
        );
        expect(find.text('Developer Backup'), findsNothing);
        await _unlockEditorSettings(tester);
        expect(find.text('Developer Backup'), findsNothing);
        expect(
          find.byKey(const ValueKey<String>('data-portable-sharing-card')),
          findsNothing,
        );
        await tester.pumpWidget(const SizedBox.shrink());
        await controller.dispose();
      }
    }
  });

  testWidgets('App build unlock gives no countdown or partial-tap hint', (
    tester,
  ) async {
    final controller = _controller();
    await _pump(tester, controller, showDeveloperBackup: false);
    final build = find.byKey(
      const ValueKey<String>('data-editor-unlock-build'),
    );

    for (
      var tap = 0;
      tap < DataSessionController.editorUnlockTapCount - 1;
      tap++
    ) {
      await tester.tap(build);
      await tester.pump();
    }

    expect(find.textContaining('more tap'), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('data-operation-status')),
      findsNothing,
    );
    expect(find.text('Editor Settings'), findsNothing);
    await controller.dispose();
  });

  testWidgets('App build stays pinned to the bottom of the profile window', (
    tester,
  ) async {
    final controller = _controller();
    await _pump(tester, controller, size: const Size(1200, 752));

    final build = tester.getRect(
      find.byKey(const ValueKey<String>('data-editor-unlock-build')),
    );
    expect(
      tester.view.physicalSize.height - build.bottom,
      lessThanOrEqualTo(20),
    );

    await controller.dispose();
  });

  testWidgets('developer backup needs an explicit maintenance surface flag', (
    tester,
  ) async {
    final controller = _controller();
    await _pump(tester, controller, showDeveloperBackup: true);
    expect(find.text('Developer Backup'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('data-portable-sharing-card')),
      findsOneWidget,
    );
    expect(find.text('Editor Settings'), findsNothing);
    await controller.dispose();
  });

  testWidgets('test update stays behind the session-only App build unlock', (
    tester,
  ) async {
    final controller = _controller();
    var testUpdateCalls = 0;
    await _pump(tester, controller, onTestUpdate: () => testUpdateCalls += 1);

    expect(
      find.byKey(const ValueKey<String>('data-test-update')),
      findsNothing,
    );
    await _unlockEditorSettings(tester);
    final testUpdate = find.byKey(const ValueKey<String>('data-test-update'));
    expect(testUpdate, findsOneWidget);
    await tester.ensureVisible(testUpdate);
    await tester.tap(testUpdate);
    await tester.pump();
    expect(testUpdateCalls, 1);

    await tester.pumpWidget(const SizedBox.shrink());
    await controller.dispose();
  });

  testWidgets('market-sale settings are compact, live, and persisted', (
    tester,
  ) async {
    PlannerState? saved;
    final controller = _controller(
      saveState: (state) {
        saved = state;
        return SynchronousFuture(state);
      },
    );
    await _pump(tester, controller, size: const Size(1227, 752));

    final marketCard = find.byKey(
      const ValueKey<String>('data-market-sale-card'),
    );
    expect(find.byKey(const ValueKey<String>('D15')), findsNothing);
    expect(
      find.descendant(of: marketCard, matching: find.byType(AppToggle)),
      findsNWidgets(2),
    );
    expect(
      find.byKey(const ValueKey<String>('market-bonus:valuePack')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('market-bonus:richMerchantsRing')),
      findsOneWidget,
    );
    expect(find.text('65%'), findsOneWidget);
    expect(find.text('35% deducted'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('D16')));
    await tester.pumpAndSettle();
    expect(controller.documentSnapshot.marketTax.valuePack, isTrue);
    expect(find.text('84,5%'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('D17')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('7,000+ · +1.5%'));
    await tester.pumpAndSettle();
    expect(controller.documentSnapshot.marketTax.familyFameBonus, .015);
    expect(find.text('85,475%'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('D18')));
    await tester.pumpAndSettle();
    expect(controller.documentSnapshot.marketTax.merchantRing, isTrue);
    expect(find.text('88,725%'), findsOneWidget);
    expect(find.text('11,275% deducted'), findsOneWidget);

    await controller.flush();
    expect(find.text('88,725%'), findsOneWidget);
    expect(saved?.marketTax.enabled, isTrue);
    expect(saved?.marketTax.valuePack, isTrue);
    expect(saved?.marketTax.merchantRing, isTrue);
    expect(saved?.marketTax.familyFameBonus, .015);
    expect(saved?.marketTax.extensions, const <String, Object?>{
      'futureTaxField': 42,
    });

    await controller.dispose();
  });

  testWidgets(
    'default Settings export includes the configured sale-tax settings',
    (tester) async {
      const fileDialogChannel = MethodChannel(
        'com.bdocraftplanner.flutter/window',
      );
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(fileDialogChannel, (_) async => null);
      addTearDown(
        () => messenger.setMockMethodCallHandler(fileDialogChannel, null),
      );
      final controller = _controller();
      controller.updateDocument(
        (document) => document.copyWith(
          marketTax: MarketTax(
            valuePack: true,
            merchantRing: true,
            familyFameBonus: .015,
            extensions: document.marketTax.extensions,
          ),
        ),
        immediate: true,
      );
      await _pump(tester, controller, showDeveloperBackup: true);

      await _invokeAsyncAppButton(
        tester,
        find.byKey(const ValueKey<String>('D07')),
      );
      await tester.pump();

      await _scrollDataUntilVisible(
        tester,
        find.byKey(const ValueKey<String>('D09')),
      );
      final editor = find.descendant(
        of: find.byKey(const ValueKey<String>('D09')),
        matching: find.byType(TextField),
      );
      final source = tester.widget<TextField>(editor).controller!.text;
      final decoded = jsonDecode(source) as Map<String, Object?>;
      final included = decoded['included']! as Map<String, Object?>;
      final data = decoded['data']! as Map<String, Object?>;
      expect(included['settings'], isTrue);
      expect(included['market'], isFalse);
      expect(data['marketTax'], <String, Object?>{
        'enabled': true,
        'valuePack': true,
        'merchantRing': true,
        'familyFameBonus': .015,
      });

      await controller.dispose();
    },
  );

  testWidgets('D12 Portable EXE reports the retained export guidance', (
    tester,
  ) async {
    final controller = _controller();
    await _pump(tester, controller, showDeveloperBackup: true);
    const stateCodec = PlannerStateJsonCodec();
    final before = stateCodec.encode(controller.documentSnapshot);

    await _revealJsonEditor(tester);
    const sessionJson = '{"session":"portable-notice"}';
    await _scrollDataUntilVisible(
      tester,
      find.byKey(const ValueKey<String>('D09')),
    );
    final editor = find.descendant(
      of: find.byKey(const ValueKey<String>('D09')),
      matching: find.byType(TextField),
    );
    await tester.enterText(editor, sessionJson);

    final portableExe = find.byKey(const ValueKey<String>('D12'));
    await tester.ensureVisible(portableExe);
    await tester.pumpAndSettle();
    await tester.tap(portableExe);
    await tester.pump();

    const notice =
        'Portable EXE packaging is unavailable in this build. '
        'Use Export JSON for selective sharing.';
    expect(find.text(notice), findsOneWidget);
    expect(tester.widget<TextField>(editor).controller?.text, sessionJson);
    expect(stateCodec.encode(controller.documentSnapshot), before);
    await controller.dispose();
  });

  testWidgets('invalid JSON reports a visible error without changing state', (
    tester,
  ) async {
    final controller = _controller();
    await _pump(tester, controller, showDeveloperBackup: true);
    const stateCodec = PlannerStateJsonCodec();
    final before = stateCodec.encode(controller.documentSnapshot);
    await _revealJsonEditor(tester);
    final editor = find.descendant(
      of: find.byKey(const ValueKey<String>('D09')),
      matching: find.byType(TextField),
    );
    await tester.enterText(editor, '{');

    final import = find.byKey(const ValueKey<String>('D10'));
    await tester.ensureVisible(import);
    await tester.pumpAndSettle();
    await tester.tap(import);
    await tester.pumpAndSettle();

    final status = find.byKey(const ValueKey<String>('data-operation-status'));
    await _scrollDataUntilVisible(tester, status);
    expect(
      find.textContaining('Import failed; no state changed'),
      findsOneWidget,
    );
    expect(tester.widget<TextField>(editor).controller?.text, '{');
    expect(stateCodec.encode(controller.documentSnapshot), before);
    await controller.dispose();
  });

  testWidgets('mastery, mass processing, and JSON session actions are wired', (
    tester,
  ) async {
    final controller = _controller();
    await _pump(tester, controller, showDeveloperBackup: true);

    await tester.enterText(
      find.descendant(
        of: find.byKey(const ValueKey<String>('D01')),
        matching: find.byType(TextField),
      ),
      '4000',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(controller.documentSnapshot.alchemy.alchemyMastery, 3000);

    await tester.enterText(
      find.descendant(
        of: find.byKey(const ValueKey<String>('D01')),
        matching: find.byType(TextField),
      ),
      '1.900',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(controller.documentSnapshot.alchemy.alchemyMastery, 1900);

    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey<String>('D02')),
        matching: find.byType(TextField),
      ),
    );
    await tester.pump();
    final repeatedMastery = find.descendant(
      of: find.byKey(const ValueKey<String>('D01')),
      matching: find.byType(TextField),
    );
    await tester.enterText(repeatedMastery, '888');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(controller.documentSnapshot.alchemy.alchemyMastery, 888);

    await tester.tap(find.byKey(const ValueKey<String>('D05')));
    await tester.pump();
    expect(controller.documentSnapshot.processing.useMassProcessing, isTrue);

    await _revealJsonEditor(tester);
    expect(find.byKey(const ValueKey<String>('D09')), findsOneWidget);
    await controller.dispose();
  });

  testWidgets('AFK Load profile stays compact and saves all character inputs', (
    tester,
  ) async {
    final controller = _controller();
    await _pump(tester, controller);

    final toggle = find.byKey(const ValueKey<String>('data-afk-load-toggle'));
    expect(toggle, findsOneWidget);
    expect(find.text('Set your character weight once'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('data-afk-maximum-weight')),
      findsNothing,
    );

    await tester.ensureVisible(toggle);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(find.text('LT TO KEEP FREE'), findsOneWidget);
    expect(find.text('LEAVE UNUSED'), findsNothing);

    Future<void> commit(String key, String value) async {
      final field = find.descendant(
        of: find.byKey(ValueKey<String>(key)),
        matching: find.byType(TextField),
      );
      await tester.enterText(field, value);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
    }

    await commit('data-afk-maximum-weight', '1600');
    await commit('data-afk-current-weight', '125');
    await commit('data-afk-safety-buffer', '25');
    final feathery = tester.widget<AppSelect<int>>(
      find.byKey(const ValueKey<String>('data-afk-feathery-steps')),
    );
    feathery.onChanged!(5);
    await tester.pumpAndSettle();

    final profile = controller.documentSnapshot.afkWeightProfile;
    expect(profile.maximumWeightLt, 1600);
    expect(profile.currentCarriedWeightLt, 125);
    expect(profile.safetyBufferLt, 25);
    expect(profile.featheryStepsLevel, 5);
    expect(profile.penaltyThresholdLt, 2000);
    expect(profile.safeLimitLt, 1850);
    expect(find.text('1.850 LT'), findsOneWidget);
    expect(find.text('1.975 LT'), findsOneWidget);
    expect(find.text('AVAILABLE FOR MATERIALS'), findsOneWidget);
    expect(find.text('SAFE STOP'), findsOneWidget);

    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('data-afk-maximum-weight')),
      findsNothing,
    );
    expect(find.textContaining('1.850 LT available'), findsOneWidget);
    await controller.dispose();
  });

  testWidgets('delete-tools option rebuilds from the global notifier', (
    tester,
  ) async {
    final controller = _controller();
    await _pump(tester, controller);

    expect(find.byKey(const ValueKey<String>('D13')), findsNothing);
    expect(controller.documentSnapshot.showDeleteTools, isFalse);
    await _unlockEditorSettings(tester);

    final option = find.byKey(const ValueKey<String>('D13'));
    final optionButton = find.descendant(
      of: option,
      matching: find.byType(AppButton),
    );
    expect(tester.widget<AppButton>(optionButton).selected, isFalse);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey<String>('D14')),
        matching: _glyph('reset'),
      ),
      findsOneWidget,
    );

    await tester.tap(option);
    await tester.pump();

    expect(controller.documentSnapshot.showDeleteTools, isTrue);
    expect(tester.widget<AppButton>(optionButton).selected, isTrue);
    expect(
      find.descendant(of: option, matching: _glyph('check')),
      findsOneWidget,
    );
    await controller.dispose();
  });

  testWidgets('D14 restores a legacy tombstone even without a hidden marker', (
    tester,
  ) async {
    final controller = _controller();
    controller.updateDocument(
      (document) => document.copyWith(
        alchemy: document.alchemy.copyWith(
          hiddenItems: const <String>[],
          recipeEdits: const <String, RecipeState?>{'Recipe': null},
        ),
      ),
      immediate: true,
    );
    await _pump(tester, controller);
    await _unlockEditorSettings(tester);

    expect(find.text('1 hidden · Alchemy'), findsOneWidget);
    await _invokeAsyncAppButton(
      tester,
      find.byKey(const ValueKey<String>('D14')),
    );
    await tester.pumpAndSettle();

    expect(controller.documentSnapshot.alchemy.hiddenItems, isEmpty);
    expect(
      controller.documentSnapshot.alchemy.recipeEdits,
      isNot(contains('Recipe')),
    );
    expect(find.text('0 hidden · Alchemy'), findsOneWidget);
    await controller.dispose();
  });

  testWidgets('shared Data session survives destruction and remount', (
    tester,
  ) async {
    final controller = _controller();
    final session = DataSessionController();
    addTearDown(session.dispose);
    await _pump(
      tester,
      controller,
      sessionController: session,
      showDeveloperBackup: true,
    );

    final importAction = _invokeAsyncAppButton(
      tester,
      find.byKey(const ValueKey<String>('D10')),
    );
    await importAction;
    await tester.pump();
    await _scrollDataToEnd(tester);
    expect(find.byKey(const ValueKey<String>('D09')), findsOneWidget);
    await _scrollDataUntilVisible(
      tester,
      find.textContaining('Paste portable JSON into the editor'),
    );
    expect(
      find.textContaining('Paste portable JSON into the editor'),
      findsOneWidget,
    );
    const sentinel = '{"session":"survives"}';
    await tester.enterText(
      find.descendant(
        of: find.byKey(const ValueKey<String>('D09')),
        matching: find.byType(TextField),
      ),
      sentinel,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await _pump(
      tester,
      controller,
      sessionController: session,
      showDeveloperBackup: true,
    );

    await _scrollDataToEnd(tester);
    await _scrollDataUntilVisible(
      tester,
      find.byKey(const ValueKey<String>('D09')),
    );
    expect(find.byKey(const ValueKey<String>('D09')), findsOneWidget);
    expect(
      tester
          .widget<TextField>(
            find.descendant(
              of: find.byKey(const ValueKey<String>('D09')),
              matching: find.byType(TextField),
            ),
          )
          .controller
          ?.text,
      sentinel,
    );
    await _scrollDataUntilVisible(
      tester,
      find.textContaining('Paste portable JSON into the editor'),
    );
    expect(
      find.textContaining('Paste portable JSON into the editor'),
      findsOneWidget,
    );
    await controller.dispose();
  });

  testWidgets('D10 rolls back memory and reports a durable write failure', (
    tester,
  ) async {
    final controller = _controller(
      saveState: (_) => throw const FileSystemException('disk full'),
    );
    await _pump(tester, controller, showDeveloperBackup: true);
    await _revealJsonEditor(tester);
    final imported = controller.documentSnapshot.copyWith(
      alchemy: controller.documentSnapshot.alchemy.copyWith(want: 777),
    );
    final source = const PortableV4Codec().export(
      imported,
      scopes: const PortableScopes.all(),
    );
    await tester.enterText(
      find.descendant(
        of: find.byKey(const ValueKey<String>('D09')),
        matching: find.byType(TextField),
      ),
      source,
    );
    final importAction = _invokeAsyncAppButton(
      tester,
      find.byKey(const ValueKey<String>('D10')),
    );
    await importAction;
    await tester.pump();
    await _scrollDataUntilVisible(
      tester,
      find.textContaining('Import failed; no state changed'),
    );

    expect(controller.documentSnapshot.alchemy.want, 100);
    expect(
      find.textContaining('Import failed; no state changed'),
      findsOneWidget,
    );
    expect(find.textContaining('disk full'), findsOneWidget);
    await controller.dispose();
  });

  testWidgets('D10 applies valid import immediately and silently', (
    tester,
  ) async {
    PlannerState? saved;
    final controller = _controller(
      saveState: (state) {
        saved = state;
        return SynchronousFuture(state);
      },
    );
    await _pump(tester, controller, showDeveloperBackup: true);

    final portableExe = find.byKey(const ValueKey<String>('D12'));
    await _scrollDataUntilVisible(tester, portableExe);
    await tester.tap(portableExe);
    await tester.pump();
    await _scrollDataUntilVisible(
      tester,
      find.byKey(const ValueKey<String>('data-operation-status')),
    );
    expect(
      find.byKey(const ValueKey<String>('data-operation-status')),
      findsOneWidget,
    );

    await _revealJsonEditor(tester);
    final imported = controller.documentSnapshot.copyWith(
      alchemy: controller.documentSnapshot.alchemy.copyWith(
        want: 777,
        favoriteRecipes: const <String>['Recipe'],
      ),
      showDeleteTools: true,
    );
    final source = const PortableV4Codec().export(
      imported,
      scopes: const PortableScopes.all(),
    );
    await tester.enterText(
      find.descendant(
        of: find.byKey(const ValueKey<String>('D09')),
        matching: find.byType(TextField),
      ),
      source,
    );
    expect(
      tester
          .widget<TextField>(
            find.descendant(
              of: find.byKey(const ValueKey<String>('D09')),
              matching: find.byType(TextField),
            ),
          )
          .controller
          ?.text,
      source,
    );

    final importAction = _invokeAsyncAppButton(
      tester,
      find.byKey(const ValueKey<String>('D10')),
    );
    await importAction;
    await tester.pump();

    expect(controller.documentSnapshot.alchemy.want, 777);
    expect(saved?.alchemy.want, 777);
    expect(controller.documentSnapshot.showDeleteTools, isFalse);
    expect(saved?.showDeleteTools, isFalse);
    expect(find.byType(Dialog), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('D10:preview-source')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey<String>('D10:undo')), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('data-operation-status')),
      findsNothing,
    );
    expect(find.byType(SnackBar), findsNothing);
    await controller.dispose();
  });
}

Future<void> _revealJsonEditor(WidgetTester tester) async {
  final showJson = find.byKey(const ValueKey<String>('D08'));
  await _centerDataTarget(tester, showJson);
  final button = tester.widget<AppButton>(showJson);
  expect(button.onPressed, isNotNull);
  button.onPressed!();
  await tester.pump();
  await _centerDataTarget(tester, find.byKey(const ValueKey<String>('D09')));
}

Future<void> _scrollDataUntilVisible(WidgetTester tester, Finder target) =>
    _centerDataTarget(tester, target);

Future<void> _centerDataTarget(WidgetTester tester, Finder target) async {
  await tester.scrollUntilVisible(
    target,
    300,
    scrollable: find
        .descendant(
          of: find.byKey(const ValueKey<String>('data-scroll')),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await Scrollable.ensureVisible(
    tester.element(target),
    alignment: 0.5,
    duration: Duration.zero,
  );
  await tester.pumpAndSettle();
}

Future<void> _scrollDataToEnd(WidgetTester tester) async {
  final scrollable = find
      .descendant(
        of: find.byKey(const ValueKey<String>('data-scroll')),
        matching: find.byType(Scrollable),
      )
      .first;
  await tester.fling(scrollable, const Offset(0, -1800), 2400);
  await tester.pumpAndSettle();
}

void _expectCraftOutputFieldGeometry(WidgetTester tester) {
  final craft = find.byKey(const ValueKey<String>('data-craft-output-card'));
  final craftRect = tester.getRect(craft);
  const fields = <String, String>{
    'D03': 'PROCESSING MASTERY',
    'D01': 'ALCHEMY MASTERY',
    'D02': 'COOKING MASTERY',
  };

  for (final entry in fields.entries) {
    final fieldGroup = find.byKey(ValueKey<String>(entry.key));
    final input = find.descendant(
      of: fieldGroup,
      matching: find.byType(TextField),
    );
    final decorator = find.descendant(
      of: fieldGroup,
      matching: find.byType(InputDecorator),
    );
    final label = find.descendant(
      of: fieldGroup,
      matching: find.text(entry.value),
    );
    final inputRect = tester.getRect(input);
    final decoratorRect = tester.getRect(decorator);
    final labelRect = tester.getRect(label);
    expect(
      tester.widget<TextField>(input).textAlignVertical,
      TextAlignVertical.center,
    );

    expect(
      inputRect.left,
      closeTo(labelRect.left, .01),
      reason: '${entry.value} input starts directly under its header',
    );
    expect(inputRect.left, greaterThan(craftRect.left));
    expect(inputRect.right, lessThan(craftRect.right));
    expect(inputRect.width, greaterThanOrEqualTo(150));
    expect(
      inputRect.height,
      greaterThanOrEqualTo(42),
      reason: '${entry.value} has a comfortably readable field height',
    );
    expect(
      decoratorRect.height,
      closeTo(inputRect.height, .01),
      reason: '${entry.value} paints across the full field host height',
    );
  }
}

Future<void> _invokeAsyncAppButton(WidgetTester tester, Finder finder) {
  final button = tester.widget<AppButton>(finder);
  expect(button.onPressedAsync, isNotNull);
  return button.onPressedAsync!();
}

Future<void> _unlockEditorSettings(WidgetTester tester) async {
  final build = find.byKey(const ValueKey<String>('data-editor-unlock-build'));
  expect(build, findsOneWidget);
  await tester.ensureVisible(build);
  await tester.pumpAndSettle();
  for (var tap = 0; tap < DataSessionController.editorUnlockTapCount; tap++) {
    await tester.tap(build);
  }
  await tester.pumpAndSettle();
  expect(find.byKey(const ValueKey<String>('D13')), findsOneWidget);
}

Future<void> _pump(
  WidgetTester tester,
  PlannerApplicationController controller, {
  Size size = const Size(1200, 752),
  DataSessionController? sessionController,
  ThemeSpec spec = RetainedThemeRegistry.standard,
  bool showDeveloperBackup = false,
  VoidCallback? onTestUpdate,
  String personalDataPath = r'C:\Test personal data',
  Future<void> Function(String destinationPath)? onMovePersonalData,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  await tester.pumpWidget(
    MaterialApp(
      theme: spec.materialTheme(),
      home: ThemeSpecScope(
        spec: spec,
        child: Scaffold(
          body: DataView(
            controller: controller,
            sessionController: sessionController,
            showDeveloperBackup: showDeveloperBackup,
            onTestUpdate: onTestUpdate,
            personalDataPath: personalDataPath,
            onMovePersonalData: onMovePersonalData,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

PlannerApplicationController _controller({SavePlannerState? saveState}) =>
    PlannerApplicationController(
      catalog: _catalog(),
      initialState: _document(),
      saveState: saveState ?? (state) => SynchronousFuture(state),
      saveDebounce: Duration.zero,
    );

PlannerState _document() => PlannerState(
  applicationVersion: 'test',
  lastSuccessfulWriteUtc: DateTime.utc(2026),
  alchemy: _mode(CraftMode.alchemy),
  cooking: _mode(CraftMode.cooking),
  processing: _mode(CraftMode.processing),
  processingYields: const {'defaultYield': 2.5},
  marketTax: MarketTax(
    extensions: const <String, Object?>{'futureTaxField': 42},
  ),
);

ModeState _mode(CraftMode mode) => ModeState(
  target: 'Recipe',
  bonusTarget: 'Recipe',
  market: MarketState(),
  appearance: AppearanceSettings.defaultsFor(mode),
);

CatalogSnapshot _catalog() => CatalogSnapshot(
  sourceSha256: 'fixture',
  sourceByteCount: 1,
  alchemy: _catalogMode(CraftMode.alchemy),
  cooking: _catalogMode(CraftMode.cooking),
  processing: _catalogMode(CraftMode.processing),
  supportingData: const {},
  collisions: const [],
);

ModeCatalog _catalogMode(CraftMode mode) => ModeCatalog(
  mode: mode,
  items: {'Recipe': _recipe(mode)},
  iconDataUris: const {},
  defaults: const {},
  metadata: const {},
  searchAliases: const {},
);

Recipe _recipe(CraftMode mode) => Recipe(
  name: 'Recipe',
  type: mode.key,
  baseOutput: 1,
  group: null,
  method: null,
  ingredients: [
    Ingredient(
      name: 'Base',
      quantity: 1,
      options: const [],
      substituteGroup: null,
      substituteRatios: const {},
    ),
  ],
  marketId: null,
  sourceNote: null,
  vendor: null,
  location: null,
  npcPrice: 0,
  qualityBase: null,
  qualityGrade: null,
  outputMinimum: 1,
  outputMaximum: 1,
);

Finder _glyph(String name) => find.byWidgetPredicate(
  (widget) => widget is AppVectorGlyph && widget.name == name,
);
