import 'package:bdo_craft_planner_flutter/domain/models/catalog_models.dart';
import 'package:bdo_craft_planner_flutter/domain/planner/mastery_yields.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('mastery chance tables match current client production rates', () {
    expect(cookingMaxDishChance, hasLength(61));
    expect(alchemyMaxProcChance, hasLength(61));
    expect(
      cookingMaxDishChance.join(','),
      '0.0,0.64,0.9604,1.3456,1.7956,2.3104,2.89,3.5344,4.2436,5.0176,'
      '5.8564,6.76,7.7284,8.7616,9.8596,11.0224,12.25,13.5424,14.8996,16.3216,'
      '17.8084,19.36,20.9764,22.6576,24.4036,26.2144,28.09,30.0304,32.0356,34.1056,'
      '36.2404,38.44,40.7044,43.0336,45.4276,47.8864,50.41,52.9984,55.6516,58.3696,'
      '61.1524,61.9172,62.682,63.4468,64.2116,64.9764,65.7412,66.506,67.2708,68.0356,'
      '68.8004,69.5652,70.33,71.0948,71.8596,72.6244,73.3892,74.154,74.9188,75.6836,'
      '76.45',
    );
    expect(
      alchemyMaxProcChance.join(','),
      '0.0,5.76,6.3504,6.9696,7.6176,8.2944,9.0,9.7344,10.4976,11.2896,12.1104,'
      '12.96,13.8384,14.7456,15.6816,16.6464,17.64,18.6624,19.7136,20.7936,21.9024,'
      '23.04,24.2064,25.4016,26.6256,27.8784,29.16,30.4704,31.8096,33.1776,34.5744,'
      '36.0,37.4544,38.9376,40.4496,41.9904,43.56,45.1584,46.7856,48.4416,50.0,'
      '50.625,51.25,51.875,52.5,53.125,53.75,54.375,55.0,55.625,56.25,'
      '56.875,57.5,58.125,58.75,59.375,60.0,60.625,61.25,61.875,62.5',
    );
  });

  test('official maximum-quantity anchors match both main-output formulas', () {
    for (final (mastery, cookingChance, alchemyChance) in [
      (0.0, 0.0, 0.0),
      (1000.0, .178084, .219024),
      (1900.0, .556516, .467856),
      (2000.0, .611524, .5),
      (3000.0, .7645, .625),
    ]) {
      expect(
        masteryTableChance(cookingMaxDishChance, mastery),
        closeTo(cookingChance, 1e-12),
      );
      expect(
        masteryTableChance(alchemyMaxProcChance, mastery),
        closeTo(alchemyChance, 1e-12),
      );
      expect(
        cookingExpectedOutput(mastery, 1, 4),
        closeTo(2.5 * (1 - cookingChance) + 4 * cookingChance, 1e-12),
      );
      expect(
        alchemyExpectedOutput(mastery, 1, 4),
        closeTo(2.5 * (1 - alchemyChance) + 4 * alchemyChance, 1e-12),
      );
      // An exceptional recipe range must not inherit the normal 1-4 average.
      expect(
        cookingExpectedOutput(mastery, 2, 3),
        closeTo(2.5 * (1 - cookingChance) + 3 * cookingChance, 1e-12),
      );
      expect(alchemyExpectedOutput(mastery, 1, 1), 1);
    }
  });

  test('mastery output interpolates and clamps at current values', () {
    expect(alchemyExpectedOutput(0, 1, 4), 2.5);
    expect(alchemyExpectedOutput(25, 1, 4), closeTo(2.5432, 1e-12));
    expect(alchemyExpectedOutput(50, 1, 4), closeTo(2.5864, 1e-12));
    expect(alchemyExpectedOutput(3000, 1, 4), closeTo(3.4375, 1e-12));
    expect(alchemyExpectedOutput(-1, 1, 4), 2.5);
    expect(alchemyExpectedOutput(3001, 1, 4), closeTo(3.4375, 1e-12));

    expect(cookingExpectedOutput(0, 1, 4), 2.5);
    expect(cookingExpectedOutput(25, 1, 4), closeTo(2.5048, 1e-12));
    expect(cookingExpectedOutput(50, 1, 4), closeTo(2.5096, 1e-12));
    expect(cookingExpectedOutput(3000, 1, 4), closeTo(3.64675, 1e-12));
  });

  test('initial alchemy yield selects the same discrete mastery point', () {
    expect(alchemyMasteryForExpectedOutput(3.2), 1900);
    expect(alchemyExpectedOutput(1900, 1, 4), closeTo(3.201784, 1e-12));
  });

  test('mass-processing table and every lower boundary are locked', () {
    expect(massProcessingBatches, hasLength(76));
    expect(
      massProcessingBatches.entries
          .map((entry) => '${entry.key}:${entry.value}')
          .join(','),
      '2:10,20:11,40:12,60:13,80:14,100:15,120:16,140:17,160:18,'
      '180:19,200:20,220:21,240:22,260:23,280:24,300:25,320:26,'
      '340:27,360:28,380:29,400:30,420:31,440:32,460:33,480:34,'
      '500:35,520:36,540:37,560:38,580:39,600:40,620:41,640:42,'
      '660:43,680:45,700:47,720:49,740:51,760:53,780:57,810:60,'
      '840:64,870:68,900:72,930:76,960:80,990:85,1020:90,1060:96,'
      '1100:112,1140:118,1180:124,1220:130,1260:137,1300:144,'
      '1350:154,1400:162,1450:170,1500:178,1550:186,1600:194,'
      '1650:203,1700:212,1800:222,1900:235,2000:250,2100:260,'
      '2200:270,2300:280,2400:285,2500:290,2600:295,2700:300,'
      '2800:305,2900:310,3000:315',
    );

    var previousBatch = 1;
    for (final entry in massProcessingBatches.entries) {
      expect(massProcessingBatchSize(entry.key - 1), previousBatch);
      expect(massProcessingBatchSize(entry.key), entry.value);
      previousBatch = entry.value;
    }
    expect(massProcessingBatchSize(-1), 1);
    expect(massProcessingBatchSize(3001), 315);
    expect(massProcessingBatchCount(101, 10), 11);
  });

  test('processing output is calculated from each recipe result range', () {
    expect(
      processingOutputPerCraft(
        recipe: _recipe(
          type: 'processing',
          baseOutput: 99,
          method: 'Grinding',
          outputMinimum: 1,
          outputMaximum: 4,
        ),
      ),
      2.5,
    );
    expect(
      processingOutputPerCraft(
        recipe: _recipe(
          type: 'processing',
          baseOutput: 99,
          method: 'Heating',
          outputMinimum: 2,
          outputMaximum: 2,
        ),
      ),
      2,
    );
    expect(
      processingOutputPerCraft(
        recipe: _recipe(type: 'processing', baseOutput: 2, method: 'Grinding'),
      ),
      5,
    );
  });
}

Recipe _recipe({
  required String type,
  required double baseOutput,
  required String method,
  double? outputMinimum,
  double? outputMaximum,
}) => Recipe(
  name: 'Output',
  type: type,
  baseOutput: baseOutput,
  group: null,
  method: method,
  ingredients: <Ingredient>[
    Ingredient(
      name: 'Raw',
      quantity: 1,
      options: const <String>[],
      substituteGroup: null,
      substituteRatios: const <String, double>{},
    ),
  ],
  marketId: null,
  sourceNote: null,
  vendor: null,
  location: null,
  npcPrice: 0,
  qualityBase: null,
  qualityGrade: null,
  outputMinimum: outputMinimum,
  outputMaximum: outputMaximum,
);
