import 'dart:io';

import 'package:bdo_craft_planner_flutter/app/planning/planner_assembly.dart';
import 'package:bdo_craft_planner_flutter/data/catalog/bundled_catalog_parser.dart';
import 'package:bdo_craft_planner_flutter/domain/models/catalog_models.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/domain/opportunities/opportunity_calculator.dart';
import 'package:bdo_craft_planner_flutter/domain/opportunities/opportunity_market_models.dart';
import 'package:bdo_craft_planner_flutter/domain/planner/planner_models.dart';
import 'package:bdo_craft_planner_flutter/domain/state/planner_state.dart';
import 'package:flutter_test/flutter_test.dart';

final now = DateTime.utc(2026, 9, 8, 16);
const calculator = OpportunityCalculator();

void main() {
  group('custom pre-tax unit sale price', () {
    test('expected yield, crafts and tax apply without changing purchases', () {
      final product = recipe('Product', minimum: 1, maximum: 3);
      final output = marketItem('1', price: 100, bids: [level(90, 100)]);
      final input = marketItem('2', asks: [level(10, 1), level(20, 10)]);
      OpportunityQuote quote(int? price) => calculate(
        product: product,
        crafts: 3,
        output: output,
        input: input,
        extraCostPerRun: 7,
        extraCostPerCraft: 3,
        timing: const OpportunityTimingAssumption(secondsPerCraft: 30),
        customSalePrice: price,
      );
      final standard = quote(null);
      final custom = quote(250);
      expect(custom.customSalePrice, 250);
      expect(custom.hasCustomSalePrice, isTrue);
      expect(custom.expectedOutput, 6);
      expect(custom.listingRevenue, closeTo(6 * 250 * .845, .000001));
      expect(custom.inputCost, 50);
      expect(custom.extraCost, 16);
      expect(custom.totalCost, 66);
      expect(custom.listingProfit, closeTo(6 * 250 * .845 - 66, .000001));
      expect(
        custom.listingProfitPerCraft,
        closeTo(custom.listingProfit! / 3, .000001),
      );
      expect(
        custom.listingProfitPerHour,
        closeTo(custom.listingProfit! * 40, .000001),
      );
      expect(
        custom.profitFor(OpportunitySaleMode.currentBuyers),
        custom.listingProfit,
      );
      expect(
        custom.profitFor(OpportunitySaleMode.listing),
        custom.listingProfit,
      );
      expect(custom.buyerRevenue, standard.buyerRevenue);
      expect(custom.buyerProfit, standard.buyerProfit);
      expect(custom.buyerFilledQuantity, standard.buyerFilledQuantity);
      expect(custom.buyerCraftCapacity, standard.buyerCraftCapacity);
      expect(custom.buyersCoverOutput, standard.buyersCoverOutput);
      expect(custom.outputMarket, same(output));
      expect(custom.ingredients.single.market, same(input));
      expect(custom.ingredients.single.availableQuantity, 11);
      expect(custom.ingredients.single.marketQuantity, 3);
      expect(custom.inputCraftCapacity, standard.inputCraftCapacity);
      final restored = quote(null);
      expect(restored.hasCustomSalePrice, isFalse);
      expect(restored.listingRevenue, standard.listingRevenue);
      expect(
        restored.profitFor(OpportunitySaleMode.currentBuyers),
        standard.buyerProfit,
      );
    });

    test('current tax bonuses apply to custom sales, not to expenses', () {
      final quote = calculate(
        customSalePrice: 1000,
        extraCostPerRun: 100,
        tax: MarketTax(
          valuePack: true,
          merchantRing: true,
          familyFameBonus: .005,
        ),
      );
      expect(quote.listingRevenue, closeTo(1000 * .65 * 1.355, .000001));
      expect(quote.totalCost, 110);
    });

    test('zero, negatives and over-limit values stay explicitly invalid', () {
      for (final price in [
        0,
        -1,
        OpportunityCalculator.maxCustomSalePrice + 1,
      ]) {
        final quote = calculate(customSalePrice: price, extraCostPerRun: 7);
        expect(quote.customSalePrice, price);
        expect(quote.hasCustomSalePrice, isTrue);
        expect(quote.issues, contains(OpportunityIssue.invalidSalePrice));
        expect(quote.listingRevenue, isNull);
        expect(quote.listingProfit, isNull);
        expect(quote.profitFor(OpportunitySaleMode.currentBuyers), isNull);
        expect(quote.buyerRevenue, isNotNull);
        expect(quote.inputCost, 10);
        expect(quote.extraCost, 7);
        expect(quote.marketReady, isFalse);
      }
      for (final price in [1, OpportunityCalculator.maxCustomSalePrice]) {
        final quote = calculate(customSalePrice: price);
        expect(
          quote.issues,
          isNot(contains(OpportunityIssue.invalidSalePrice)),
        );
        expect(quote.listingRevenue, price * (.65 * 1.3));
      }
    });

    test('non-finite gross is invalid, never converted to zero revenue', () {
      final quote = calculate(
        product: recipe('Product', minimum: 1e300, maximum: 1e300),
        customSalePrice: OpportunityCalculator.maxCustomSalePrice,
      );
      expect(quote.expectedOutput, 1e300);
      expect(quote.issues, contains(OpportunityIssue.invalidSalePrice));
      expect(quote.listingRevenue, isNull);
      expect(quote.listingProfit, isNull);
      expect(quote.inputCost, 10);
    });

    test(
      'missing and stale quotes allow only hypothetical custom valuation',
      () {
        for (final missing in [true, false]) {
          final quote = calculate(
            omitOutput: missing,
            output: marketItem(
              '1',
              quoteTime: now.subtract(const Duration(days: 1)),
            ),
            customSalePrice: 200,
          );
          expect(quote.listingRevenue, closeTo(169, .000001));
          expect(quote.listingProfit, closeTo(159, .000001));
          expect(quote.marketReady, isFalse);
          expect(
            quote.issues,
            contains(
              missing
                  ? OpportunityIssue.outputMarketUnknown
                  : OpportunityIssue.outputQuoteStale,
            ),
          );
          if (missing) {
            expect(quote.outputMarket, isNull);
          } else {
            expect(
              quote.outputMarket!.quoteFetchedAt,
              now.subtract(const Duration(days: 1)),
            );
          }
        }
      },
    );

    test('custom price does not invent buyers or missing ingredient costs', () {
      final emptyBids = marketItem('1', bids: []);
      final quote = calculate(output: emptyBids, customSalePrice: 500);
      expect(quote.listingRevenue, closeTo(422.5, .000001));
      expect(quote.buyerRevenue, isNull);
      expect(quote.buyersCoverOutput, isFalse);
      expect(quote.buyerFilledQuantity, 0);
      expect(quote.buyerCraftCapacity, 0);
      expect(quote.issues, contains(OpportunityIssue.insufficientBuyers));
      final unknownInput = calculate(omitInput: true, customSalePrice: 500);
      expect(unknownInput.listingRevenue, isNotNull);
      expect(unknownInput.totalCost, isNull);
      expect(unknownInput.listingProfit, isNull);
      expect(unknownInput.marketReady, isFalse);
      expect(
        unknownInput.issues,
        contains(OpportunityIssue.inputMarketUnknown),
      );
    });

    test(
      'unlisted and forbidden outputs cannot gain custom market revenue',
      () {
        final unlisted = calculate(
          output: marketItem('1', unlisted: true),
          customSalePrice: 500,
        );
        expect(unlisted.listingRevenue, isNull);
        expect(unlisted.issues, contains(OpportunityIssue.outputUnlisted));
        expect(unlisted.inputCost, 10);
        final forbidden = calculate(
          rules: PlannerRules(legacyUnavailableItems: {'Product'}),
          customSalePrice: 500,
        );
        expect(forbidden.hasCustomSalePrice, isTrue);
        expect(forbidden.listingRevenue, isNull);
        expect(forbidden.issues, contains(OpportunityIssue.recipeNotCraftable));
      },
    );
  });

  group('inspection substitutes and complete-craft splits', () {
    final product = recipe(
      'Product',
      ingredients: [
        ingredient('Ore', 1, options: ['Ore', 'Other Ore']),
      ],
    );
    final extras = {'Other Ore': leaf('Other Ore', id: '3')};
    test(
      'candidate reporting retains selectable alias and its own quantity',
      () {
        final names = <String, Set<String>>{};
        final quantities = <String, double>{};
        calculate(
          product: recipe(
            'Product',
            ingredients: [
              ingredient('Ore', 2),
              ingredient('Shared Ore', 1, options: ['Shared Ore', 'Other Ore']),
            ],
          ),
          extras: {
            ...extras,
            'Shared Ore': leaf('Shared Ore', id: '2'),
          },
          onInputCandidate: (original, candidate) {
            (names[original] ??= {}).add(candidate.name);
            quantities[candidate.name] = candidate.quantityPerCraft;
          },
        );
        expect(names['Shared Ore'], {'Shared Ore', 'Other Ore'});
        expect(quantities['Shared Ore'], 1);
      },
    );
    test(
      'explicit choice uses every ask tier, not stock times cheapest price',
      () {
        final quote = calculate(
          product: product,
          extras: extras,
          crafts: 19,
          input: marketItem('2', asks: [level(10, 5), level(100, 14)]),
          additionalMarket: {
            '3': marketItem('3', asks: [level(20, 100)]),
          },
          ingredientChoices: {'Ore': 'Ore'},
        );
        expect(quote.inputCost, 1450);
        expect(quote.ingredients.single.quantity, 19);
        expect(quote.listingProfit, closeTo(155.5, .00001));
        expect(quote.marketReady, isTrue);
      },
    );
    test('next substitutes can fill the remainder without reusing stock', () {
      final quote = calculate(
        product: product,
        extras: extras,
        crafts: 30,
        input: marketItem('2', asks: [level(10, 5), level(20, 14)]),
        additionalMarket: {
          '3': marketItem('3', asks: [level(25, 11)]),
        },
        ingredientAllocations: {
          'Ore': {'Ore': 19, 'Other Ore': 11},
        },
      );
      expect(quote.inputCost, 605);
      expect(quote.ingredients.map((input) => input.quantity), [19, 11]);
      expect(quote.marketReady, isTrue);
      expect(quote.expectedOutput, 30);
    });
    test('shared item aliases aggregate before filling order depth', () {
      final quote = calculate(
        product: recipe(
          'Product',
          ingredients: [
            ingredient('Ore', 1, options: ['Ore', 'Other Ore']),
            ingredient('Shared Ore', 1),
          ],
        ),
        extras: {
          ...extras,
          'Shared Ore': leaf('Shared Ore', id: '2'),
        },
        crafts: 3,
        input: marketItem('2', asks: [level(10, 3), level(100, 1)]),
        additionalMarket: {
          '3': marketItem('3', asks: [level(20, 100)]),
        },
        ingredientAllocations: {
          'Ore': {'Ore': 1, 'Other Ore': 2},
        },
      );
      expect(quote.inputCost, 170);
      expect(quote.ingredients.first.quantity, 4);
    });
    test(
      '10x formula splits count whole crafts and keep fixed ingredients',
      () {
        final quote = calculate(
          product: recipe(
            'Product',
            variants: [
              variant(
                'bulk',
                [
                  ingredient('Ore', 10, options: ['Ore', 'Other Ore']),
                  ingredient('Powder', 1),
                ],
                output: 10,
                batch: 10,
              ),
            ],
          ),
          extras: {...extras, 'Powder': leaf('Powder', npc: 5)},
          crafts: 3,
          input: marketItem('2', asks: [level(10, 20)]),
          additionalMarket: {
            '3': marketItem('3', asks: [level(20, 10)]),
          },
          ingredientAllocations: {
            'Ore': {'Ore': 2, 'Other Ore': 1},
          },
          extraCostPerRun: 7,
          extraCostPerCraft: 2,
        );
        expect(quote.inputCost, 415);
        expect(quote.totalCost, 428);
        expect(quote.expectedOutput, 30);
        expect(quote.ingredients.map((input) => input.quantity), [20, 10, 3]);
      },
    );
    test(
      'short or stale stock stays unavailable even with an explicit split',
      () {
        for (final item in [
          marketItem('2', asks: [level(10, 1)]),
          marketItem('2', bookTime: now.subtract(const Duration(minutes: 6))),
          marketItem('2', unknownBook: true),
        ]) {
          final quote = calculate(
            product: product,
            extras: extras,
            crafts: 3,
            input: item,
            additionalMarket: {'3': marketItem('3')},
            ingredientAllocations: {
              'Ore': {'Ore': 2, 'Other Ore': 1},
            },
          );
          expect(quote.marketReady, isFalse);
          expect(quote.inputCost, isNull);
          expect(quote.hasEstimatedInputs, isTrue);
        }
      },
    );
    test('invalid names, over-allocation and missing crafts are rejected', () {
      for (final allocation in [
        {'Ore': 1},
        {'Ore': 4},
        {'Ore': -1, 'Other Ore': 4},
        {'Not allowed': 3},
      ]) {
        final quote = calculate(
          product: product,
          extras: extras,
          crafts: 3,
          ingredientAllocations: {'Ore': allocation},
        );
        expect(quote.issues, contains(OpportunityIssue.invalidSubstitute));
        expect(quote.listingProfit, isNull);
      }
      expect(
        calculate(
          product: product,
          ingredientChoices: {'Ore': 'Not allowed'},
        ).issues,
        contains(OpportunityIssue.invalidSubstitute),
      );
    });
  });
  test('the complete production catalog is safe with no market evidence', () {
    final catalog = const BundledCatalogParser().parse(
      File('assets/data/app-data.json').readAsStringSync(),
    );
    final rules = const PlannerAssembly().plannerRules(catalog.supportingData);
    var checked = 0;
    for (final mode in CraftMode.values) {
      final recipes = catalog.forMode(mode).items;
      for (final recipe in recipes.values.where(
        (recipe) => recipe.isCraftable,
      )) {
        final quote = calculator.evaluate(
          recipe: recipe,
          recipes: recipes,
          state: _defaultState(),
          rules: rules,
          marketTax: MarketTax(valuePack: true),
          market: OpportunityMarketSnapshot(region: 'eu', items: {}),
          now: now,
        );
        expect(quote.marketReady, isFalse, reason: recipe.name);
        expect(quote.listingProfit, isNull, reason: recipe.name);
        expect(quote.buyerProfit, isNull, reason: recipe.name);
        checked++;
      }
    }
    expect(checked, greaterThan(800));
  });

  test(
    'listing and actual buyer depth never share a fictitious sale price',
    () {
      final quote = calculate(
        crafts: 2,
        output: marketItem('1', price: 100, bids: [level(80, 1), level(70, 5)]),
        input: marketItem('2', price: 10, asks: [level(12, 1), level(15, 9)]),
      );
      expect(quote.inputCost, 27);
      expect(quote.capitalNeeded, 27);
      expect(quote.listingRevenue, closeTo(169, .000001));
      expect(quote.buyerRevenue, closeTo(126.75, .000001));
      expect(quote.listingProfit, closeTo(142, .000001));
      expect(quote.buyerProfit, closeTo(99.75, .000001));
      expect(quote.buyerProfitPerCraft, closeTo(49.875, .000001));
      expect(quote.marketReady, isTrue);
      expect(quote.buyersCoverOutput, isTrue);
    },
  );

  test('partial input depth yields only a flagged current-price estimate', () {
    final quote = calculate(
      crafts: 4,
      input: marketItem('2', asks: [level(10, 3)]),
    );
    expect(quote.inputCost, isNull);
    expect(quote.listingProfit, closeTo(298, .000001));
    expect(quote.buyerProfit, closeTo(264.2, .000001));
    expect(quote.estimatedInputCost, 40);
    expect(quote.hasEstimatedInputs, isTrue);
    expect(quote.marketReady, isFalse);
    expect(quote.inputCraftCapacity, 3);
    expect(quote.inputCapacityKnown, isTrue);
    expect(quote.ingredients.single.filledQuantity, 3);
    expect(quote.issues, contains(OpportunityIssue.insufficientInputs));
  });

  test('entered run and craft costs are deducted once, after sales tax', () {
    final quote = calculate(
      crafts: 2,
      extraCostPerRun: 7,
      extraCostPerCraft: 3,
      timing: const OpportunityTimingAssumption(secondsPerCraft: 30),
    );
    expect(quote.inputCost, 20);
    expect(quote.extraCostPerRun, 7);
    expect(quote.extraCostPerCraft, 3);
    expect(quote.extraCost, 13);
    expect(quote.totalCost, 33);
    expect(quote.capitalNeeded, 33);
    expect(quote.listingRevenue, closeTo(169, .000001));
    expect(quote.buyerRevenue, closeTo(152.1, .000001));
    expect(quote.listingProfit, closeTo(136, .000001));
    expect(quote.preliminaryListingProfit, closeTo(136, .000001));
    expect(quote.buyerProfit, closeTo(119.1, .000001));
    expect(quote.listingProfitPerCraft, closeTo(68, .000001));
    expect(quote.buyerProfitPerCraft, closeTo(59.55, .000001));
    expect(quote.listingProfitPerHour, closeTo(8160, .000001));
    expect(quote.buyerProfitPerHour, closeTo(7146, .000001));
  });

  test('extra costs can turn a positive main-output margin into a loss', () {
    final quote = calculate(extraCostPerRun: 100);
    expect(quote.listingProfit, closeTo(-25.5, .000001));
    expect(quote.buyerProfit, closeTo(-33.95, .000001));
    expect(quote.marketReady, isTrue);
    expect(quote.buyersCoverOutput, isTrue);
  });

  test('unchecked input depth uses a flagged price estimate with expenses', () {
    final quote = calculate(
      extraCostPerRun: 100,
      input: marketItem('2', unknownBook: true),
    );
    expect(quote.extraCost, 100);
    expect(quote.inputCost, isNull);
    expect(quote.totalCost, 110);
    expect(quote.capitalNeeded, 110);
    expect(quote.listingProfit, closeTo(-25.5, .000001));
    expect(quote.buyerProfit, closeTo(-33.95, .000001));
    expect(quote.hasUncheckedInputDepth, isTrue);
    expect(quote.preliminaryListingProfit, closeTo(-25.5, .000001));
    expect(quote.marketReady, isFalse);
  });

  test(
    'per-craft expenses count complete formulas, not their output pieces',
    () {
      final product = recipe(
        'Product',
        variants: [
          variant('bulk', [ingredient('Ore', 10)], output: 10, batch: 10),
        ],
      );
      final quote = calculate(
        product: product,
        crafts: 4,
        extraCostPerRun: 10,
        extraCostPerCraft: 2,
      );
      expect(quote.expectedOutput, 40);
      expect(quote.extraCost, 18);
      expect(quote.totalCost, 418);
      expect(quote.listingProfit, closeTo(2962, .000001));
    },
  );

  test(
    'invalid extra costs cannot make an opportunity ready or profitable',
    () {
      for (final invalid in [-1.0, double.nan, double.infinity]) {
        for (final perCraft in [false, true]) {
          final quote = calculate(
            extraCostPerRun: perCraft ? 0 : invalid,
            extraCostPerCraft: perCraft ? invalid : 0,
          );
          expect(quote.issues, contains(OpportunityIssue.invalidExtraCost));
          expect(quote.listingProfit, isNull);
          expect(quote.buyerProfit, isNull);
          expect(quote.marketReady, isFalse);
        }
      }
      final overflow = calculate(crafts: 100, extraCostPerCraft: 1e308);
      expect(overflow.issues, contains(OpportunityIssue.invalidExtraCost));
      expect(overflow.capitalNeeded, isNull);
    },
  );

  test('route comparison includes entered expenses per unit of output', () {
    final product = recipe(
      'Product',
      variants: [
        variant('single', [ingredient('Ore', 1)]),
        variant('bulk', [ingredient('Ore', 11)], output: 10, batch: 10),
      ],
    );
    expect(calculate(product: product).selectedVariantId, 'single');
    final quote = calculate(product: product, extraCostPerRun: 10);
    expect(quote.selectedVariantId, 'bulk');
    expect(quote.extraCost, 10);
    expect(quote.inputCost, 110);
    expect(quote.totalCost, 120);
    expect(quote.listingProfit, closeTo(725, .000001));
  });

  test('summary stock does not stand in for an unknown order book', () {
    final quote = calculate(
      input: marketItem('2', stock: 999999, unknownBook: true),
    );
    expect(quote.marketReady, isFalse);
    expect(quote.inputCost, isNull);
    expect(quote.inputCapacityKnown, isFalse);
    expect(quote.preliminaryInputCost, 10);
    expect(quote.preliminaryListingProfit, closeTo(74.5, .000001));
  });

  test('an empty book is known zero, not unknown', () {
    final quote = calculate(input: marketItem('2', asks: []));
    expect(quote.inputCraftCapacity, 0);
    expect(quote.inputCapacityKnown, isTrue);
    expect(quote.marketReady, isFalse);
  });

  test('only bids at their own actual prices count', () {
    final quote = calculate(
      output: marketItem('1', price: 100, bids: [level(1, 99)]),
    );
    expect(quote.buyersCoverOutput, isTrue);
    expect(quote.buyerRevenue, closeTo(.845, .000001));
    expect(quote.buyerProfit, lessThan(0));
    expect(quote.listingProfit, greaterThan(0));
  });

  test('insufficient buyers cannot produce a full immediate-sale profit', () {
    final quote = calculate(
      crafts: 3,
      output: marketItem('1', bids: [level(90, 2)]),
    );
    expect(quote.marketReady, isTrue);
    expect(quote.buyersCoverOutput, isFalse);
    expect(quote.buyerRevenue, isNull);
    expect(quote.buyerFilledQuantity, 2);
    expect(quote.buyerCraftCapacity, 2);
  });

  test('partial cheap asks are combined with the NPC remainder', () {
    final quote = calculate(
      crafts: 5,
      npcPrice: 20,
      input: marketItem('2', asks: [level(10, 2), level(25, 99)]),
    );
    expect(quote.inputCost, 80);
    expect(quote.ingredients.single.marketQuantity, 2);
    expect(quote.ingredients.single.npcQuantity, 3);
    expect(quote.inputCraftCapacity, isNull);
    expect(quote.inputCapacityKnown, isTrue);
  });

  test('NPC-only inputs need neither quote nor stock', () {
    final quote = calculate(npcPrice: 12, omitInput: true);
    expect(quote.inputCost, 12);
    expect(quote.marketReady, isTrue);
    expect(quote.ingredients.single.npcQuantity, 1);
    expect(quote.issues, isNot(contains(OpportunityIssue.inputMarketUnknown)));
  });

  test('fresh base quote does not refresh an old book', () {
    final quote = calculate(
      input: marketItem(
        '2',
        bookTime: now.subtract(const Duration(minutes: 6)),
      ),
    );
    expect(quote.marketReady, isFalse);
    expect(quote.issues, contains(OpportunityIssue.inputBookStale));
    expect(quote.preliminaryInputCost, 10);
  });

  test('stale base quotes cannot enter preliminary profit', () {
    final quote = calculate(
      input: marketItem(
        '2',
        unknownBook: true,
        quoteTime: now.subtract(const Duration(hours: 1)),
      ),
    );
    expect(quote.preliminaryListingProfit, isNull);
  });

  test('future timestamps and wrong item identity are not valid evidence', () {
    final future = calculate(
      input: marketItem('2', bookTime: now.add(const Duration(seconds: 1))),
    );
    expect(future.marketReady, isFalse);
    final wrong = calculate(input: marketItem('99'));
    expect(wrong.inputCost, isNull);
    expect(wrong.preliminaryInputCost, isNull);
  });

  test('alias IDs aggregate stock and cost across distinct rows', () {
    final product = recipe(
      'Product',
      ingredients: [ingredient('Ore', 2), ingredient('Alias Ore', 3)],
    );
    final quote = calculate(
      product: product,
      extras: {'Alias Ore': leaf('Alias Ore', id: '0002')},
      input: marketItem('2', asks: [level(10, 4)]),
    );
    expect(quote.ingredients, hasLength(1));
    expect(quote.ingredients.single.quantity, 5);
    expect(quote.ingredients.single.originalNames, {'Ore', 'Alias Ore'});
    expect(quote.inputCost, isNull);
    expect(quote.inputCraftCapacity, 0);
  });

  test('duplicate rows consume successive ask levels once', () {
    final quote = calculate(
      product: recipe(
        'Product',
        ingredients: [ingredient('Ore', 2), ingredient('Ore', 2)],
      ),
      input: marketItem('2', asks: [level(10, 2), level(20, 2)]),
    );
    expect(quote.ingredients, hasLength(1));
    expect(quote.inputCost, 60);
  });

  test(
    'inventory and saved planner choices cannot create free repeatable profit',
    () {
      final quote = calculate(
        state: state(
          inventory: {'Ore': 100000},
          choices: {'Product': 'missing'},
        ),
      );
      expect(quote.inputCost, 10);
    },
  );

  test(
    'complete automatic variants choose the cheaper route; manual lock stays exact',
    () {
      final product = recipe(
        'Product',
        variants: [
          variant('ore', [ingredient('Ore', 5)]),
          variant('npc', [ingredient('NPC', 1)]),
        ],
      );
      final extras = {'NPC': leaf('NPC', npc: 20)};
      final automatic = calculate(
        product: product,
        extras: extras,
        state: state(choices: {'Product': 'ore'}),
      );
      expect(automatic.selectedVariantId, 'npc');
      expect(automatic.inputCost, 20);
      final manual = calculate(
        product: product,
        extras: extras,
        selectedVariantId: 'ore',
      );
      expect(manual.selectedVariantId, 'ore');
      expect(manual.inputCost, 50);
    },
  );

  test('10x formulas are not multiplied twice', () {
    final product = recipe(
      'Product',
      variants: [
        variant('single', [ingredient('Ore', 2)], output: 1),
        variant(
          'ten',
          [ingredient('Ore', 20), ingredient('Powder', 1)],
          output: 10,
          batch: 10,
        ),
      ],
    );
    final extras = {'Powder': leaf('Powder', npc: 5)};
    final single = calculate(
      product: product,
      extras: extras,
      selectedVariantId: 'single',
      crafts: 40,
    );
    final ten = calculate(
      product: product,
      extras: extras,
      selectedVariantId: 'ten',
      crafts: 4,
    );
    expect(single.expectedOutput, 40);
    expect(ten.expectedOutput, 40);
    expect(single.ingredients.single.quantity, 80);
    expect(ten.ingredients.first.quantity, 80);
    expect(ten.ingredients.last.quantity, 4);
    expect(ten.inputCost! - single.inputCost!, 20);
  });

  test(
    'automatic batch ranking compares margin per output, not bigger totals',
    () {
      final product = recipe(
        'Product',
        variants: [
          variant('single', [ingredient('Ore', 1)], output: 1),
          variant('ten', [ingredient('Ore', 30)], output: 10, batch: 10),
        ],
      );
      final automatic = calculate(product: product);
      final bulk = calculate(product: product, selectedVariantId: 'ten');
      expect(bulk.listingProfit, greaterThan(automatic.listingProfit!));
      expect(automatic.selectedVariantId, 'single');
      expect(
        automatic.listingProfit! / automatic.expectedOutput!,
        greaterThan(bulk.listingProfit! / bulk.expectedOutput!),
      );
    },
  );

  test(
    'public discovery uses normalized IDs, folded names and alias fallbacks',
    () {
      final recipes = {'Ore': leaf('Ore', id: '')};
      final rules = PlannerRules(
        marketIds: {'ORE': '0002'},
        marketNameAliases: {'Alias': 'ore'},
      );
      expect(
        calculator.marketItemId(name: 'alias', recipes: recipes, rules: rules),
        '2',
      );
      expect(
        calculator.marketItemId(name: ' ORE ', recipes: recipes, rules: rules),
        '2',
      );
    },
  );

  test('supported quality choice keeps the per-attempt ceiling', () {
    final product = recipe(
      'Product',
      type: 'cooking',
      minimum: 1,
      maximum: 1,
      ingredients: [ingredient('Ore', 6)],
    );
    final rules = PlannerRules(
      qualityConversions: const {
        'Ore': QualityConversionRule(
          special: QualityTierRule(name: 'Special Ore', ratio: 5),
        ),
      },
    );
    final quote = calculate(
      product: product,
      crafts: 3,
      rules: rules,
      extras: {'Special Ore': leaf('Special Ore', id: '3')},
      additionalMarket: {
        '3': marketItem('3', asks: [level(15, 100)]),
      },
    );
    expect(quote.ingredients.single.name, 'Special Ore');
    expect(quote.ingredients.single.quantityPerCraft, 2);
    expect(quote.ingredients.single.quantity, 6);
    expect(quote.inputCost, 90);
  });

  test(
    'processing ignores general quality replacement and uses recorded output',
    () {
      final quote = calculate(
        product: recipe(
          'Product',
          type: 'processing',
          minimum: 2,
          maximum: 4,
          ingredients: [ingredient('Ore', 6)],
        ),
        rules: PlannerRules(qualityIngredients: {'Ore'}),
        extras: {'Special Ore': leaf('Special Ore', npc: 1)},
        state: state(processingMastery: 3000),
      );
      expect(quote.ingredients.single.name, 'Ore');
      expect(quote.outputPerCraft, 3);
    },
  );

  test('fractional expected output is not rounded into additional revenue', () {
    final quote = calculate(
      product: recipe('Product', type: 'cooking', minimum: 1, maximum: 4),
      output: marketItem('1', price: 100, bids: [level(80, 2), level(60, 1)]),
    );
    expect(quote.expectedOutput, 2.5);
    expect(quote.buyerRevenue, closeTo(190 * .845, .000001));
    expect(quote.listingRevenue, closeTo(250 * .845, .000001));
  });

  test('catalog-supported substitute can win without saved choices', () {
    final quote = calculate(
      product: recipe(
        'Product',
        ingredients: [
          ingredient(
            'Ore',
            2,
            options: ['Ore', 'Other Ore'],
            ratios: {'Other Ore': 1.5},
          ),
        ],
      ),
      extras: {'Other Ore': leaf('Other Ore', id: '3')},
      additionalMarket: {
        '3': marketItem('3', asks: [level(4, 100)]),
      },
    );
    expect(quote.ingredients.single.name, 'Other Ore');
    expect(quote.ingredients.single.quantity, 3);
    expect(quote.inputCost, 12);
  });

  test(
    'book discovery includes supported alternate formulas and qualities',
    () {
      final product = recipe(
        'Product',
        type: 'cooking',
        variants: [
          variant('a', [
            ingredient('Ore', 1, options: ['Ore', 'Other Ore']),
          ], type: 'cooking'),
          variant('b', [ingredient('NPC', 1)], type: 'cooking'),
        ],
      );
      final names = calculator.marketItemNames(
        recipe: product,
        recipes: {
          'Product': product,
          'Ore': leaf('Ore'),
          'Other Ore': leaf('Other Ore'),
          'NPC': leaf('NPC'),
        },
        rules: PlannerRules(qualityIngredients: {'Ore'}),
      );
      expect(
        names,
        containsAll([
          'Product',
          'Ore',
          'Other Ore',
          'NPC',
          'Special Ore',
          'High-Quality Ore',
        ]),
      );
    },
  );

  test('NPC/base discovery never becomes confirmed executable profit', () {
    final product = recipe(
      'Product',
      variants: [
        variant('a', [ingredient('Ore', 5)]),
        variant('b', [ingredient('Other', 1)]),
      ],
    );
    final quote = calculate(
      product: product,
      input: marketItem('2', unknownBook: true),
      extras: {'Other': leaf('Other', id: '3')},
      additionalMarket: {'3': marketItem('3', price: 20, unknownBook: true)},
    );
    expect(quote.selectedVariantId, 'b');
    expect(quote.preliminaryInputCost, 20);
    expect(quote.listingProfit, closeTo(64.5, .000001));
    expect(quote.hasUncheckedInputDepth, isTrue);
    expect(quote.inputCost, isNull);
    expect(quote.marketReady, isFalse);
  });

  test('fallback prices are never accepted', () {
    final quote = calculate(
      omitInput: true,
      rules: PlannerRules(fallbackMarketPrices: {'Ore': 1}),
    );
    expect(quote.preliminaryInputCost, isNull);
    expect(quote.inputCost, isNull);
  });

  test('unlisted output is never a market opportunity', () {
    final quote = calculate(output: marketItem('1', unlisted: true));
    expect(quote.listingRevenue, isNull);
    expect(quote.buyerRevenue, isNull);
    expect(quote.marketReady, isFalse);
  });

  for (final role in [RecipeRole.manualConversion, RecipeRole.salvage]) {
    test('$role remains outside automatic crafting', () {
      final quote = calculate(product: recipe('Product', role: role));
      expect(quote.issues, contains(OpportunityIssue.recipeNotCraftable));
    });
  }

  test('legacy unavailable production recipes are excluded', () {
    final quote = calculate(
      rules: PlannerRules(legacyUnavailableItems: {'PRODUCT'}),
    );
    expect(quote.issues, contains(OpportunityIssue.recipeNotCraftable));
  });

  for (final crafts in [0, -1, 1000000001]) {
    test('invalid craft count $crafts is rejected', () {
      expect(
        calculate(crafts: crafts).issues,
        contains(OpportunityIssue.invalidQuantity),
      );
    });
  }

  test('huge/non-finite ingredients cannot overflow a run', () {
    for (final qty in [double.nan, double.infinity, 1e308, -1.0, 0.0]) {
      expect(
        calculate(
          product: recipe('Product', ingredients: [ingredient('Ore', qty)]),
        ).issues,
        contains(OpportunityIssue.invalidQuantity),
      );
    }
  });

  test('unrecognized explicit route is not silently substituted', () {
    expect(
      calculate(selectedVariantId: 'missing').issues,
      contains(OpportunityIssue.unknownVariant),
    );
  });

  test('no timing estimate is invented; measured timing includes restocks', () {
    expect(calculate().estimatedSeconds, isNull);
    final quote = calculate(
      crafts: 11,
      timing: const OpportunityTimingAssumption(
        secondsPerCraft: 2,
        setupSeconds: 30,
        refillSeconds: 10,
        craftsPerLoad: 5,
      ),
    );
    expect(quote.estimatedSeconds, 72);
    expect(
      quote.listingProfitPerHour,
      closeTo(quote.listingProfit! * 50, .000001),
    );
  });

  test('invalid timing does not erase valid material calculations', () {
    final quote = calculate(
      timing: const OpportunityTimingAssumption(secondsPerCraft: 0),
    );
    expect(quote.estimatedSeconds, isNull);
    expect(quote.listingProfitPerHour, isNull);
    expect(quote.listingProfit, isNotNull);
    expect(quote.issues, contains(OpportunityIssue.invalidTiming));
  });

  test(
    'tax applies to sale only and legacy disabled cannot create tax-free profit',
    () {
      final quote = calculate(tax: MarketTax(enabled: false));
      expect(quote.inputCost, 10);
      expect(quote.listingRevenue, 65);
    },
  );
}

