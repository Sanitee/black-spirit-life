// Read-only production projection audit. Synthetic state; no profile repository,
// market client, window launch, catalog writes or persistent user state.
import 'dart:convert';
import 'dart:io';

import 'package:bdo_craft_planner_flutter/app/state/planner_application_controller.dart';
import 'package:bdo_craft_planner_flutter/data/catalog/bundled_catalog_parser.dart';
import 'package:bdo_craft_planner_flutter/data/catalog/catalog_repository.dart';
import 'package:bdo_craft_planner_flutter/data/opportunities/exchange_catalog.dart';
import 'package:bdo_craft_planner_flutter/data/opportunities/exchange_item_details.dart';
import 'package:bdo_craft_planner_flutter/domain/models/catalog_models.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/domain/planner/acquisition_recipe_resolution.dart';
import 'package:bdo_craft_planner_flutter/domain/state/planner_state.dart';
import 'package:bdo_craft_planner_flutter/features/planner/planner_contracts.dart';
import 'package:bdo_craft_planner_flutter/features/recipe_book/recipe_book.dart';
import 'package:bdo_craft_planner_flutter/features/recipe_book/recipe_book_exact_buff_info.dart';
import 'package:bdo_craft_planner_flutter/features/recipe_book/recipe_book_exact_crystal_info.dart';
import 'package:bdo_craft_planner_flutter/features/recipe_book/recipe_book_exact_food_info.dart';
import 'package:bdo_craft_planner_flutter/features/recipe_book/recipe_book_item_info.dart';
import 'package:bdo_craft_planner_flutter/features/recipe_book/recipe_book_preview_routes.dart';
import 'package:flutter_test/flutter_test.dart';

const audit = String.fromEnvironment('BSL_CORRECTNESS_AUDIT_DIR');
Map<String, Object?> ingredient(Ingredient i) => {
  'name': i.name,
  'quantity': i.quantity,
  'options': i.options,
  'group': i.substituteGroup,
  'ratios': i.substituteRatios,
};
Map<String, Object?> formula(RecipeBookFormula f) => {
  'output': f.outputName,
  'type': f.type,
  'method': f.method,
  'mode': f.mode?.key,
  'variant': f.variantId,
  'route': f.routeId,
  'routeLabel': f.routeLabel,
  'batch': f.batchMultiplier,
  'baseOutput': f.baseOutput,
  'min': f.outputMinimum,
  'max': f.outputMaximum,
  'estimated': f.outputEstimated,
  'identity': recipeBookPreviewFormulaIdentity(f),
  'ingredients': f.ingredients.map(ingredient).toList(),
};
Map<String, Object?> infoJson(RecipeBookItemInfo? info) => info == null
    ? {'null': true}
    : {
        'title': info.title,
        'kind': info.kind,
        'summary': info.summary,
        'effectsTitle': info.effectsTitle,
        'effects': info.effects,
        'sources': info.acquisitionNotes,
        'notes': info.notes,
        'uses': info.uses,
        'example': info.example,
        'archived': info.isTemporarilyArchived,
        'formulas': info.acquisitionFormulas.map(formula).toList(),
        'usedFor': info.craftUses
            .map(
              (u) => {
                'output': u.output,
                'formulas': u.formulas.map(formula).toList(),
              },
            )
            .toList(),
      };
