import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bdo_craft_planner_flutter/data/catalog/bundled_catalog_parser.dart';
import 'package:bdo_craft_planner_flutter/data/catalog/catalog_repository.dart';
import 'package:bdo_craft_planner_flutter/data/market/shared_market_repository.dart';
import 'package:bdo_craft_planner_flutter/data/opportunities/market_eligibility.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/domain/planner/ingredient_quality.dart';
import 'package:bdo_craft_planner_flutter/features/planner/planner_choice_market.dart';
import 'package:bdo_craft_planner_flutter/features/planner/planner_contracts.dart';
import 'package:bdo_craft_planner_flutter/features/recipe_book/recipe_book.dart';
import 'package:bdo_craft_planner_flutter/visual/visual.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/availability_badge_finders.dart';
import '../../support/choice_market_transport.dart';
import '../planner/planner_choice_market_test.dart' show settle;
import '../planner/planner_review_projection_test.dart' as fixture;

void main() {
  final catalog = const BundledCatalogParser().parse(
    File('assets/data/app-data.json').readAsStringSync(),
  );
  final repository = CatalogRepository.cached(catalog);
  test(
    'all catalogued ingredient alternatives and quality grades resolve availability',
    () async {
      final app = fixture.controller(catalog, CraftMode.cooking, 'Beer', 1);
      addTearDown(app.dispose);
      final names = <String>{};
      for (final mode in app.modes.values) {
        for (final recipe in mode.recipes.values) {
          for (final inputs in [
            recipe.ingredients,
            ...recipe.variants.map((v) => v.ingredients),
          ]) {
            for (final input in inputs) {
              for (final name in {
                input.name,
                ...input.options,
                ...input.substituteRatios.keys,
              }) {
                names.add(name);
                if (recipe.type != 'processing') {
                  names.addAll(
                    ingredientQualityAlternatives(
                      rules: app.plannerRules,
                      ingredientName: name,
                    ).map((q) => q.name),
                  );
                }
              }
            }
          }
        }
      }
      var checked = 0;
      final dual = <String>[];
      for (final name in names) {
        final id = repository.bundledMarketId(name);
        if (id == null || !isOpportunityMarketRequestEligible(id)) continue;
        for (final mode in app.modes.values) {
          final identity = choiceMarketIdentity(mode, name, acrossModes: true);
          expect(identity.marketId, id, reason: '${mode.mode.name}: $name');
          checked++;
          if (mode.mode == CraftMode.cooking && identity.npc) dual.add(name);
        }
      }
      debugPrint(
        'AVAILABILITY: $checked mode/name identities; dual sources: $dual',
      );
      expect(checked, greaterThan(1000));
    },
  );
  setUpAll(() async {
    for (final entry in {
      'Segoe UI': [
        'C:/Windows/Fonts/segoeui.ttf',
        'C:/Windows/Fonts/seguisb.ttf',
      ],
      'Georgia': [
        'C:/Windows/Fonts/georgia.ttf',
        'C:/Windows/Fonts/georgiab.ttf',
      ],
      'MaterialIcons': [
        'D:/Tools/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
      ],
    }.entries) {
      final loader = FontLoader(entry.key);
      for (final f in entry.value) {
        loader.addFont(File(f).readAsBytes().then(ByteData.sublistView));
      }
      await loader.load();
    }
  });
  for (final spec in RetainedThemeRegistry.themes) {
    for (final scale in [1.0, 2.0]) {
      for (final name in ['Wheat Flour', 'Eilton Sandwich']) {
        testWidgets('every source $name ${spec.id} $scale', (tester) async {
          tester.view.physicalSize = const Size(1400, 1000);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final app = fixture.controller(catalog, CraftMode.cooking, 'Beer', 1);
          final book = RecipeBookController(
            modeController: app.active,
            catalogRepository: repository,
            callingContext: RecipeBookCallingContext.planner,
            allowedTargets: const [],
          );
          final before = jsonEncode(app.documentSnapshot.toJson());
          final transport = ChoiceMarketTransport();
          transport.values[repository.bundledMarketId('High-Quality Wheat')!] =
              (price: 100, stock: 4321, preorders: 12);
          transport.values[repository.bundledMarketId('Paprika')!] = (
            price: 100,
            stock: 0,
            preorders: 84,
          );
          final broker = SharedMarketRepository(
            transport: transport,
            requestSpacing: Duration.zero,
          );
          Widget host() => MaterialApp(
            home: ThemeSpecScope(
              spec: spec,
              child: MediaQuery(
                data: MediaQueryData(
                  size: const Size(1400, 1000),
                  textScaler: TextScaler.linear(scale),
                ),
                child: PlannerChoiceMarketScope(
                  repository: broker,
                  child: Scaffold(
                    body: Center(
                      child: Builder(
                        builder: (context) => RepaintBoundary(
                          key: const ValueKey('capture'),
                          child: ItemReferenceCard(
                            controller: book,
                            mode: CraftMode.cooking,
                            name: name,
                            info: book.itemInfoFor(name)!,
                            maxWidth: itemReferenceCardMaxWidth(context),
                            spec: spec,
                            onClose: () {},
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpWidget(host());
          // Before fetching, the HQ badge is present, but does not claim zero.
          final grade = find.byKey(
            const ValueKey('reference-source:High-quality Wheat'),
          );
          if (name == 'Wheat Flour') {
            expect(grade, findsOneWidget);
            expect(
              find.descendant(of: grade, matching: stockBadgeText('—')),
              findsOneWidget,
            );
          }
          await settle(tester, broker);
          await tester.pumpAndSettle();
          if (name == 'Wheat Flour') {
            for (final n in ['Wheat', 'High-quality Wheat', 'Special Wheat']) {
              expect(
                find.byKey(ValueKey('reference-source:$n')),
                findsOneWidget,
              );
            }
            expect(
              find.descendant(of: grade, matching: stockBadgeText('4,3k')),
              findsOneWidget,
            );
            expect(
              find.descendant(of: grade, matching: find.text('Orders 12')),
              findsOneWidget,
            );
            if (scale == 1) {
              expect(
                tester.getRect(grade).left,
                greaterThan(
                  tester.getRect(find.text('or 1 High-quality Wheat')).right,
                ),
              );
            }
          } else {
            final paprika = find.byKey(
              const ValueKey('reference-source:Paprika'),
            );
            expect(
              find.descendant(
                of: find.byKey(const ValueKey('reference-npc:Paprika')),
                matching: find.text('NPC'),
              ),
              findsOneWidget,
            );
            for (final text in ['0', 'Orders 84']) {
              expect(
                find.descendant(of: paprika, matching: find.text(text)),
                findsOneWidget,
              );
            }
          }
          expect(jsonEncode(app.documentSnapshot.toJson()), before);
          expect(tester.takeException(), isNull);
          final imageWidgets = tester
              .widgetList<Image>(find.byType(Image))
              .toList();
          await tester.runAsync(() async {
            for (final i in imageWidgets) {
              await precacheImage(
                i.image,
                tester.element(find.byKey(const ValueKey('capture'))),
              );
            }
          });
          await tester.pumpAndSettle();
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(const ValueKey('capture')),
          );
          await tester.runAsync(() async {
            final image = await boundary.toImage();
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            final out = File(
              'tmp/substitute-availability/${spec.id}-$scale-$name.png',
            );
            await out.parent.create(recursive: true);
            await out.writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
          await tester.pumpWidget(const SizedBox());
          book.dispose();
          await broker.close();
          await app.dispose();
        });
      }
    }
  }
}