OpportunityQuote calculate({
  Recipe? product,
  OpportunityMarketItem? input,
  OpportunityMarketItem? output,
  int crafts = 1,
  double npcPrice = 0,
  bool omitInput = false,
  bool omitOutput = false,
  Map<String, Recipe> extras = const {},
  Map<String, OpportunityMarketItem> additionalMarket = const {},
  PlannerRules? rules,
  ModeState? state,
  MarketTax? tax,
  String? selectedVariantId,
  OpportunityTimingAssumption? timing,
  double extraCostPerRun = 0,
  double extraCostPerCraft = 0,
  int? customSalePrice,
  Map<String, String> ingredientChoices = const {},
  Map<String, Map<String, int>> ingredientAllocations = const {},
  void Function(String, OpportunityIngredientQuote)? onInputCandidate,
  bool useInventory = false,
  bool preferAvailableInputs = false,
  Set<String> nonMarketableIds = const {},
}) {
  final selected = product ?? recipe('Product');
  return calculator.evaluate(
    recipe: selected,
    recipes: {
      selected.name: selected,
      'Ore': leaf('Ore', id: '2', npc: npcPrice),
      ...extras,
    },
    state: state ?? _defaultState(),
    rules: rules ?? PlannerRules(),
    marketTax: tax ?? MarketTax(valuePack: true),
    market: OpportunityMarketSnapshot(
      region: 'eu',
      items: {
        if (!omitOutput)
          '1': output ?? marketItem('1', price: 100, bids: [level(90, 10000)]),
        if (!omitInput) '2': input ?? marketItem('2'),
        ...additionalMarket,
      },
    ),
    now: now,
    crafts: crafts,
    selectedVariantId: selectedVariantId,
    timing: timing,
    extraCostPerRun: extraCostPerRun,
    extraCostPerCraft: extraCostPerCraft,
    customSalePrice: customSalePrice,
    ingredientChoices: ingredientChoices,
    ingredientAllocations: ingredientAllocations,
    onInputCandidate: onInputCandidate,
    useInventory: useInventory,
    preferAvailableInputs: preferAvailableInputs,
    nonMarketableIds: nonMarketableIds,
  );
}