ModeState modeState(CraftMode mode, String target) => ModeState(
  target: target,
  bonusTarget: target,
  market: MarketState(),
  appearance: AppearanceSettings.defaultsFor(mode),
);
void main() {
  test(
    'exports every shared reference through actual controllers in all three modes',
    () async {
      if (audit.isEmpty || !Directory(audit).existsSync()) {
        throw StateError(
          'Provide an existing isolated BSL_CORRECTNESS_AUDIT_DIR via --dart-define.',
        );
      }
      final text = File('assets/data/app-data.json').readAsStringSync();
      final raw = jsonDecode(text) as Map<String, dynamic>;
      final catalog = const BundledCatalogParser().parse(text);
      final repository = CatalogRepository(catalog);
      final application = PlannerApplicationController(
        catalog: catalog,
        initialState: PlannerState(
          applicationVersion: 'read-only-audit',
          lastSuccessfulWriteUtc: DateTime.utc(2026, 11, 1),
          activeMode: CraftMode.alchemy,
          alchemy: modeState(CraftMode.alchemy, 'Clear Liquid Reagent'),
          cooking: modeState(CraftMode.cooking, 'Beer'),
          processing: modeState(CraftMode.processing, 'Red Pepper Powder'),
          processingYields: const {},
          marketTax: MarketTax(),
          showDeleteTools: false,
        ),
        saveState: (state) async => state,
        saveDebounce: Duration.zero,
      );
      addTearDown(application.dispose);
      final books = <CraftMode, RecipeBookController>{};
      for (final mode in CraftMode.values) {
        final controller = application.modes[mode]!;
        final book = RecipeBookController(
          modeController: controller,
          catalogRepository: repository,
          callingContext: RecipeBookCallingContext.planner,
          allowedTargets: controller.craftableNames,
        );
        books[mode] = book;
        addTearDown(book.dispose);
      }
      final roles = <String, Set<String>>{};
      void add(String name, String role) =>
          roles.putIfAbsent(name, () => {}).add(role);
      for (final name in (raw['acquisitionInfo'] as Map).keys.cast<String>()) {
        add(name, 'acquisition registry');
      }
      for (final name in (raw['vendorInfo'] as Map).keys.cast<String>()) {
        add(name, 'vendor registry');
      }
      for (final item in exchangeItems.values) {
        add(item.name, 'exchange registry');
      }
      for (final item in exactBuffInfoByName.values) {
        add(item.title, 'buff registry');
      }
      for (final item in exactCrystalInfoByName.values) {
        add(item.title, 'crystal registry');
      }
      for (final item in exactFoodInfoByName.values) {
        add(item.title, 'food registry');
      }
      final recipes = <Map<String, Object?>>[];
      for (final mode in CraftMode.values) {
        for (final entry in catalog.forMode(mode).items.entries) {
          final r = entry.value;
          add(entry.key, '${mode.key} output');
          for (final i in [
            ...r.ingredients,
            ...r.variants.expand((v) => v.ingredients),
          ]) {
            add(i.name, '${mode.key} ingredient');
            for (final n in {...i.options, ...i.substituteRatios.keys}) {
              add(n, '${mode.key} substitute');
            }
          }
          recipes.add({
            'mode': mode.key,
            'name': entry.key,
            'id': r.marketId,
            'craftable': r.isCraftable,
            'type': r.type,
            'method': r.method,
            'role': r.role.name,
            'baseOutput': r.baseOutput,
            'min': r.outputMinimum,
            'max': r.outputMaximum,
            'sourceNote': r.sourceNote,
            'formulas': recipeBookFormulas(r, mode: mode).map(formula).toList(),
          });
        }
      }
      final records = <Map<String, Object?>>[];
      final names = roles.keys.toList()..sort();
      for (final name in names) {
        records.add({
          'name': name,
          'roles': roles[name]!.toList(),
          'id': repository.bundledMarketId(name),
          'effectiveIds': {
            for (final mode in CraftMode.values)
              mode.key:
                  resolveAcquisitionRecipe(
                    name: name,
                    currentMode: mode,
                    recipesByMode: {
                      for (final m in CraftMode.values)
                        m: application.modes[m]!.recipes,
                    },
                  )?.recipe.marketId ??
                  repository.bundledMarketId(name),
          },
          'views': {
            for (final mode in CraftMode.values)
              mode.key: infoJson(books[mode]!.itemInfoFor(name, mode: mode)),
          },
        });
      }
      final exchanges = [
        for (final e in exchangeItems.values)
          {
            'name': e.name,
            'id': e.id,
            'currencySources': [
              for (final currency in exchangeCatalog)
                if (currency.item.id == e.id)
                  {
                    'activity': currency.sourceActivity,
                    'notes': currency.notes,
                  },
            ],
            if (exchangeItemDetails[e.id] case final detail?)
              'detail': {
                'summary': detail.summary,
                'sources': detail.howToObtain,
                'effects': detail.effects,
                'notes': detail.notes,
              },
            'incomingRoutes': [
              for (final currency in exchangeCatalog)
                for (final r in currency.routes)
                  if (r.rewards.any((reward) => reward.item?.id == e.id) ||
                      r.rewardContainer?.id == e.id)
                    {
                      'currency': currency.item.name,
                      'cost': r.inputCount,
                      'location': r.location,
                      'limit': r.limit.kind.name,
                      'maximum': r.limit.maximum,
                      'requirements': r.requirements,
                      'notes': r.notes,
                      'vendorSale': r.directVendorSale,
                    },
            ],
          },
      ];
      File('$audit/controller-projection.json').writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert({
          'generatedAt': DateTime.now().toUtc().toIso8601String(),
          'catalogHash': catalog.sourceSha256,
          'personalDataAccessed': false,
          'recordCount': records.length,
          'modeViews': records.length * 3,
          'recipes': recipes,
          'items': records,
          'exchanges': exchanges,
        }),
      );
      expect(names.length, greaterThan(2200));
      expect(
        records.firstWhere((r) => r['name'] == 'Perilla')['views'],
        isNotNull,
      );
      stdout.writeln(
        'Exported ${records.length} references, ${records.length * 3} actual mode projections and ${recipes.length} catalog records. This asserts enumeration, not factual completeness.',
      );
    },
    timeout: const Timeout(Duration(minutes: 15)),
  );
}
