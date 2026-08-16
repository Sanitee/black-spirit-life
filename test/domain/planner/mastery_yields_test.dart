import 'package:bdo_craft_planner_flutter/domain/models/catalog_models.dart';
import 'package:bdo_craft_planner_flutter/domain/planner/mastery_yields.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('mastery chance tables match the locked Avalonia data', () {
    expect(cookingMaxDishChance, hasLength(61));
    expect(alchemyMaxProcChance, hasLength(61));
    expect(
      cookingMaxDishChance.join(','),
      '0.0,12.5,13.76,15.0,16.26,17.5,18.76,20.0,21.26,22.5,'
      '23.76,25.0,26.26,27.5,28.76,30.0,31.26,32.5,33.76,34.38,'
      '35.0,35.63,36.26,36.87,37.5,38.13,38.76,39.37,40.0,40.63,'
      '41.26,41.87,42.5,43.13,43.76,44.37,45.0,45.63,46.26,53.45,'
      '61.15,61.78,62.4,63.03,63.65,64.28,64.9,65.53,66.15,66.78,'
      '67.4,68.03,68.65,69.28,69.9,70.53,71.15,71.78,72.4,73.03,'
      '73.65',
    );
    expect(
      alchemyMaxProcChance.join(','),
      '0.0,5.76,6.35,6.97,7.62,8.29,9.0,9.73,10.5,11.29,12.11,'
      '12.96,13.84,14.75,15.68,16.65,17.64,18.66,19.71,20.79,21.9,'
      '23.04,24.21,25.4,26.63,27.88,29.16,30.47,31.81,33.18,34.57,'
      '36.0,37.45,38.94,40.45,41.99,43.56,45.16,46.79,48.44,50.0,'
      '50.63,51.25,51.88,52.5,53.13,53.75,54.38,55.0,55.63,56.25,'
      '56.88,57.5,58.13,58.75,59.38,60.0,60.63,61.25,61.88,62.5',
    );
  });

  test('mastery output interpolates and clamps at locked values', () {
    expect(alchemyExpectedOutput(0, 1, 4), 2.5);
    expect(alchemyExpectedOutput(25, 1, 4), closeTo(2.5432, 1e-12));
    expect(alchemyExpectedOutput(50, 1, 4), closeTo(2.5864, 1e-12));
    expect(alchemyExpectedOutput(3000, 1, 4), closeTo(3.4375, 1e-12));
    expect(alchemyExpectedOutput(-1, 1, 4), 2.5);
    expect(alchemyExpectedOutput(3001, 1, 4), closeTo(3.4375, 1e-12));

    expect(cookingExpectedOutput(0, 1, 4), 2.5);
    expect(cookingExpectedOutput(25, 1, 4), closeTo(2.59375, 1e-12));
    expect(cookingExpectedOutput(50, 1, 4), closeTo(2.6875, 1e-12));
    expect(cookingExpectedOutput(3000, 1, 4), closeTo(3.60475, 1e-12));
  });

  test('initial alchemy yield selects the same discrete mastery point', () {
    expect(alchemyMasteryForExpectedOutput(3.2), 1900);
    expect(alchemyExpectedOutput(1900, 1, 4), closeTo(3.20185, 1e-12));
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