OpportunityMarketLevel level(int price, int quantity) =>
    OpportunityMarketLevel(price: price, quantity: quantity);
OpportunityMarketItem marketItem(
  String id, {
  int price = 10,
  int stock = 10000,
  List<OpportunityMarketLevel>? asks,
  List<OpportunityMarketLevel>? bids,
  bool unknownBook = false,
  DateTime? quoteTime,
  DateTime? bookTime,
  bool unlisted = false,
}) => OpportunityMarketItem(
  itemId: id,
  basePrice: price,
  stock: stock,
  quoteFetchedAt: quoteTime ?? now,
  asks: unknownBook ? null : asks ?? [level(price, 10000)],
  bids: unknownBook ? null : bids ?? [],
  bookFetchedAt: unknownBook ? null : bookTime ?? now,
  unlisted: unlisted,
);

ModeState _defaultState() => state();
ModeState state({
  Map<String, double> inventory = const {},
  Map<String, String> choices = const {},
  int processingMastery = 0,
}) => ModeState(
  target: 'Product',
  bonusTarget: 'Product',
  inventory: inventory,
  ignoreIngredientInventory: false,
  recipeVariantChoices: choices,
  processingMastery: processingMastery,
  market: MarketState(),
  appearance: AppearanceSettings.defaultsFor(CraftMode.processing),
);

