import 'dart:io';

import 'package:bdo_craft_planner_flutter/data/catalog/catalog_repository.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/features/opportunities/opportunities_visuals.dart';
import 'package:bdo_craft_planner_flutter/features/shared/mode_item_icon.dart';
import 'package:bdo_craft_planner_flutter/visual/visual.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/application_test_harness.dart';
import 'design_directions/concept_support.dart';
import 'design_directions/quiet_round4/quiet_board.dart';

void main() {
  setUpAll(_loadFonts);
  final concepts = <String, Widget Function(ConceptItemIcon)>{
    'quiet_onyx': (icons) => QuietOnyxBoardConcept(itemIcon: icons),
  };
  for (final entry in concepts.entries) {
    testWidgets('${entry.key} uses actual icons in a native overview', (
      tester,
    ) async {
      final previousShadows = debugDisableShadows;
      debugDisableShadows = false;
      try {
        configureApplicationTestSurface(tester, const Size(1500, 940));
        final harness = (await tester.runAsync(ApplicationTestHarness.create))!;
        final catalog = CatalogRepository(harness.bundle.catalog);
        Widget icon(String name, double size) => ModeItemIcon(
          controller: harness.bundle.controller.modes[CraftMode.alchemy]!,
          catalogRepository: catalog,
          name: name,
          size: size,
          searchAcrossModes: true,
          showFrame: false,
        );
        await tester.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData(
              fontFamily: 'Segoe UI',
              brightness: Brightness.dark,
            ),
            home: Scaffold(
              body: RepaintBoundary(
                key: const ValueKey('quiet-native-preview'),
                child: ThemeSpecScope(
                  spec: OpportunitiesVisualSpec.spec,
                  child: entry.value(icon),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        for (final element in find.byType(Image).evaluate().toList()) {
          await tester.runAsync(
            () => precacheImage((element.widget as Image).image, element),
          );
        }
        await tester.pumpAndSettle();
        for (final recipe in boardRecipes) {
          final tile = find.byKey(ValueKey('quiet-recipe-${recipe.name}'));
          final tileRect = tester.getRect(tile);
          expect(
            tileRect.bottom,
            lessThanOrEqualTo(916),
            reason: 'Keep the full card visible.',
          );
          expect(find.text(recipe.name), findsOneWidget);
          final art = find.byWidgetPredicate(
            (w) => w is ModeItemIcon && w.name == recipe.name,
          );
          final item = tester.widget<ModeItemIcon>(art);
          expect(item.size, 64);
          expect(item.showFrame, isFalse);
          expect(
            find.byKey(ModeItemIconKeys.image(recipe.name)),
            findsOneWidget,
            reason:
                '${recipe.name} must use actual bundled game art, not a fallback.',
          );
          expect(
            find.byKey(ModeItemIconKeys.failure(recipe.name)),
            findsNothing,
          );
        }
        expect(find.text('Design preview · Example prices'), findsOneWidget);
        expect(find.text('Ingredients'), findsNothing);
        expect(find.text('Sale after tax'), findsNothing);
        expect(tester.takeException(), isNull);
        await expectLater(
          find.byKey(const ValueKey('quiet-native-preview')),
          matchesGoldenFile(
            'design_directions/quiet_round4/goldens/${entry.key}.png',
          ),
        );
        await tester.tap(
          find.byKey(ValueKey('quiet-recipe-${boardRecipes.first.name}')),
        );
        await tester.pumpAndSettle();
        expect(find.text('Back'), findsOneWidget);
        await tester.tap(find.text('Back'));
        await tester.pumpAndSettle();
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.runAsync(harness.dispose);
      } finally {
        debugDisableShadows = previousShadows;
      }
    });
  }
}

Future<void> _loadFonts() async {
  if (!Platform.isWindows) return;
  final windows = Platform.environment['WINDIR'] ?? r'C:\Windows';
  var sdk = File(Platform.resolvedExecutable).parent;
  while (!Directory(
    '${sdk.path}/bin/cache/artifacts/material_fonts',
  ).existsSync()) {
    if (sdk.parent.path == sdk.path) {
      throw StateError('Flutter fonts not found');
    }
    sdk = sdk.parent;
  }
  for (final family in <String, List<String>>{
    'Segoe UI': [
      '$windows/Fonts/segoeui.ttf',
      '$windows/Fonts/seguisb.ttf',
      '$windows/Fonts/segoeuib.ttf',
    ],
    'MaterialIcons': [
      '${sdk.path}/bin/cache/artifacts/material_fonts/materialicons-regular.otf',
    ],
  }.entries) {
    final loader = FontLoader(family.key);
    for (final path in family.value) {
      loader.addFont(File(path).readAsBytes().then(ByteData.sublistView));
    }
    await loader.load();
  }
}
