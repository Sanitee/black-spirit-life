import '../models/catalog_models.dart';

// Percentage points at 50-Mastery intervals, retaining the client's precision.
// Source: cookingstatdata.bss / alchemystatdata.bss, client audit 2026-09-03.
// The displayed rates are independently confirmed by the official NA/EU patch:
// https://www.naeu.playblackdesert.com/en-US/News/Detail?groupContentNo=8046
// These are maximum-quantity chances, not special-output proc probabilities.
const List<double> cookingMaxDishChance = <double>[
  0,
  0.64,
  0.9604,
  1.3456,
  1.7956,
  2.3104,
  2.89,
  3.5344,
  4.2436,
  5.0176,
  5.8564,
  6.76,
  7.7284,
  8.7616,
  9.8596,
  11.0224,
  12.25,
  13.5424,
  14.8996,
  16.3216,
  17.8084,
  19.36,
  20.9764,
  22.6576,
  24.4036,
  26.2144,
  28.09,
  30.0304,
  32.0356,
  34.1056,
  36.2404,
  38.44,
  40.7044,
  43.0336,
  45.4276,
  47.8864,
  50.41,
  52.9984,
  55.6516,
  58.3696,
  61.1524,
  61.9172,
  62.682,
  63.4468,
  64.2116,
  64.9764,
  65.7412,
  66.506,
  67.2708,
  68.0356,
  68.8004,
  69.5652,
  70.33,
  71.0948,
  71.8596,
  72.6244,
  73.3892,
  74.154,
  74.9188,
  75.6836,
  76.45,
];

const List<double> alchemyMaxProcChance = <double>[
  0,
  5.76,
  6.3504,
  6.9696,
  7.6176,
  8.2944,
  9,
  9.7344,
  10.4976,
  11.2896,
  12.1104,
  12.96,
  13.8384,
  14.7456,
  15.6816,
  16.6464,
  17.64,
  18.6624,
  19.7136,
  20.7936,
  21.9024,
  23.04,
  24.2064,
  25.4016,
  26.6256,
  27.8784,
  29.16,
  30.4704,
  31.8096,
  33.1776,
  34.5744,
  36,
  37.4544,
  38.9376,
  40.4496,
  41.9904,
  43.56,
  45.1584,
  46.7856,
  48.4416,
  50,
  50.625,
  51.25,
  51.875,
  52.5,
  53.125,
  53.75,
  54.375,
  55,
  55.625,
  56.25,
  56.875,
  57.5,
  58.125,
  58.75,
  59.375,
  60,
  60.625,
  61.25,
  61.875,
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

/// Estimates the main result, assuming a uniform ordinary roll within the
/// catalog range and a separate Mastery maximum-quantity roll. This is an
/// average across successful recipes, not a guaranteed per-craft result. It
/// excludes special-quality results, byproducts and failed crafts.
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
