import '../models/catalog_models.dart';

const List<double> cookingMaxDishChance = <double>[
  0,
  12.5,
  13.76,
  15,
  16.26,
  17.5,
  18.76,
  20,
  21.26,
  22.5,
  23.76,
  25,
  26.26,
  27.5,
  28.76,
  30,
  31.26,
  32.5,
  33.76,
  34.38,
  35,
  35.63,
  36.26,
  36.87,
  37.5,
  38.13,
  38.76,
  39.37,
  40,
  40.63,
  41.26,
  41.87,
  42.5,
  43.13,
  43.76,
  44.37,
  45,
  45.63,
  46.26,
  53.45,
  61.15,
  61.78,
  62.4,
  63.03,
  63.65,
  64.28,
  64.9,
  65.53,
  66.15,
  66.78,
  67.4,
  68.03,
  68.65,
  69.28,
  69.9,
  70.53,
  71.15,
  71.78,
  72.4,
  73.03,
  73.65,
];

const List<double> alchemyMaxProcChance = <double>[
  0,
  5.76,
  6.35,
  6.97,
  7.62,
  8.29,
  9,
  9.73,
  10.5,
  11.29,
  12.11,
  12.96,
  13.84,
  14.75,
  15.68,
  16.65,
  17.64,
  18.66,
  19.71,
  20.79,
  21.9,
  23.04,
  24.21,
  25.4,
  26.63,
  27.88,
  29.16,
  30.47,
  31.81,
  33.18,
  34.57,
  36,
  37.45,
  38.94,
  40.45,
  41.99,
  43.56,
  45.16,
  46.79,
  48.44,
  50,
  50.63,
  51.25,
  51.88,
  52.5,
  53.13,
  53.75,
  54.38,
  55,
  55.63,
  56.25,
  56.88,
  57.5,
  58.13,
  58.75,
  59.38,
  60,
  60.63,
  61.25,
  61.88,
  62.5,
];

const Map<int, int> massProcessingBatches = <int, int>{
  2: 10,
  20: 11,
  40: 12,
  60: 13,
  80: 14,
  100: 15,
  120: 16,
  140: 17,
  160: 18,
  180: 19,
  200: 20,
  220: 21,
  240: 22,
  260: 23,
  280: 24,
  300: 25,
  320: 26,
  340: 27,
  360: 28,
  380: 29,
  400: 30,
  420: 31,
  440: 32,
  460: 33,
  480: 34,
  500: 35,
  520: 36,
  540: 37,
  560: 38,
  580: 39,
  600: 40,
  620: 41,
  640: 42,
  660: 43,
  680: 45,
  700: 47,
  720: 49,
  740: 51,
  760: 53,
  780: 57,
  810: 60,
  840: 64,
  870: 68,
  900: 72,
  930: 76,
  960: 80,
  990: 85,
  1020: 90,
  1060: 96,
  1100: 112,
  1140: 118,
  1180: 124,
  1220: 130,
  1260: 137,
  1300: 144,
  1350: 154,
  1400: 162,
  1450: 170,
  1500: 178,
  1550: 186,
  1600: 194,
  1650: 203,
  1700: 212,
  1800: 222,
  1900: 235,
  2000: 250,
  2100: 260,
  2200: 270,
  2300: 280,
  2400: 285,
  2500: 290,
  2600: 295,
  2700: 300,
  2800: 305,
  2900: 310,
  3000: 315,
};

const List<String> processingMethods = <String>[
  'Shaking',
  'Grinding',
  'Chopping',
  'Drying',
  'Heating',
  'Filtering',
  'Thinning',
  'Simple Alchemy',
  'Simple Cooking',
  'Other',
];

double masteryTableChance(List<double> table, double mastery) {
  if (table.length != 61) {
    throw ArgumentError.value(table.length, 'table', 'must have 61 entries');
  }
  if (!mastery.isFinite) {
    throw ArgumentError.value(mastery, 'mastery', 'must be finite');
  }

  final value = mastery.clamp(0, 3000).toDouble();
  final lowerIndex = (value / 50).floor();
  final upperIndex = (value / 50).ceil().clamp(0, table.length - 1).toInt();
  final fraction = upperIndex == lowerIndex
      ? 0.0
      : (value - lowerIndex * 50) / 50;
  return (table[lowerIndex] +
          (table[upperIndex] - table[lowerIndex]) * fraction) /
      100;
}

