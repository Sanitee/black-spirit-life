import 'dart:convert';
import 'dart:io';

import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/domain/state/planner_state.dart';
import 'package:bdo_craft_planner_flutter/features/gathering/gathering_workspace.dart';
import 'package:bdo_craft_planner_flutter/visual/foundations/application_theme.dart';
import 'package:bdo_craft_planner_flutter/visual/foundations/theme_registry.dart';
import 'package:bdo_gathering_companion/bdo_gathering_companion.dart';
import 'package:bdo_gathering_companion/src/gathering_companion_home.dart';
import 'package:bdo_gathering_companion/src/ui/field_guide.dart';
import 'package:bdo_gathering_companion/src/ui/theme.dart';
import 'package:bdo_gathering_companion/src/widgets/spot_map.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final themes = {
    'sakura': RetainedThemeRegistry.sakuraNightGarden,
    'ledger': RetainedThemeRegistry.illuminatedLedger,
    'forest': applicationThemeForAppearance(
      AppearanceSettings.classicDefaultsFor(CraftMode.alchemy),
    ),
  };
  test(
    'host theme maps semantic gathering colors without replacing geometry',
    () async {
      for (final entry in themes.entries) {
        final theme = entry.value;
        final palette = gatheringPaletteForTheme(theme);
        expect(palette.ink, theme.palette.text);
        expect(palette.accent, theme.palette.primary);
        expect(palette.surface, theme.palette.surface);
        expect(palette.rim, theme.palette.trimBright);
        expect(
          palette.muted,
          Color.lerp(theme.palette.textMuted, theme.palette.text, .27),
        );
        expect(palette.brightness, theme.brightness);
        expect(
          CompanionVisualPalette.decode(palette.encode())?.encode(),
          palette.encode(),
        );
        final material = companionTheme(
          visualPalette: palette,
          opacityPercent: 60,
        );
        expect(material.brightness, theme.brightness);
        expect(material.textTheme.headlineSmall?.fontFamily, 'Georgia');
        expect(material.textTheme.bodyMedium?.color, theme.palette.text);
        expect(material.extension<CompanionGlassTheme>()?.opacityPercent, 60);
        if (const String.fromEnvironment(
          'GATHERING_PALETTE_DIRECTORY',
        ).isNotEmpty) {
          final directory = Directory(
            const String.fromEnvironment('GATHERING_PALETTE_DIRECTORY'),
          );
          await directory.create(recursive: true);
          await File(
            '${directory.path}/${entry.key}.palette',
          ).writeAsString(palette.encode());
        }
      }
    },
  );

  testWidgets(
    'host theme switching retains gathering feature, finder and working state',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1563, 950);
      addTearDown(tester.view.reset);
      final directory = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('bdo-gathering-theme-'),
      ))!;
      final theme = ValueNotifier(themes['sakura']!);
      addTearDown(theme.dispose);
      await tester.runAsync(
        () => File('${directory.path}/sessions.json').writeAsString(
          jsonEncode({
            'schemaVersion': 1,
            'sessions': <Object?>[],
            'preferences': {'methodId': 'butcher', 'spotId': 'imp-cave-wolves'},
          }),
        ),
      );
      await tester.pumpWidget(
        GatheringWorkspace(dataDirectory: directory, theme: theme),
      );
      for (
        var attempt = 0;
        attempt < 50 && find.byType(CompanionHome).evaluate().isEmpty;
        attempt++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pump();
      }
      expect(find.byType(CompanionHome), findsOneWidget);
      await tester.pumpAndSettle();
      final featureState = tester.state(find.byType(GatheringCompanionFeature));
      final homeState = tester.state(find.byType(CompanionHome));
      final home = tester.widget<CompanionHome>(find.byType(CompanionHome));
      final change = find.byKey(const ValueKey('guide-change-spot'));
      if (change.evaluate().isNotEmpty) {
        await tester.tap(change);
        await tester.pumpAndSettle();
      }
      await tester.enterText(find.byKey(const ValueKey('spot-search')), 'Wolf');
      await tester.pumpAndSettle();
      final fieldState = tester.state(find.byType(FieldGuide));
      final mapState = tester.state(find.byType(SpotMap).first);
      final input = tester.widget<TextField>(
        find.byKey(const ValueKey('spot-search')),
      );
      final controller = input.controller;
      for (final selected in [
        themes['ledger']!,
        themes['forest']!,
        themes['sakura']!,
      ]) {
        theme.value = selected;
        await tester.pumpAndSettle();
        expect(
          tester.state(find.byType(GatheringCompanionFeature)),
          same(featureState),
        );
        expect(tester.state(find.byType(CompanionHome)), same(homeState));
        expect(tester.state(find.byType(FieldGuide)), same(fieldState));
        expect(tester.state(find.byType(SpotMap).first), same(mapState));
        final nextHome = tester.widget<CompanionHome>(
          find.byType(CompanionHome),
        );
        expect(nextHome.store, same(home.store));
        expect(nextHome.catalog, same(home.catalog));
        final nextInput = tester.widget<TextField>(
          find.byKey(const ValueKey('spot-search')),
        );
        expect(nextInput.controller, same(controller));
        expect(nextInput.controller!.text, 'Wolf');
        expect(
          tester
              .element(find.byKey(const ValueKey('spot-search')))
              .gatheringColors
              .ink,
          selected.palette.text,
        );
        expect(
          tester
              .getSize(find.byKey(const ValueKey('gathering-field-rail')))
              .width,
          198, // Approved 212px hosted rail, less its 10px/4px outer inset.
        );
        for (final stage in ['prepare', 'gather', 'history', 'spots']) {
          expect(find.byKey(ValueKey('workflow-$stage')), findsNothing);
        }
        final body = find.byKey(const ValueKey('gathering-retained-stages'));
        final stageTheme = tester
            .widget<Theme>(body)
            .data
            .extension<CompanionGlassTheme>()!;
        expect(stageTheme.colors.ink, selected.palette.text);
        expect(stageTheme.opacityPercent, 60);
        await tester.tap(find.byKey(const ValueKey('open-gathering-buffs')));
        await tester.pumpAndSettle();
        expect(
          tester
              .element(find.byKey(const ValueKey('gathering-buffs-dialog')))
              .gatheringColors
              .ink,
          selected.palette.text,
        );
        await tester.tap(find.byKey(const ValueKey('close-gathering-buffs')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('open-gathering-setup')));
        await tester.pumpAndSettle();
        final setup = find.byKey(const ValueKey('gathering-setup-dialog'));
        expect(
          tester.element(setup).gatheringColors.ink,
          selected.palette.text,
        );
        await tester.tap(
          find.descendant(of: setup, matching: find.text('Cancel')),
        );
        await tester.pumpAndSettle();
        expect(tester.state(find.byType(FieldGuide)), same(fieldState));
        expect(tester.state(find.byType(SpotMap).first), same(mapState));
        final retainedInput = tester.widget<TextField>(
          find.byKey(const ValueKey('spot-search')),
        );
        expect(retainedInput.controller, same(controller));
        expect(retainedInput.controller!.text, 'Wolf');
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.runAsync(() async {
        if (!directory.path.startsWith(
          '${Directory.systemTemp.path}${Platform.pathSeparator}bdo-gathering-theme-',
        )) {
          throw StateError('Unexpected test directory');
        }
        await directory.delete(recursive: true);
      });
    },
  );
}