Recipe recipe(
  String name, {
  String type = 'processing',
  List<Ingredient>? ingredients,
  List<RecipeVariant> variants = const [],
  double minimum = 1,
  double maximum = 1,
  RecipeRole role = RecipeRole.production,
}) => Recipe(
  name: name,
  type: type,
  baseOutput: 1,
  group: null,
  method: 'Simple Alchemy',
  ingredients: ingredients ?? [ingredient('Ore', 1)],
  marketId: '1',
  sourceNote: null,
  vendor: null,
  location: null,
  npcPrice: 0,
  qualityBase: null,
  qualityGrade: null,
  outputMinimum: minimum,
  outputMaximum: maximum,
  role: role,
  variants: variants,
);

Recipe leaf(String name, {String? id, double npc = 0}) => Recipe(
  name: name,
  type: 'gathered',
  baseOutput: 1,
  group: null,
  method: null,
  ingredients: [],
  marketId: id,
  sourceNote: null,
  vendor: null,
  location: null,
  npcPrice: npc,
  qualityBase: null,
  qualityGrade: null,
  outputMinimum: null,
  outputMaximum: null,
);

Ingredient ingredient(
  String name,
  double quantity, {
  List<String> options = const [],
  Map<String, double> ratios = const {},
}) => Ingredient(
  name: name,
  quantity: quantity,
  options: options,
  substituteGroup: name,
  substituteRatios: ratios,
);

RecipeVariant variant(
  String id,
  List<Ingredient> ingredients, {
  double output = 1,
  int batch = 1,
  String type = 'processing',
}) => RecipeVariant(
  id: id,
  label: id,
  type: type,
  baseOutput: 1,
  method: 'Simple Alchemy',
  ingredients: ingredients,
  outputMinimum: output,
  outputMaximum: output,
  routeId: id,
  batchMultiplier: batch,
);
