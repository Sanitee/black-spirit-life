import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bdo_craft_planner_flutter/app/app.dart';
import 'package:bdo_craft_planner_flutter/data/catalog/catalog_repository.dart';
import 'package:bdo_craft_planner_flutter/domain/catalog/item_name_presentation.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/domain/planner/reviewed_recipe_yields.dart';
import 'package:bdo_craft_planner_flutter/domain/state/state_copy.dart';
import 'package:bdo_craft_planner_flutter/features/planner/planner.dart';
import 'package:bdo_craft_planner_flutter/features/recipe_book/recipe_book.dart';
import 'package:bdo_craft_planner_flutter/features/recipe_book/reviewed_artifact_facts.dart';
import 'package:bdo_craft_planner_flutter/features/recipe_book/reviewed_container_quest_sources.dart';
import 'package:bdo_craft_planner_flutter/features/recipe_book/reviewed_monster_quest_sources.dart';
import 'package:bdo_craft_planner_flutter/features/recipe_book/reviewed_weapon_recycling_sources.dart';
import 'package:bdo_craft_planner_flutter/features/shared/mode_item_icon.dart';
import 'package:bdo_craft_planner_flutter/visual/visual.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/application_test_harness.dart';

void main() {
  setUpAll(_loadFonts);
  _supportedFactCaptures();
  for (final spec in [
    SakuraNightGardenSpec.theme,
    StandardSpec.theme,
    IlluminatedLedgerSpec.theme,
  ]) {
    for (final example in [
      (
        CraftMode.cooking,
        'Bean Sprout Salad',
        'Perilla',
        'Gather · Perilla plants in Morning Light (hands or hoe)',
        1.0,
      ),
      (
        CraftMode.cooking,
        'Bean Sprout Salad',
        'Red Pepper Powder',
        'Grinding',
        1.0,
      ),
      (
        CraftMode.cooking,
        'Bean Sprout Salad',
        'Perilla',
        'Gather · Perilla plants in Morning Light (hands or hoe)',
        2.0,
      ),
      (
        CraftMode.cooking,
        'Bean Sprout Salad',
        'Red Pepper Powder',
        'Grinding',
        2.0,
      ),
    ]) {
      final (craftMode, target, name, source, scale) = example;
      testWidgets('verified source $name ${spec.id} text $scale', (
        tester,
      ) async {
        const size = Size(1200, 752);
        configureApplicationTestSurface(tester, size, textScaleFactor: scale);
        final original = (await tester.runAsync(
          () => ApplicationTestHarness.create(
            backgroundId: spec.isStandard ? 'greenhouse' : spec.id,
            activeMode: craftMode,
          ),
        ))!;
        final harness = original.rebindControllerInCurrentZone();
        await tester.runAsync(original.disposeControllerOnly);
        final mode = harness.bundle.controller.active;
        expect(mode.selectTarget(target), isTrue);
        mode.updateState((state) => state.copyWith(want: 100), immediate: true);
        final before = mode.state.value.toJson();
        try {
          await tester.pumpWidget(
            RepaintBoundary(
              key: const ValueKey('source-capture'),
              child: BdoCraftPlannerApp(
                enableOpportunityAutoCheck: false,
                applicationFuture: Future.value(harness.bundle),
                marketGateway: const EmptyMarketGateway(),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final anchor = find.byKey(
            PlannerActionKeys.row('P22', '$target:$name'),
          );
          final queue = find
              .descendant(
                of: find.byKey(
                  const PageStorageKey<String>('planner-craft-queue'),
                ),
                matching: find.byType(Scrollable),
              )
              .first;
          if (anchor.evaluate().isEmpty) {
            final expand = find.byKey(PlannerActionKeys.row('P09', target));
            await tester.scrollUntilVisible(expand, 180, scrollable: queue);
            await tester.ensureVisible(expand);
            await tester.pumpAndSettle();
            await tester.tap(expand);
            await tester.pumpAndSettle();
          }
          await tester.scrollUntilVisible(anchor, 160, scrollable: queue);
          await tester.ensureVisible(anchor);
          await tester.pumpAndSettle();
          await tester.tap(anchor);
          await tester.pumpAndSettle();
          final popup = find.byType(ItemReferenceCard);
          expect(popup, findsOneWidget);
          expect(
            find.descendant(of: popup, matching: find.text(source)),
            findsOneWidget,
          );
          if (name == 'Powder of Darkness') {
            expect(
              find.text('Mine rocks with a pickaxe (rare)'),
              findsOneWidget,
            );
          }
          final rect = tester.getRect(popup);
          expect(rect.left, greaterThanOrEqualTo(0));
          expect(rect.right, lessThanOrEqualTo(size.width));
          expect(rect.top, greaterThanOrEqualTo(0));
          expect(rect.bottom, lessThanOrEqualTo(size.height));
          await _capture(
            tester,
            '${name.toLowerCase().replaceAll(' ', '-')}-${spec.id}-${scale.toInt()}',
          );
          final used = find.byKey(
            const ValueKey('attached-reference-tab:used'),
          );
          if (used.evaluate().isNotEmpty) {
            await tester.tap(used);
            await tester.pumpAndSettle();
            await tester.tap(
              find.byKey(const ValueKey('attached-reference-tab:recipe')),
            );
            await tester.pumpAndSettle();
            expect(
              find.descendant(of: popup, matching: find.text(source)),
              findsOneWidget,
            );
          }
          expect(mode.state.value.toJson(), before);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await harness.disposeControllerOnly();
          await tester.runAsync(
            () => harness.temporaryDirectory.delete(recursive: true),
          );
        }
      });
    }
  }
}

void _supportedFactCaptures() {
  for (final spec in [
    SakuraNightGardenSpec.theme,
    StandardSpec.theme,
    IlluminatedLedgerSpec.theme,
  ]) {
    for (final scale in [1.0, 2.0]) {
      for (final name in [
        'Bean Sprouts',
        'Soybean Paste',
        'Soy Sauce',
        'Harmony Draught - Demihuman',
        'Grain Juice',
        'Magic Crystal of Infinity - HP Recovery',
        'Magic Crystal of Infinity - Sturdiness',
        'Magic Crystal of Infinity - Vigor',
        'Obsidian Hammer',
        'Strawberry',
        'Everlasting Herb',
        "Stonetail Wind's Meal",
        'Armor Draught',
        'Blue Tidal Draught',
        "Beast's Draught",
        "Giant's Draught",
        'Origin of Margoria',
        'Origin of Eltro',
        'Origin of Serni',
        'Origin of Zulatia',
        'Origin of Rusalka',
        'Magical Shard',
        'Resplendent Boss Weapon Reform Stone V',
        'Imperfect Lightstone of Flora',
        'Purified Lightstone of Flora',
        'Trace of Nature',
        'Grade 3 Armor Reform Stone',
        'Grade 3 Weapon Reform Stone',
        'Concentrated Magical Black Gem',
        'Acacia Plank',
        'Melted Copper Shard',
        'Fancy Feather',
        'Silkworm Cocoon',
        'Caphras Tree Plank',
        'Supreme Lightweight Plume',
        'Supreme Tough Hide',
        'Ancient Hammer',
        'Primordial Hammer',
        "Dahn's Gloves (Bound)",
        "Ator's Shoes (Bound)",
        'Essence of Dawn',
        "Essence of Dawn - Black Spirit's Rage",
        'Essence of Dawn - Accuracy',
        'Essence of Dawn - Damage Reduction',
        'Essence of Dawn - Evasion',
        'Crystallized Energy of Endtimes',
        'Black Stone',
        'Sharp Black Crystal Shard',
        'Royal Fern Root',
        'Stonetail Fodder',
        'Breezy Conch Seaweed',
        'Deep Blue Hoof Root',
        'High-quality Carrot',
        'Special Carrot',
        'Destruction Spirit Stone',
        'Guardian Spirit Stone',
        'Life Spirit Stone',
        'Primordial Crystal',
        'Embers of the Primordial',
        'Reforge Stone - All AP',
        'JIN Magic Crystal - Harphia',
        'BON Magic Crystal - Viper',
        'WON Magic Crystal - Addis',
        'Forest Fury',
        'Caphras Stone',
        'Black Magic Crystal - Harphia',
        'Black Stone Powder',
        'Scorched Fragment',
        'Sturdy Snow White Stone',
        'Rough Ruby',
        "Hercules' Might Armor",
        "Heve's Strength Armor",
        "Fortuna's Luck Armor",
        'Krea Staff',
        'Magic Crystal of Infinity - Critical Hit',
        'Black Magic Crystal - Assault',
        'Ogre Ring',
        "Sicil's Necklace",
        'Ring of Crescent Guardian',
        'Centaurus Belt',
        'Sunset Dyed Wool',
        'Metal Solvent',
        'Necklace of Shultz the Gladiator',
        'Mark of Shadow',
        'Dawn Earring',
        'Tungrad Necklace',
        'Tungrad Ring',
        'Remnants of the Rift',
        "Vell's Concentrated Magic",
        'Tree Spirit Stone Fragment',
        'Earth Spirit Stone Fragment',
        'Water Spirit Stone Fragment',
        'Wind Spirit Stone Fragment',
        'Turo Heart',
        'Fused Crystal of Emotions',
        'Refined Essence of Emotions',
        'Dawnbound Ekleta Necklace',
        'Sunstarved Apeiron Ring',
        'Ethereal Earring',
        'Ocean Haze Ring',
        'Taritas Helmet',
        'Taritas Armor',
        'Taritas Gloves',
        'Taritas Shoes',
        'Blue Coral Earring',
        'Red Coral Earring',
        'Blue Coral Ring',
        'Red Coral Ring',
        'Token of Friendship',
        'Insectivore Plant Powder',
        'Insectivore Plant Sap',
        'Insectivore Plant Flower',
        'Insectivore Plant Leaf',
        'Insectivore Plant Root',
        'Insectivore Plant Stalk',
        'Pure Iron Crystal',
        'Pure Lead Crystal',
        'Pure Platinum Crystal',
        'Pure Silver Crystal',
        'Pure Tin Crystal',
        'Pure Titanium Crystal',
        'Pure Zinc Crystal',
        'Concentrated Herbal Juice',
        'Highly Concentrated Herbal Juice',
        'Elixir of Regeneration',
        'Grape-scented Herbal Wine',
        "Marsh's Artifact - Extra AP Against Monsters",
        "Lesha's Artifact - Monster Damage Reduction",
        "Kehelle's Artifact - Max HP",
        "Sethra's Artifact - Life Skill Mastery",
        'Purified Lightstone',
        'Iron Ingot',
        'Concentrated Grain Juice',
        'Highly Concentrated Grain Juice',
        'Refined Herbal Juice',
        'Resplendent Lightstone of Fire',
        'Resplendent Lightstone of Earth',
        'Resplendent Lightstone of Wind',
        'Resplendent Lightstone of Flora',
        'High-Quality Amanita Mushroom',
        'Special Amanita Mushroom',
        'Concentrated Boss Crystal',
        'Black Essence: Addis',
        'Black Essence: Carmae',
        'Black Essence: Cobelinus',
        'Black Essence: Hystria',
        'Black Essence: Viper',
        'Black Essence: Black Spirit Crystal',
        'Spellbound Tool Box',
        'Storm Horse Gear Box',
        'Deep Blue Tidal Draught',
        "Khan's Heart: Life",
        "Khan's Dim Magic",
        'Sturdy Whale Tendon Elixir',
        'Sturdy Whale Tendon Potion',
        'Fiery Celerity Draught',
        'Immortal: Perfume of Envy',
        'Immortal: Perfume of Tenacity',
        'Blush Leaf',
        'Wildspark',
        'Sangpyeong Coin',
        'Sangpyeong Coin Chest',
        'Essence of Taebaek',
        'Tear of Illusion',
        'Energy of Lakiaro',
        "Sethra's Artifact - Gathering EXP",
        'Teff Flour',
        'Black Gold Ingot',
        'Black Magic Crystal - Addis',
        'Passion of Valtarra',
        'Delotia Powder',
        'Melted Iron Shard',
        'Fine Lightweight Plume',
        'Polished Stone',
        'Fine Soft Hide',
        'Snowfield Cedar Plywood',
        'Melted Gold Shard',
        'Cheese',
        "Sethra's Artifact - Cooking EXP",
        "Sethra's Artifact - Processing EXP",
        "Sethra's Artifact - Trading EXP",
        'Dried Pearl Oyster Flesh',
        'Dried Silver Stripe Round Herring',
        'Dried Mullet',
        'Dried Flower Icefish',
        "Manos Alchemist's Clothes",
        'Manos Butcher Knife',
        "Manos Cook's Clothes",
        "Manos Fisher's Clothes",
        'Manos Fluid Collector',
        'Manos Hoe',
        'Manos Riding Crop',
        'Manos Tanning Knife',
        "Manos Trainer's Clothes",
        'Contained Boss Aura',
        'Concentrated Bheg Crystal',
        "Resplendent Bheg's Gloves Reform Stone V",
        'Advice of Valks (+50)',
        'Advice of Valks (+100)',
        "Sethra's Artifact - Life EXP",
        "Sethra's Artifact - Sailing EXP",
        "Sethra's Artifact - Sailing Mastery",
      ]) {
        testWidgets('supported fact card $name ${spec.id} $scale', (
          tester,
        ) async {
          configureApplicationTestSurface(
            tester,
            const Size(1200, 752),
            textScaleFactor: scale,
          );
          final original = (await tester.runAsync(
            () => ApplicationTestHarness.create(
              backgroundId: spec.isStandard ? 'greenhouse' : spec.id,
            ),
          ))!;
          final harness = original.rebindControllerInCurrentZone();
          await tester.runAsync(original.disposeControllerOnly);
          final mode = harness.bundle.controller.active;
          final book = RecipeBookController(
            modeController: mode,
            catalogRepository: CatalogRepository(harness.bundle.catalog),
            callingContext: RecipeBookCallingContext.planner,
            allowedTargets: mode.craftableNames,
          );
          if (name == 'Purified Lightstone of Flora') {
            expect(mode.selectTarget(name), isTrue);
            mode.updateState(
              (state) => state.copyWith(want: 10),
              immediate: true,
            );
          }
          final before = mode.state.value.toJson();
          final copied = <String>[];
          try {
            await tester.pumpWidget(
              RepaintBoundary(
                key: const ValueKey('source-capture'),
                child: BdoCraftPlannerApp(
                  enableOpportunityAutoCheck: false,
                  applicationFuture: Future.value(harness.bundle),
                  marketGateway: const EmptyMarketGateway(),
                ),
              ),
            );
            await tester.pumpAndSettle();
            if (name == 'Purified Lightstone of Flora') {
              final note = find.byKey(ValueKey('planner-output-note:$name'));
              final queue = find
                  .descendant(
                    of: find.byKey(
                      const PageStorageKey<String>('planner-craft-queue'),
                    ),
                    matching: find.byType(Scrollable),
                  )
                  .first;
              await tester.scrollUntilVisible(note, 240, scrollable: queue);
              await tester.ensureVisible(note);
              await tester.pumpAndSettle();
              expect(
                tester.widget<Text>(note).data,
                reviewedLightstoneYieldNote,
              );
              expect(tester.takeException(), isNull);
              await _capture(
                tester,
                'lightstone-planner-${spec.id}-${scale.toInt()}',
              );
            }
            final context = tester.element(find.byType(Scaffold).first);
            unawaited(
              showDialog<void>(
                context: context,
                builder: (context) => Dialog(
                  backgroundColor: Colors.transparent,
                  child: SizedBox(
                    width: 480,
                    child: ItemReferenceCard(
                      controller: book,
                      mode: mode.mode,
                      name: name,
                      info: book.itemInfoFor(name)!,
                      maxWidth: 480,
                      spec: spec,
                      onClose: () => Navigator.of(context).pop(),
                      onCopyItemName: copied.add,
                    ),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            final card = find.byType(ItemReferenceCard);
            expect(card, findsOneWidget);
            if (name.startsWith('Resplendent Lightstone of ')) {
              final icon = find
                  .descendant(
                    of: card,
                    matching: find.byWidgetPredicate(
                      (w) => w is ModeItemIcon && w.name == name,
                    ),
                  )
                  .first;
              expect(
                find.descendant(of: icon, matching: find.byType(Image)),
                findsOneWidget,
              );
            }
            if (name == 'Insectivore Plant Powder' ||
                name == 'Insectivore Plant Sap') {
              final ingredients = name == 'Insectivore Plant Powder'
                  ? ['Insectivore Plant Flower', 'Insectivore Plant Leaf']
                  : ['Insectivore Plant Stalk', 'Insectivore Plant Root'];
              for (final ingredient in ingredients) {
                final badge = find.descendant(
                  of: card,
                  matching: find.byKey(
                    ValueKey('reference-source:$ingredient'),
                  ),
                );
                expect(badge, findsOneWidget);
                await tester.ensureVisible(badge);
                await tester.pumpAndSettle();
                final badgeRect = tester.getRect(badge);
                final cardRect = tester.getRect(card);
                expect(badgeRect.top, greaterThanOrEqualTo(cardRect.top));
                expect(badgeRect.bottom, lessThanOrEqualTo(cardRect.bottom));
              }
              expect(
                find.descendant(
                  of: card,
                  matching: find.textContaining('Tree Spirit Stone Fragment'),
                ),
                findsNothing,
              );
            }
            if (name.startsWith('Origin of ')) {
              expect(
                find.descendant(of: card, matching: find.text('Use recipe')),
                findsNothing,
              );
              final recycling = find.descendant(
                of: card,
                matching: find.textContaining('(consumes the crystal)'),
              );
              expect(recycling, findsOneWidget);
              await tester.ensureVisible(recycling);
              await tester.pumpAndSettle();
              final cardRect = tester.getRect(card);
              final sourceRect = tester.getRect(recycling);
              expect(sourceRect.top, greaterThanOrEqualTo(cardRect.top));
              expect(sourceRect.bottom, lessThanOrEqualTo(cardRect.bottom));
            }
            if (const {
              'Black Magic Crystal - Harphia',
              'Black Stone Powder',
              'Scorched Fragment',
              'Sturdy Snow White Stone',
              'Rough Ruby',
            }.contains(name)) {
              final gemSource = find.descendant(
                of: card,
                matching: find.textContaining('Rough Lustrous Gem · Open'),
              );
              expect(gemSource, findsOneWidget);
              await tester.ensureVisible(gemSource);
              await tester.pumpAndSettle();
              final cardRect = tester.getRect(card);
              final sourceRect = tester.getRect(gemSource);
              expect(sourceRect.top, greaterThanOrEqualTo(cardRect.top));
              expect(sourceRect.bottom, lessThanOrEqualTo(cardRect.bottom));
            }
            if (RegExp(r'^(JIN|BON|WON) Magic Crystal - ').hasMatch(name)) {
              expect(
                find.descendant(of: card, matching: find.text('Use recipe')),
                findsNothing,
              );
              final result = find.descendant(
                of: card,
                matching: find.textContaining('1 matching JIN, BON or WON'),
              );
              expect(result, findsOneWidget);
              await tester.ensureVisible(result);
              await tester.pumpAndSettle();
              final cardRect = tester.getRect(card);
              final resultRect = tester.getRect(result);
              expect(resultRect.top, greaterThanOrEqualTo(cardRect.top));
              expect(resultRect.bottom, lessThanOrEqualTo(cardRect.bottom));
            }
            if (const {
              'Primordial Crystal',
              'Embers of the Primordial',
              'Reforge Stone - All AP',
            }.contains(name)) {
              final sources = book.itemInfoFor(name)!.howToObtain;
              expect(
                sources.where((s) => s.contains('World Boss')),
                hasLength(1),
              );
              expect(sources, isNot(contains('World bosses · Morning Light')));
              expect(
                find.descendant(
                  of: card,
                  matching: find.text('World bosses · Morning Light'),
                ),
                findsNothing,
              );
            }
            final containerQuestFact = [
              ...reviewedContainerQuestSources.values,
              ...reviewedMonsterQuestSources.values,
              ...reviewedWeaponRecyclingSources.values,
            ].where((r) => r.$1 == name).firstOrNull;
            if (containerQuestFact != null) {
              for (final source in containerQuestFact.$2) {
                final line = find.descendant(
                  of: card,
                  matching: find.text(source),
                );
                expect(line, findsOneWidget);
                await tester.ensureVisible(line);
                await tester.pumpAndSettle();
                expect(
                  tester.getRect(line).top,
                  greaterThanOrEqualTo(tester.getRect(card).top),
                );
                expect(
                  tester.getRect(line).bottom,
                  lessThanOrEqualTo(tester.getRect(card).bottom),
                );
              }
            }
            if (name == 'Deep Blue Hoof Root' || name == 'Scorched Fragment') {
              expect(
                find.descendant(
                  of: card,
                  matching: find.byKey(
                    ValueKey('mode-item-icon:image:${name.toLowerCase()}'),
                  ),
                ),
                findsOneWidget,
              );
              expect(
                find.byKey(
                  ValueKey('mode-item-icon:failure:${name.toLowerCase()}'),
                ),
                findsNothing,
              );
            }
            if (name == 'Strawberry' || name == 'Everlasting Herb') {
              expect(
                find.descendant(
                  of: card,
                  matching: find.text('When eaten raw'),
                ),
                findsNothing,
              );
            }
            expect(
              find.descendant(
                of: card,
                matching: find.text(itemDisplayName(name)),
              ),
              findsOneWidget,
            );
            await tester.tap(
              find.descendant(
                of: card,
                matching: find.text(itemDisplayName(name)),
              ),
            );
            await tester.pump();
            expect(copied, [itemDisplayName(name)]);
            final rect = tester.getRect(card);
            expect(rect.top, greaterThanOrEqualTo(0));
            expect(rect.bottom, lessThanOrEqualTo(752));
            expect(rect.width, lessThanOrEqualTo(480));
            expect(tester.takeException(), isNull);
            await _capture(
              tester,
              'supported-${name.toLowerCase().replaceAll(RegExp(r"[^a-z0-9]+"), '-')}-${spec.id}-${scale.toInt()}',
            );
            if (name == "Khan's Heart: Life" ||
                name == 'Fiery Celerity Draught' ||
                name == 'Sturdy Whale Tendon Elixir' ||
                name == 'Sturdy Whale Tendon Potion') {
              final text = switch (name) {
                "Khan's Heart: Life" => "or 3 Khan's Dim Magic",
                'Fiery Celerity Draught' => 'or 4 Celerity Draught',
                'Sturdy Whale Tendon Elixir' => 'or 3 Whale Tendon Elixir',
                _ => 'or 1 Superior Whale Tendon Potion',
              };
              final alternative = find.descendant(
                of: card,
                matching: find.text(text),
              );
              expect(alternative, findsOneWidget);
              await tester.ensureVisible(alternative);
              await tester.pumpAndSettle();
              expect(
                tester.getRect(alternative).top,
                greaterThanOrEqualTo(tester.getRect(card).top),
              );
              expect(
                tester.getRect(alternative).bottom,
                lessThanOrEqualTo(tester.getRect(card).bottom),
              );
              await _capture(
                tester,
                'practical-alternative-${name.toLowerCase().replaceAll(RegExp(r"[^a-z0-9]+"), '-')}-${spec.id}-${scale.toInt()}',
              );
            }
            if (name == 'Immortal: Perfume of Envy' ||
                name == 'Immortal: Perfume of Tenacity') {
              final input = name.endsWith('Envy')
                  ? 'Immortal: Perfume of Courage'
                  : 'Immortal: Perfume of Deep Sea';
              final ingredients = find.descendant(
                of: card,
                matching: find.text(input),
              );
              expect(ingredients, findsNWidgets(2));
              await tester.ensureVisible(ingredients.last);
              await tester.pumpAndSettle();
              expect(
                tester.getRect(ingredients.last).top,
                greaterThanOrEqualTo(tester.getRect(card).top),
              );
              expect(
                tester.getRect(ingredients.last).bottom,
                lessThanOrEqualTo(tester.getRect(card).bottom),
              );
              await _capture(
                tester,
                'practical-conversion-${name.toLowerCase().replaceAll(RegExp(r"[^a-z0-9]+"), '-')}-${spec.id}-${scale.toInt()}',
              );
            }
            if (name == 'Teff Flour') {
              expect(
                find.descendant(of: card, matching: find.text('Grinding')),
                findsOneWidget,
              );
            }
            if (name == 'Deep Blue Tidal Draught') {
              final alternate = find.descendant(
                of: card,
                matching: find.text('or 2 Blue Tidal Draught'),
              );
              expect(alternate, findsOneWidget);
              await tester.ensureVisible(alternate);
              await tester.pumpAndSettle();
              expect(
                tester.getRect(alternate).top,
                greaterThanOrEqualTo(tester.getRect(card).top),
              );
              expect(
                tester.getRect(alternate).bottom,
                lessThanOrEqualTo(tester.getRect(card).bottom),
              );
              expect(tester.takeException(), isNull);
              await _capture(
                tester,
                'tidal-alternative-${spec.id}-${scale.toInt()}',
              );
            }
            if (reviewedBasicArtifacts.values.contains(name)) {
              await tester.tap(
                find.byKey(const ValueKey('attached-reference-tab:used')),
              );
              await tester.pumpAndSettle();
              final exchange = find.descendant(
                of: card,
                matching: find.textContaining(
                  'Spare artifact (no Lightstones)',
                ),
              );
              expect(exchange, findsOneWidget);
              await tester.ensureVisible(exchange);
              await tester.pumpAndSettle();
              expect(
                tester.getRect(exchange).top,
                greaterThanOrEqualTo(tester.getRect(card).top),
              );
              expect(
                tester.getRect(exchange).bottom,
                lessThanOrEqualTo(tester.getRect(card).bottom),
              );
              expect(
                find.descendant(of: card, matching: find.text('Use recipe')),
                findsNothing,
              );
              expect(tester.takeException(), isNull);
              await _capture(
                tester,
                'artifact-use-${name.toLowerCase().replaceAll(RegExp(r"[^a-z0-9]+"), '-')}-${spec.id}-${scale.toInt()}',
              );
              await tester.tap(
                find.byKey(const ValueKey('attached-reference-tab:recipe')),
              );
              await tester.pumpAndSettle();
            }
            if (const {
              'Destruction Spirit Stone',
              'Guardian Spirit Stone',
              'Life Spirit Stone',
            }.contains(name)) {
              final source = find.descendant(
                of: card,
                matching: find.textContaining('Monster drops · Kamasylvia'),
              );
              expect(source, findsOneWidget);
              await tester.ensureVisible(source);
              await tester.pumpAndSettle();
              final sourceRect = tester.getRect(source);
              expect(sourceRect.top, greaterThanOrEqualTo(rect.top));
              expect(sourceRect.bottom, lessThanOrEqualTo(rect.bottom));
              expect(tester.takeException(), isNull);
              await _capture(
                tester,
                'source-visible-${name.toLowerCase().replaceAll(' ', '-')}-${spec.id}-${scale.toInt()}',
              );
            }
            expect(mode.state.value.toJson(), before);
          } finally {
            await tester.pumpWidget(const SizedBox.shrink());
            book.dispose();
            await harness.disposeControllerOnly();
            await tester.runAsync(
              () => harness.temporaryDirectory.delete(recursive: true),
            );
          }
        });
      }
    }
  }
}

Future<void> _capture(WidgetTester tester, String name) async {
  final output = Platform.environment['BSL_VERIFIED_SOURCE_CAPTURE_DIR'];
  if (output == null || output.isEmpty) return;
  await tester.runAsync(() async {
    await Future.wait([
      for (final element in find.byType(Image).evaluate())
        precacheImage((element.widget as Image).image, element),
    ]);
  });
  await tester.pumpAndSettle();
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('source-capture')),
  );
  await tester.runAsync(() async {
    await Directory(output).create(recursive: true);
    final image = await boundary.toImage();
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      await File('$output/$name.png').writeAsBytes(data!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
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
  for (final family in {
    'Georgia': ['$windows/Fonts/georgia.ttf', '$windows/Fonts/georgiab.ttf'],
    'Segoe UI': [
      '$windows/Fonts/segoeui.ttf',
      '$windows/Fonts/seguisb.ttf',
      '$windows/Fonts/segoeuib.ttf',
    ],
    'Roboto': [
      '${sdk.path}/bin/cache/artifacts/material_fonts/roboto-regular.ttf',
      '${sdk.path}/bin/cache/artifacts/material_fonts/roboto-bold.ttf',
    ],
    'MaterialIcons': [
      '${sdk.path}/bin/cache/artifacts/material_fonts/materialicons-regular.otf',
    ],
  }.entries) {
    final loader = FontLoader(family.key);
    for (final file in family.value) {
      loader.addFont(File(file).readAsBytes().then(ByteData.sublistView));
    }
    await loader.load();
  }
}
