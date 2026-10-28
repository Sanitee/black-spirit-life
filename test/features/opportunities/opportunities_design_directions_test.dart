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
import 'design_directions/merchant_ledger_concept.dart';
import 'design_directions/moonlit_workshop_concept.dart';
import 'design_directions/night_market_concept.dart';

void main() {
  setUpAll(_loadFonts);
  final concepts = <String, Widget Function(ConceptItemIcon)>{
    'night_market': (icons) => NightMarketConcept(itemIcon: icons),
    'merchant_ledger': (icons) => MerchantLedgerConcept(itemIcon: icons),
    'moonlit_workshop': (icons) => MoonlitWorkshopConcept(itemIcon: icons),
  };
  for (final entry in concepts.entries) {
    testWidgets('${entry.key} is a readable native design preview', (
      tester,
    ) async {
      configureApplicationTestSurface(tester, const Size(1500, 940));
      final harness = (await tester.runAsync(
        () => ApplicationTestHarness.create(),
      ))!;
      final catalog = CatalogRepository(harness.bundle.catalog);
      Widget icon(String name, double size) => ModeItemIcon(
        controller: harness.bundle.controller.modes[CraftMode.cooking]!,
        catalogRepository: catalog,
        name: name,
        size: size,
        searchAcrossModes: true,
        showFrame: false,
      );
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(fontFamily: 'Segoe UI', brightness: Brightness.dark),
          home: Scaffold(
            body: RepaintBoundary(
              key: const ValueKey('design-preview'),
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
      for (final recipe in conceptRecipes) {
        expect(find.text(recipe.name), findsOneWidget);
        final image = tester.widget<ModeItemIcon>(
          find.byWidgetPredicate(
            (w) => w is ModeItemIcon && w.name == recipe.name,
          ),
        );
        expect(image.size, 64);
        expect(image.showFrame, isFalse);
      }
      expect(find.text('Design preview · Example prices'), findsOneWidget);
      expect(find.text('Sale after tax'), findsNothing);
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byKey(const ValueKey('design-preview')),
        matchesGoldenFile('design_directions/goldens/${entry.key}.png'),
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(harness.dispose);
    });
  }
}

Future<void> _loadFonts() async {
  if (!Platform.isWindows) return;
  final windowsPath = Platform.environment['WINDIR'] ?? r'C:\Windows';
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
      '$windowsPath/Fonts/segoeui.ttf',
      '$windowsPath/Fonts/seguisb.ttf',
      '$windowsPath/Fonts/segoeuib.ttf',
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