double expectedOutputWithChance({
  required double mastery,
  required double minimum,
  required double maximum,
  required List<double> chanceTable,
}) {
  if (!minimum.isFinite || !maximum.isFinite) {
    throw ArgumentError('Output bounds must be finite.');
  }
  final low = minimum < 0 ? 0.0 : minimum;
  final high = maximum < low ? low : maximum;
  final baseAverage = (low + high) / 2;
  final chance = masteryTableChance(chanceTable, mastery);
  return baseAverage * (1 - chance) + high * chance;
}

double cookingExpectedOutput(double mastery, double minimum, double maximum) =>
    expectedOutputWithChance(
      mastery: mastery,
      minimum: minimum,
      maximum: maximum,
      chanceTable: cookingMaxDishChance,
    );

double alchemyExpectedOutput(double mastery, double minimum, double maximum) =>
    expectedOutputWithChance(
      mastery: mastery,
      minimum: minimum,
      maximum: maximum,
      chanceTable: alchemyMaxProcChance,
    );

int alchemyMasteryForExpectedOutput(double output) {
  if (!output.isFinite) {
    throw ArgumentError.value(output, 'output', 'must be finite');
  }
  final target = output < 0.1 ? 0.1 : output;
  var bestMastery = 0;
  var bestDelta = double.infinity;
  for (var mastery = 0; mastery <= 3000; mastery += 50) {
    final delta = (alchemyExpectedOutput(mastery.toDouble(), 1, 4) - target)
        .abs();
    if (delta < bestDelta) {
      bestDelta = delta;
      bestMastery = mastery;
    }
  }
  return bestMastery;
}

int massProcessingBatchSize(int mastery) {
  final clamped = mastery.clamp(0, 3000);
  var batch = 1;
  for (final entry in massProcessingBatches.entries) {
    if (clamped < entry.key) {
      break;
    }
    batch = entry.value;
  }
  return batch;
}

double massProcessingBatchCount(double craftCount, int batchSize) {
  if (!craftCount.isFinite) {
    throw ArgumentError.value(craftCount, 'craftCount', 'must be finite');
  }
  if (batchSize < 1) {
    throw ArgumentError.value(batchSize, 'batchSize', 'must be positive');
  }
  if (craftCount <= 0) {
    return 0;
  }
  return (craftCount / batchSize).ceilToDouble();
}

double effectiveBaseOutput(double value) {
  if (!value.isFinite) {
    throw ArgumentError.value(value, 'value', 'must be finite');
  }
  if (value <= 0) {
    return 1;
  }
  return value < 0.0001 ? 0.0001 : value;
}

/// Returns the catalog-owned expected result of one processing recipe.
///
/// Processing Mastery controls mass-processing batch size, not the result of
/// each recipe. Most bundled recipes record their final minimum and maximum
/// output, so their expected result is the midpoint of that range. A small
/// legacy set predates explicit bounds; its [Recipe.baseOutput] values were
/// normalized around the historical 2.5 average and retain that fallback until
/// their source records are upgraded.
double processingOutputPerCraft({required Recipe recipe}) {
  final minimum = _processingOutputBound(recipe.outputMinimum);
  final maximum = _processingOutputBound(recipe.outputMaximum);
  if (minimum != null && maximum != null) {
    final high = maximum < minimum ? minimum : maximum;
    return (minimum + high) / 2;
  }
  if (minimum != null) return minimum;
  if (maximum != null) return maximum;
  return effectiveBaseOutput(recipe.baseOutput) * 2.5;
}

double? _processingOutputBound(double? value) {
  if (value == null) return null;
  if (!value.isFinite) {
    throw ArgumentError.value(value, 'output', 'must be finite');
  }
  if (value <= 0) return null;
  return value < 0.0001 ? 0.0001 : value;
}
