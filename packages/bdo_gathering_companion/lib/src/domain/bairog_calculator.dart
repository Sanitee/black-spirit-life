import 'dart:convert';
import 'dart:math' as math;

import 'bairog_benchmarks.dart';

/// The Sep. 3, 2026 replacement for WON Dawn Crystal - Life EXP in
/// Gathering and Hunting drop tables.
const bairogEvergreenShardItemId = 821469;

/// Energy used by an ordinary gather at Gathering Professional 3 or higher.
/// The Sep. 3, 2026 update raised the no-consumption chance to 30%.
const bairogProfessionalThreePlusEnergyUsePerGather = 0.7;

/// The three gathering drop families used by Bairog Haan's public calculator.
enum BairogDropFamily { common, special, rare }

enum BairogMinigameMode {
  none('none', 0, 1),
  normal('normal', 0.05, 1.45),
  event('event', 0.10, 1.90);

  const BairogMinigameMode(
    this.storageValue,
    this.procChance,
    this.expectedYieldFactor,
  );

  final String storageValue;
  final double procChance;
  final double expectedYieldFactor;

  static BairogMinigameMode parse(Object? value) {
    final normalized = value?.toString().trim().toLowerCase();
    return values.firstWhere(
      (mode) => mode.storageValue == normalized,
      orElse: () => BairogMinigameMode.normal,
    );
  }
}

enum BairogHedgehogTier {
  none(0, 0),
  tier1(1, 0.30),
  tier2(2, 0.30),
  tier3(3, 0.40),
  tier4(4, 0.50);

  const BairogHedgehogTier(this.storageValue, this.procRate);

  final int storageValue;
  final double procRate;

  static BairogHedgehogTier parse(Object? value) {
    final tier = _asInt(value, fallback: 0);
    return values.firstWhere(
      (entry) => entry.storageValue == tier,
      orElse: () => BairogHedgehogTier.none,
    );
  }
}

enum BairogDisplayMode {
  silverPerHour('silver_hr'),
  energyDump('energy_dump');

  const BairogDisplayMode(this.storageValue);

  final String storageValue;

  static BairogDisplayMode parse(Object? value) {
    final normalized = value?.toString().trim().toLowerCase();
    return values.firstWhere(
      (mode) => mode.storageValue == normalized,
      orElse: () => BairogDisplayMode.silverPerHour,
    );
  }
}

class BairogMasteryBonuses {
  const BairogMasteryBonuses({
    required this.commonRatePercent,
    required this.commonAmountPercent,
    required this.specialRatePercent,
    required this.specialAmountPercent,
    required this.rareRatePercent,
    required this.rareAmountPercent,
  });

  final double commonRatePercent;
  final double commonAmountPercent;
  final double specialRatePercent;
  final double specialAmountPercent;
  final double rareRatePercent;
  final double rareAmountPercent;

  double ratePercentFor(BairogDropFamily family) => switch (family) {
    BairogDropFamily.common => commonRatePercent,
    BairogDropFamily.special => specialRatePercent,
    BairogDropFamily.rare => rareRatePercent,
  };

  double amountPercentFor(BairogDropFamily family) => switch (family) {
    BairogDropFamily.common => commonAmountPercent,
    BairogDropFamily.special => specialAmountPercent,
    BairogDropFamily.rare => rareAmountPercent,
  };
}

/// Exact 50-mastery lookup published in the current BDO Workshop client.
const bairogMasteryBonuses = <int, BairogMasteryBonuses>{
  0: BairogMasteryBonuses(
    commonRatePercent: 0,
    commonAmountPercent: 0,
    specialRatePercent: 0,
    specialAmountPercent: 0,
    rareRatePercent: 0,
    rareAmountPercent: 0,
  ),
  50: BairogMasteryBonuses(
    commonRatePercent: 0,
    commonAmountPercent: 16,
    specialRatePercent: 8,
    specialAmountPercent: 4,
    rareRatePercent: 10,
    rareAmountPercent: 3.33,
  ),
  100: BairogMasteryBonuses(
    commonRatePercent: 80,
    commonAmountPercent: 19.8,
    specialRatePercent: 9.9,
    specialAmountPercent: 4.95,
    rareRatePercent: 12.38,
    rareAmountPercent: 4.13,
  ),
  150: BairogMasteryBonuses(
    commonRatePercent: 80,
    commonAmountPercent: 23.99,
    specialRatePercent: 11.99,
    specialAmountPercent: 6,
    rareRatePercent: 14.99,
    rareAmountPercent: 5,
  ),
  200: BairogMasteryBonuses(
    commonRatePercent: 80,
    commonAmountPercent: 28.56,
    specialRatePercent: 14.28,
    specialAmountPercent: 7.14,
    rareRatePercent: 17.85,
    rareAmountPercent: 5.95,
  ),
  250: BairogMasteryBonuses(
    commonRatePercent: 80,
    commonAmountPercent: 33.49,
    specialRatePercent: 16.75,
    specialAmountPercent: 8.37,
    rareRatePercent: 20.93,
    rareAmountPercent: 6.98,
  ),
  300: BairogMasteryBonuses(
    commonRatePercent: 80,
    commonAmountPercent: 38.8,
    specialRatePercent: 19.4,
    specialAmountPercent: 9.7,
    rareRatePercent: 24.25,
    rareAmountPercent: 8.08,
  ),
  350: BairogMasteryBonuses(
    commonRatePercent: 80,
    commonAmountPercent: 44.47,
    specialRatePercent: 22.23,
    specialAmountPercent: 11.12,
    rareRatePercent: 27.79,
    rareAmountPercent: 9.26,
  ),
  400: BairogMasteryBonuses(
    commonRatePercent: 80,
    commonAmountPercent: 50.49,
    specialRatePercent: 25.25,
    specialAmountPercent: 12.62,
    rareRatePercent: 31.56,
    rareAmountPercent: 10.52,
  ),
  450: BairogMasteryBonuses(
    commonRatePercent: 80,
    commonAmountPercent: 56.87,
    specialRatePercent: 28.43,
    specialAmountPercent: 14.22,
    rareRatePercent: 35.54,
    rareAmountPercent: 11.85,
  ),
  500: BairogMasteryBonuses(
    commonRatePercent: 80,
    commonAmountPercent: 63.59,
    specialRatePercent: 31.8,
    specialAmountPercent: 15.9,
    rareRatePercent: 39.74,
    rareAmountPercent: 13.25,
  ),
  550: BairogMasteryBonuses(
    commonRatePercent: 80,
    commonAmountPercent: 70.65,
    specialRatePercent: 35.33,
    specialAmountPercent: 17.66,
    rareRatePercent: 44.16,
    rareAmountPercent: 14.72,
  ),
  600: BairogMasteryBonuses(
    commonRatePercent: 80,
    commonAmountPercent: 78.05,
    specialRatePercent: 39.02,
    specialAmountPercent: 19.51,
    rareRatePercent: 48.78,
    rareAmountPercent: 16.26,
  ),
  650: BairogMasteryBonuses(
    commonRatePercent: 80,
    commonAmountPercent: 85.77,
    specialRatePercent: 42.89,
    specialAmountPercent: 21.44,
    rareRatePercent: 53.61,
    rareAmountPercent: 17.87,
  ),
  700: BairogMasteryBonuses(
    commonRatePercent: 80,
    commonAmountPercent: 93.82,
    specialRatePercent: 46.91,
    specialAmountPercent: 23.46,
    rareRatePercent: 58.64,
    rareAmountPercent: 19.55,
  ),
  750: BairogMasteryBonuses(
    commonRatePercent: 80,
    commonAmountPercent: 102.19,
    specialRatePercent: 51.09,
    specialAmountPercent: 25.55,
    rareRatePercent: 63.87,
    rareAmountPercent: 21.29,
  ),
  800: BairogMasteryBonuses(
    commonRatePercent: 80,
    commonAmountPercent: 110.87,
    specialRatePercent: 55.44,
    specialAmountPercent: 27.72,
    rareRatePercent: 69.29,
    rareAmountPercent: 23.1,
  ),
  850: BairogMasteryBonuses(
    commonRatePercent: 80,
    commonAmountPercent: 119.86,
    specialRatePercent: 59.93,
    specialAmountPercent: 29.96,
    rareRatePercent: 74.91,
    rareAmountPercent: 24.97,
  ),
  900: BairogMasteryBonuses(
    commonRatePercent: 80,
    commonAmountPercent: 129.15,
    specialRatePercent: 64.57,
    specialAmountPercent: 32.29,
    rareRatePercent: 80.72,
    rareAmountPercent: 26.91,
  ),
  950: BairogMasteryBonuses(
    commonRatePercent: 80,
    commonAmountPercent: 138.74,
    specialRatePercent: 69.37,
    specialAmountPercent: 34.68,
    rareRatePercent: 86.71,
    rareAmountPercent: 28.9,
  ),
  1000: BairogMasteryBonuses(
    commonRatePercent: 80,
    commonAmountPercent: 148.62,
    specialRatePercent: 74.31,
    specialAmountPercent: 37.15,
    rareRatePercent: 92.89,
    rareAmountPercent: 30.96,
  ),
  1050: BairogMasteryBonuses(
    commonRatePercent: 80,
    commonAmountPercent: 158.79,
    specialRatePercent: 79.39,
    specialAmountPercent: 39.7,
    rareRatePercent: 99.24,
    rareAmountPercent: 33.08,
  ),
  1100: BairogMasteryBonuses(
    commonRatePercent: 80,
    commonAmountPercent: 169.23,
    specialRatePercent: 84.62,
    specialAmountPercent: 42.31,
    rareRatePercent: 105.77,
    rareAmountPercent: 35.26,
  ),
  1150: BairogMasteryBonuses(
    commonRatePercent: 80,
    commonAmountPercent: 179.96,
    specialRatePercent: 89.98,
    specialAmountPercent: 44.99,
    rareRatePercent: 112.47,
    rareAmountPercent: 37.49,
  ),
  1200: BairogMasteryBonuses(
    commonRatePercent: 80,
    commonAmountPercent: 190.96,
    specialRatePercent: 95.48,
    specialAmountPercent: 47.74,
    rareRatePercent: 119.35,
    rareAmountPercent: 39.78,
  ),
  1250: BairogMasteryBonuses(
    commonRatePercent: 80,
    commonAmountPercent: 202.22,
    specialRatePercent: 101.11,
    specialAmountPercent: 50.55,
    rareRatePercent: 126.39,
    rareAmountPercent: 42.13,
  ),
  1300: BairogMasteryBonuses(
    commonRatePercent: 80,
    commonAmountPercent: 213.74,
    specialRatePercent: 106.87,
    specialAmountPercent: 53.44,
    rareRatePercent: 133.59,
    rareAmountPercent: 44.53,
  ),
  1350: BairogMasteryBonuses(
    commonRatePercent: 80,
    commonAmountPercent: 225.53,
    specialRatePercent: 112.76,
    specialAmountPercent: 56.38,
    rareRatePercent: 140.95,
    rareAmountPercent: 46.98,
  ),
  1400: BairogMasteryBonuses(
    commonRatePercent: 80,
    commonAmountPercent: 237.56,
    specialRatePercent: 118.78,
    specialAmountPercent: 59.39,
    rareRatePercent: 148.47,
    rareAmountPercent: 49.49,
  ),
  1450: BairogMasteryBonuses(
    commonRatePercent: 80,
    commonAmountPercent: 249.84,
    specialRatePercent: 124.92,
    specialAmountPercent: 62.46,
    rareRatePercent: 156.15,
    rareAmountPercent: 52.05,
  ),
  1500: BairogMasteryBonuses(
    commonRatePercent: 80,
    commonAmountPercent: 262.36,
    specialRatePercent: 131.18,
    specialAmountPercent: 65.59,
    rareRatePercent: 163.97,
    rareAmountPercent: 54.66,
  ),
  1550: BairogMasteryBonuses(
    commonRatePercent: 80,
    commonAmountPercent: 275.11,
    specialRatePercent: 137.56,
    specialAmountPercent: 68.78,
    rareRatePercent: 171.94,
    rareAmountPercent: 57.31,
  ),
  1600: BairogMasteryBonuses(
    commonRatePercent: 80,
    commonAmountPercent: 288.1,
    specialRatePercent: 144.05,
    specialAmountPercent: 72.02,
    rareRatePercent: 180.06,
    rareAmountPercent: 60.02,
  ),
  1650: BairogMasteryBonuses(
    commonRatePercent: 80,
    commonAmountPercent: 301.31,
    specialRatePercent: 150.66,
    specialAmountPercent: 75.33,
    rareRatePercent: 188.32,
    rareAmountPercent: 62.77,
  ),
  1700: BairogMasteryBonuses(
    commonRatePercent: 80,
    commonAmountPercent: 314.75,
    specialRatePercent: 157.38,
    specialAmountPercent: 78.69,
    rareRatePercent: 196.72,
    rareAmountPercent: 65.57,
  ),
  1750: BairogMasteryBonuses(
    commonRatePercent: 80,
    commonAmountPercent: 328.4,
    specialRatePercent: 164.2,
    specialAmountPercent: 82.1,
    rareRatePercent: 205.25,
    rareAmountPercent: 68.42,
  ),
  1800: BairogMasteryBonuses(
    commonRatePercent: 80,
    commonAmountPercent: 342.27,
    specialRatePercent: 171.13,
    specialAmountPercent: 85.57,
    rareRatePercent: 213.92,
    rareAmountPercent: 71.31,
  ),
  1850: BairogMasteryBonuses(
    commonRatePercent: 80,
    commonAmountPercent: 356.34,
    specialRatePercent: 178.17,
    specialAmountPercent: 89.09,
    rareRatePercent: 222.71,
    rareAmountPercent: 74.24,
  ),
  1900: BairogMasteryBonuses(
    commonRatePercent: 80,
    commonAmountPercent: 370.62,
    specialRatePercent: 185.31,
    specialAmountPercent: 92.65,
    rareRatePercent: 231.64,
    rareAmountPercent: 77.21,
  ),
  1950: BairogMasteryBonuses(
    commonRatePercent: 80,
    commonAmountPercent: 385.09,
    specialRatePercent: 192.54,
    specialAmountPercent: 96.27,
    rareRatePercent: 240.68,
    rareAmountPercent: 80.23,
  ),
  2000: BairogMasteryBonuses(
    commonRatePercent: 80,
    commonAmountPercent: 400,
    specialRatePercent: 200,
    specialAmountPercent: 100,
    rareRatePercent: 249.85,
    rareAmountPercent: 85,
  ),
  2050: BairogMasteryBonuses(
    commonRatePercent: 80,
    commonAmountPercent: 404.49,
    specialRatePercent: 202.24,
    specialAmountPercent: 101.12,
    rareRatePercent: 252.81,
    rareAmountPercent: 85.97,
  ),
  2100: BairogMasteryBonuses(
    commonRatePercent: 80,
    commonAmountPercent: 409.25,
    specialRatePercent: 204.62,
    specialAmountPercent: 102.31,
    rareRatePercent: 255.78,
    rareAmountPercent: 86.96,
  ),
  2150: BairogMasteryBonuses(
    commonRatePercent: 80,
    commonAmountPercent: 414.04,
    specialRatePercent: 207.02,
    specialAmountPercent: 103.51,
    rareRatePercent: 258.77,
    rareAmountPercent: 87.96,
  ),
  2200: BairogMasteryBonuses(
    commonRatePercent: 80,
    commonAmountPercent: 418.85,
    specialRatePercent: 209.43,
    specialAmountPercent: 104.71,
    rareRatePercent: 261.78,
    rareAmountPercent: 88.96,
  ),
  2250: BairogMasteryBonuses(
    commonRatePercent: 80,
    commonAmountPercent: 423.7,
    specialRatePercent: 211.85,
    specialAmountPercent: 105.92,
    rareRatePercent: 264.81,
    rareAmountPercent: 89.97,
  ),
  2300: BairogMasteryBonuses(
    commonRatePercent: 80,
    commonAmountPercent: 428.57,
    specialRatePercent: 214.28,
    specialAmountPercent: 107.14,
    rareRatePercent: 267.86,
    rareAmountPercent: 90.99,
  ),
  2350: BairogMasteryBonuses(
    commonRatePercent: 80,
    commonAmountPercent: 433.47,
    specialRatePercent: 216.73,
    specialAmountPercent: 108.37,
    rareRatePercent: 270.92,
    rareAmountPercent: 92.01,
  ),
  2400: BairogMasteryBonuses(
    commonRatePercent: 80,
    commonAmountPercent: 438.4,
    specialRatePercent: 219.2,
    specialAmountPercent: 109.6,
    rareRatePercent: 274,
    rareAmountPercent: 93.03,
  ),
  2450: BairogMasteryBonuses(
    commonRatePercent: 80,
    commonAmountPercent: 443.35,
    specialRatePercent: 221.68,
    specialAmountPercent: 110.84,
    rareRatePercent: 277.09,
    rareAmountPercent: 94.06,
  ),
  2500: BairogMasteryBonuses(
    commonRatePercent: 80,
    commonAmountPercent: 448.33,
    specialRatePercent: 224.17,
    specialAmountPercent: 112.08,
    rareRatePercent: 280.21,
    rareAmountPercent: 95.1,
  ),
  2550: BairogMasteryBonuses(
    commonRatePercent: 80,
    commonAmountPercent: 453.35,
    specialRatePercent: 226.67,
    specialAmountPercent: 113.34,
    rareRatePercent: 283.34,
    rareAmountPercent: 96.15,
  ),
  2600: BairogMasteryBonuses(
    commonRatePercent: 80,
    commonAmountPercent: 458.38,
    specialRatePercent: 229.19,
    specialAmountPercent: 114.6,
    rareRatePercent: 286.49,
    rareAmountPercent: 97.2,
  ),
  2650: BairogMasteryBonuses(
    commonRatePercent: 80,
    commonAmountPercent: 463.45,
    specialRatePercent: 231.73,
    specialAmountPercent: 115.86,
    rareRatePercent: 289.66,
    rareAmountPercent: 98.25,
  ),
  2700: BairogMasteryBonuses(
    commonRatePercent: 80,
    commonAmountPercent: 468.54,
    specialRatePercent: 234.27,
    specialAmountPercent: 117.14,
    rareRatePercent: 292.84,
    rareAmountPercent: 99.31,
  ),
  2750: BairogMasteryBonuses(
    commonRatePercent: 80,
    commonAmountPercent: 473.67,
    specialRatePercent: 236.83,
    specialAmountPercent: 118.42,
    rareRatePercent: 296.04,
    rareAmountPercent: 100.38,
  ),
  2800: BairogMasteryBonuses(
    commonRatePercent: 80,
    commonAmountPercent: 478.82,
    specialRatePercent: 239.41,
    specialAmountPercent: 119.7,
    rareRatePercent: 299.26,
    rareAmountPercent: 101.45,
  ),
  2850: BairogMasteryBonuses(
    commonRatePercent: 80,
    commonAmountPercent: 484,
    specialRatePercent: 242,
    specialAmountPercent: 121,
    rareRatePercent: 302.5,
    rareAmountPercent: 102.53,
  ),
  2900: BairogMasteryBonuses(
    commonRatePercent: 80,
    commonAmountPercent: 489.2,
    specialRatePercent: 244.6,
    specialAmountPercent: 122.3,
    rareRatePercent: 305.75,
    rareAmountPercent: 103.62,
  ),
  2950: BairogMasteryBonuses(
    commonRatePercent: 80,
    commonAmountPercent: 494.44,
    specialRatePercent: 247.22,
    specialAmountPercent: 123.61,
    rareRatePercent: 309.02,
    rareAmountPercent: 104.71,
  ),
  3000: BairogMasteryBonuses(
    commonRatePercent: 80,
    commonAmountPercent: 500,
    specialRatePercent: 250,
    specialAmountPercent: 125,
    rareRatePercent: 312.31,
    rareAmountPercent: 105.8,
  ),
};

int bairogMasteryTier(num mastery) =>
    ((mastery.clamp(0, 3000).floor()) ~/ 50) * 50;

BairogMasteryBonuses bairogBonusesForMastery(num mastery) =>
    bairogMasteryBonuses[bairogMasteryTier(mastery)]!;

class BairogEnergyExpense {
  const BairogEnergyExpense({
    required this.bdoItemId,
    required this.name,
    required this.recoveryPerHour,
    required this.energyBoost,
    this.usesPerHour,
    this.durationHours,
  }) : assert(usesPerHour != null || durationHours != null);

  final int bdoItemId;
  final String name;
  final double recoveryPerHour;
  final double energyBoost;
  final double? usesPerHour;
  final double? durationHours;
}

const bairogEnergyExpenses = <BairogEnergyExpense>[
  BairogEnergyExpense(
    bdoItemId: 589,
    name: 'Energy Potion (Extra Large)',
    recoveryPerHour: 275,
    energyBoost: 0,
    usesPerHour: 6,
  ),
  BairogEnergyExpense(
    bdoItemId: 820150,
    name: 'Miraculous Herbal Medicine',
    recoveryPerHour: 600,
    energyBoost: 500,
    durationHours: 1,
  ),
  BairogEnergyExpense(
    bdoItemId: 821144,
    name: 'Mystical Herbal Medicine',
    recoveryPerHour: 1000,
    energyBoost: 0,
    durationHours: 3,
  ),
  BairogEnergyExpense(
    bdoItemId: 821145,
    name: 'Mellow Herbal Medicine',
    recoveryPerHour: 600,
    energyBoost: 0,
    durationHours: 3,
  ),
];

class BairogCalculatorSettings {
  const BairogCalculatorSettings({
    this.mastery = 2000,
    this.gatheringDropRatePercent = 60,
    this.minigameMode = BairogMinigameMode.normal,
    this.hedgehogTier = BairogHedgehogTier.none,
    this.agrisEnabled = false,
    this.enabledExpenseItemIds = const <int>{589},
    this.displayMode = BairogDisplayMode.silverPerHour,
    this.yourEnergy = 500,
    this.naturalEnergyRecoveryPerThreeMinutes = 3,
    this.includeAfuaru = true,
    this.includeChest = true,
    this.includeChestX10 = false,
    this.includeFeverTime = true,
    this.includeEvergreenShard = true,
    this.showTaxed = true,
    this.marketNetRate = 0.845,
    this.dropTaxed = const <int, bool>{},
    this.hiddenDropItemTypeIds = const <int>{},
    this.customGathersPerHour = const <int, int>{},
    this.customItemPrices = const <int, double>{},
  });

  static const schemaVersion = 2;

  final int mastery;
  final double gatheringDropRatePercent;
  final BairogMinigameMode minigameMode;
  final BairogHedgehogTier hedgehogTier;
  final bool agrisEnabled;
  final Set<int> enabledExpenseItemIds;
  final BairogDisplayMode displayMode;
  final double yourEnergy;
  final double naturalEnergyRecoveryPerThreeMinutes;
  final bool includeAfuaru;
  final bool includeChest;
  final bool includeChestX10;
  final bool includeFeverTime;
  final bool includeEvergreenShard;
  final bool showTaxed;
  final double marketNetRate;
  final Map<int, bool> dropTaxed;
  final Set<int> hiddenDropItemTypeIds;
  final Map<int, int> customGathersPerHour;
  final Map<int, double> customItemPrices;

  factory BairogCalculatorSettings.fromJsonString(String source) {
    final decoded = jsonDecode(source);
    if (decoded is! Map) {
      throw const FormatException(
        'Bairog calculator settings must be an object.',
      );
    }
    return BairogCalculatorSettings.fromJson(decoded.cast<String, dynamic>());
  }

  factory BairogCalculatorSettings.fromJson(Map<String, dynamic> json) {
    const knownExpenses = <int>{589, 820150, 821144, 821145};
    final expenses = <int>{};
    final rawExpenses = json['expensesEnabled'];
    if (rawExpenses is Map) {
      for (final entry in rawExpenses.entries) {
        final id = int.tryParse(entry.key.toString());
        if (id != null && knownExpenses.contains(id) && _asBool(entry.value)) {
          expenses.add(id);
        }
      }
    } else if (json['enabledExpenseItemIds'] is List) {
      for (final value in json['enabledExpenseItemIds'] as List) {
        final id = _nullableInt(value);
        if (id != null && knownExpenses.contains(id)) expenses.add(id);
      }
    } else {
      expenses.add(589);
    }

    final mastery = _asInt(json['mastery'], fallback: 2000).clamp(0, 3000);
    return BairogCalculatorSettings(
      mastery: mastery,
      gatheringDropRatePercent: _finiteNonNegative(
        json['additionalDroprateBonus'] ?? json['gatheringDropRatePercent'],
        60,
      ),
      minigameMode: BairogMinigameMode.parse(json['minigameMode']),
      hedgehogTier: BairogHedgehogTier.parse(json['hedgehogTier']),
      agrisEnabled: _asBool(json['agrisEnabled']),
      enabledExpenseItemIds: Set<int>.unmodifiable(expenses),
      displayMode: BairogDisplayMode.parse(json['displayMode']),
      yourEnergy: _finiteNonNegative(json['yourEnergy'], 500),
      naturalEnergyRecoveryPerThreeMinutes: _finiteNonNegative(
        json['energyRecovery'] ?? json['naturalEnergyRecoveryPerThreeMinutes'],
        3,
      ),
      includeAfuaru: _asBool(json['includeAfuaru'], fallback: true),
      includeChest: _asBool(json['includeChest'], fallback: true),
      includeChestX10: _asBool(json['includeChestX10']),
      includeFeverTime: _asBool(json['includeFeverTime'], fallback: true),
      includeEvergreenShard: _asBool(
        json['includeEvergreenShard'] ?? json['includeWonCrystal'],
        fallback: true,
      ),
      showTaxed: _asBool(json['showTaxed'], fallback: true),
      marketNetRate: _finiteClamped(json['marketNetRate'], 0.845, 0, 1),
      dropTaxed: Map<int, bool>.unmodifiable(_boolMap(json['dropTaxed'])),
      hiddenDropItemTypeIds: Set<int>.unmodifiable(
        _enabledIds(json['hiddenDropIds'] ?? json['hiddenDropItemTypeIds']),
      ),
      customGathersPerHour: Map<int, int>.unmodifiable(
        _positiveIntMap(json['customGathersPerHour']),
      ),
      customItemPrices: Map<int, double>.unmodifiable(
        _nonNegativeDoubleMap(json['customItemPrices']),
      ),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'schemaVersion': schemaVersion,
    'mastery': mastery.clamp(0, 3000),
    'additionalDroprateBonus': _validNonNegative(gatheringDropRatePercent, 60),
    'minigameMode': minigameMode.storageValue,
    'hedgehogTier': hedgehogTier.storageValue,
    'agrisEnabled': agrisEnabled,
    'expensesEnabled': <String, bool>{
      for (final expense in bairogEnergyExpenses)
        '${expense.bdoItemId}': enabledExpenseItemIds.contains(
          expense.bdoItemId,
        ),
    },
    'displayMode': displayMode.storageValue,
    'yourEnergy': _validNonNegative(yourEnergy, 500),
    'energyRecovery': _validNonNegative(
      naturalEnergyRecoveryPerThreeMinutes,
      3,
    ),
    'includeAfuaru': includeAfuaru,
    'includeChest': includeChest,
    'includeChestX10': includeChestX10,
    'includeFeverTime': includeFeverTime,
    'includeEvergreenShard': includeEvergreenShard,
    'showTaxed': showTaxed,
    'marketNetRate': _validClamped(marketNetRate, 0.845, 0, 1),
    'dropTaxed': _sortedStringMap(dropTaxed),
    'hiddenDropIds': <String, bool>{
      for (final id in hiddenDropItemTypeIds.toList()..sort()) '$id': true,
    },
    'customGathersPerHour': <String, String>{
      for (final entry
          in customGathersPerHour.entries.toList()
            ..sort((a, b) => a.key.compareTo(b.key)))
        '${entry.key}': '${entry.value}',
    },
    'customItemPrices': _sortedStringMap(customItemPrices),
  };

  String toJsonString() => jsonEncode(toJson());

  /// Whether every persisted calculator input has the same effective value.
  ///
  /// Setup drafts are rebuilt as new objects while the user edits the dialog,
  /// so identity cannot tell the host whether applying the draft actually
  /// changed anything.
  bool hasSameValuesAs(BairogCalculatorSettings other) =>
      identical(this, other) || toJsonString() == other.toJsonString();

  BairogCalculatorSettings copyWith({
    int? mastery,
    double? gatheringDropRatePercent,
    BairogMinigameMode? minigameMode,
    BairogHedgehogTier? hedgehogTier,
    bool? agrisEnabled,
    Set<int>? enabledExpenseItemIds,
    BairogDisplayMode? displayMode,
    double? yourEnergy,
    double? naturalEnergyRecoveryPerThreeMinutes,
    bool? includeAfuaru,
    bool? includeChest,
    bool? includeChestX10,
    bool? includeFeverTime,
    bool? includeEvergreenShard,
    bool? showTaxed,
    double? marketNetRate,
    Map<int, bool>? dropTaxed,
    Set<int>? hiddenDropItemTypeIds,
    Map<int, int>? customGathersPerHour,
    Map<int, double>? customItemPrices,
  }) => BairogCalculatorSettings(
    mastery: mastery ?? this.mastery,
    gatheringDropRatePercent:
        gatheringDropRatePercent ?? this.gatheringDropRatePercent,
    minigameMode: minigameMode ?? this.minigameMode,
    hedgehogTier: hedgehogTier ?? this.hedgehogTier,
    agrisEnabled: agrisEnabled ?? this.agrisEnabled,
    enabledExpenseItemIds: enabledExpenseItemIds ?? this.enabledExpenseItemIds,
    displayMode: displayMode ?? this.displayMode,
    yourEnergy: yourEnergy ?? this.yourEnergy,
    naturalEnergyRecoveryPerThreeMinutes:
        naturalEnergyRecoveryPerThreeMinutes ??
        this.naturalEnergyRecoveryPerThreeMinutes,
    includeAfuaru: includeAfuaru ?? this.includeAfuaru,
    includeChest: includeChest ?? this.includeChest,
    includeChestX10: includeChestX10 ?? this.includeChestX10,
    includeFeverTime: includeFeverTime ?? this.includeFeverTime,
    includeEvergreenShard: includeEvergreenShard ?? this.includeEvergreenShard,
    showTaxed: showTaxed ?? this.showTaxed,
    marketNetRate: marketNetRate ?? this.marketNetRate,
    dropTaxed: dropTaxed ?? this.dropTaxed,
    hiddenDropItemTypeIds: hiddenDropItemTypeIds ?? this.hiddenDropItemTypeIds,
    customGathersPerHour: customGathersPerHour ?? this.customGathersPerHour,
    customItemPrices: customItemPrices ?? this.customItemPrices,
  );
}

class BairogCalculatorSource {
  const BairogCalculatorSource({
    required this.creator,
    required this.publisher,
    required this.url,
    required this.capturedAtUtc,
    required this.siteVersion,
    required this.note,
  });

  final String creator;
  final String publisher;
  final Uri url;
  final DateTime capturedAtUtc;
  final String siteVersion;
  final String note;
}

class BairogBdoItem {
  const BairogBdoItem({
    required this.id,
    required this.name,
    required this.icon,
  });

  final int id;
  final String name;
  final String icon;
}

class BairogGatheringItemType {
  const BairogGatheringItemType({
    required this.id,
    required this.family,
    required this.procsWithMinigame,
    required this.procsWithHedgehog,
    required this.multiDropFactor,
    required this.globalDrop,
    required this.affectedByAgris,
    required this.isPrimary,
    required this.vendorUnitPrice,
    required this.item,
  });

  final int id;
  final BairogDropFamily family;
  final bool procsWithMinigame;
  final bool procsWithHedgehog;
  final double multiDropFactor;
  final bool globalDrop;
  final bool affectedByAgris;
  final bool isPrimary;
  final double? vendorUnitPrice;
  final BairogBdoItem item;
}

class BairogGatheringType {
  const BairogGatheringType({
    required this.id,
    required this.name,
    required this.categoryId,
    required this.hasAfuaru,
    required this.agrisPerGather,
    required this.afuaruSpawnRate,
    required this.afuaruAverageItems,
    required this.afuaruItemAverages,
    required this.chestSpawnRate,
    required this.chestItemAverages,
    required this.feverTimeSpawnRate,
    required this.feverTimeItemAverages,
  });

  final int id;
  final String name;
  final int categoryId;
  final bool hasAfuaru;
  final double? agrisPerGather;
  final double? afuaruSpawnRate;
  final double? afuaruAverageItems;
  final Map<int, double> afuaruItemAverages;
  final double? chestSpawnRate;
  final Map<int, double> chestItemAverages;
  final double? feverTimeSpawnRate;
  final Map<int, double> feverTimeItemAverages;
}

class BairogDropRate {
  const BairogDropRate({
    required this.id,
    required this.itemTypeId,
    required this.gatheringTypeId,
    required this.dropRate,
    required this.dropAmount,
    required this.dropMin,
    required this.dropMax,
  });

  final int id;
  final int itemTypeId;
  final int gatheringTypeId;
  final double dropRate;
  final double dropAmount;
  final double? dropMin;
  final double? dropMax;

  BairogDropRate withDropAmount(double value) => BairogDropRate(
    id: id,
    itemTypeId: itemTypeId,
    gatheringTypeId: gatheringTypeId,
    dropRate: value == 0 ? 0 : dropRate,
    dropAmount: value,
    dropMin: dropMin,
    dropMax: dropMax,
  );
}

class BairogGatheringTypeRatio {
  const BairogGatheringTypeRatio({
    required this.gatheringTypeId,
    required this.ratio,
  });

  final int gatheringTypeId;
  final double ratio;
}

class BairogRotation {
  const BairogRotation({
    required this.id,
    required this.name,
    required this.videoUrl,
    required this.gatheringTypeId,
    required this.averageGathersPerHour,
    required this.sessionCount,
    required this.totalHours,
    required this.typeRatios,
    required this.primaryItemRatios,
  });

  final int id;
  final String name;
  final Uri videoUrl;
  final int gatheringTypeId;
  final int averageGathersPerHour;
  final int sessionCount;
  final double totalHours;
  final List<BairogGatheringTypeRatio> typeRatios;
  final Map<int, double>? primaryItemRatios;
}

class BairogCalculatorData {
  BairogCalculatorData._({
    required this.source,
    required List<BairogGatheringType> gatheringTypes,
    required List<BairogGatheringItemType> gatheringItemTypes,
    required List<BairogDropRate> dropRates,
    required List<BairogRotation> rotations,
  }) : gatheringTypes = List.unmodifiable(gatheringTypes),
       gatheringItemTypes = List.unmodifiable(gatheringItemTypes),
       dropRates = List.unmodifiable(dropRates),
       rotations = List.unmodifiable(rotations),
       gatheringTypesById = Map.unmodifiable({
         for (final row in gatheringTypes) row.id: row,
       }),
       gatheringItemTypesById = Map.unmodifiable({
         for (final row in gatheringItemTypes) row.id: row,
       }),
       rotationsById = Map.unmodifiable({
         for (final row in rotations) row.id: row,
       });

  final BairogCalculatorSource source;
  final List<BairogGatheringType> gatheringTypes;
  final List<BairogGatheringItemType> gatheringItemTypes;
  final List<BairogDropRate> dropRates;
  final List<BairogRotation> rotations;
  final Map<int, BairogGatheringType> gatheringTypesById;
  final Map<int, BairogGatheringItemType> gatheringItemTypesById;
  final Map<int, BairogRotation> rotationsById;

  factory BairogCalculatorData.fromJsonString(String source) {
    final decoded = jsonDecode(source);
    if (decoded is! Map) {
      throw const FormatException('Bairog calculator data must be an object.');
    }
    return BairogCalculatorData.fromJson(decoded.cast<String, dynamic>());
  }

  factory BairogCalculatorData.fromJson(Map<String, dynamic> json) {
    final rawSource = _requiredMap(json, 'source');
    final sourceUri = Uri.tryParse(_requiredString(rawSource, 'url'));
    final capturedAt = DateTime.tryParse(
      _requiredString(rawSource, 'capturedAtUtc'),
    );
    if (sourceUri == null || !sourceUri.hasScheme || capturedAt == null) {
      throw const FormatException('Invalid Bairog source metadata.');
    }
    final source = BairogCalculatorSource(
      creator: _requiredString(rawSource, 'creator'),
      publisher: _requiredString(rawSource, 'publisher'),
      url: sourceUri,
      capturedAtUtc: capturedAt.toUtc(),
      siteVersion: _requiredString(rawSource, 'siteVersion'),
      note: _requiredString(rawSource, 'note'),
    );

    final gatheringTypes = _requiredList(json, 'gatheringTypes')
        .map((raw) {
          final row = _object(raw, 'gathering type');
          return BairogGatheringType(
            id: _requiredInt(row, 'id'),
            name: _requiredString(row, 'name'),
            categoryId: _requiredInt(row, 'gathering_category_id'),
            hasAfuaru: _asBool(row['has_afuaru']),
            agrisPerGather: _nullableFinite(row['agris_per_gather']),
            afuaruSpawnRate: _nullableFinite(row['afuaru_spawn_rate']),
            afuaruAverageItems: _nullableFinite(row['afuaru_avg_items']),
            afuaruItemAverages: Map.unmodifiable(
              _requiredNumericMap(row['afuaru_item_avgs']),
            ),
            chestSpawnRate: _nullableFinite(row['chest_spawn_rate']),
            chestItemAverages: Map.unmodifiable(
              _requiredNumericMap(row['chest_item_avgs']),
            ),
            feverTimeSpawnRate: _nullableFinite(row['fever_time_spawn_rate']),
            feverTimeItemAverages: Map.unmodifiable(
              _requiredNumericMap(row['fever_time_item_avgs']),
            ),
          );
        })
        .toList(growable: false);

    final gatheringItemTypes = _requiredList(json, 'gatheringItemTypes')
        .map((raw) {
          final row = _object(raw, 'gathering item type');
          final bdo = _requiredMap(row, 'bdo_item');
          final rawFamily = _requiredInt(row, 'item_type');
          if (rawFamily < 0 || rawFamily >= BairogDropFamily.values.length) {
            throw FormatException('Unknown Bairog item family $rawFamily.');
          }
          return BairogGatheringItemType(
            id: _requiredInt(row, 'id'),
            family: BairogDropFamily.values[rawFamily],
            procsWithMinigame: _asBool(row['procs_with_minigame']),
            procsWithHedgehog: _asBool(row['procs_with_hedgehog']),
            multiDropFactor: _requiredFinite(row, 'multi_drop_factor'),
            globalDrop: _asBool(row['global_drop']),
            affectedByAgris: _asBool(row['affected_by_agris']),
            isPrimary: _asBool(row['is_primary']),
            vendorUnitPrice: _nullableFinite(row['only_vendor_price']),
            item: BairogBdoItem(
              id: _requiredInt(bdo, 'bdo_id'),
              name: _requiredString(bdo, 'name'),
              icon: _requiredString(bdo, 'icon'),
            ),
          );
        })
        .toList(growable: false);

    final dropRates = _requiredList(json, 'droprates')
        .map((raw) {
          final row = _object(raw, 'drop rate');
          return BairogDropRate(
            id: _requiredInt(row, 'id'),
            itemTypeId: _requiredInt(row, 'gathering_item_type_id'),
            gatheringTypeId: _requiredInt(row, 'gathering_type_id'),
            dropRate: _requiredFinite(row, 'droprate'),
            dropAmount: _requiredFinite(row, 'dropamount'),
            dropMin: _nullableFinite(row['drop_min']),
            dropMax: _nullableFinite(row['drop_max']),
          );
        })
        .toList(growable: false);

    final rotations = _requiredList(json, 'rotations')
        .map((raw) {
          final row = _object(raw, 'rotation');
          final video = Uri.tryParse(_requiredString(row, 'rotation_video'));
          if (video == null || !video.hasScheme) {
            throw FormatException(
              'Invalid video URL for rotation ${row['id']}.',
            );
          }
          final rawPrimary = row['primary_item_ratios'];
          return BairogRotation(
            id: _requiredInt(row, 'id'),
            name: _requiredString(row, 'name'),
            videoUrl: video,
            gatheringTypeId: _requiredInt(row, 'gathering_type_id'),
            averageGathersPerHour: _requiredInt(row, 'avg_gathers_per_hour'),
            sessionCount: _requiredInt(row, 'session_count'),
            totalHours: _requiredFinite(row, 'total_hours'),
            typeRatios: _requiredList(row, 'type_ratios')
                .map((rawRatio) {
                  final ratio = _object(rawRatio, 'rotation type ratio');
                  return BairogGatheringTypeRatio(
                    gatheringTypeId: _requiredInt(ratio, 'gathering_type_id'),
                    ratio: _requiredFinite(ratio, 'ratio'),
                  );
                })
                .toList(growable: false),
            primaryItemRatios: rawPrimary == null
                ? null
                : Map.unmodifiable(_requiredNumericMap(rawPrimary)),
          );
        })
        .toList(growable: false);

    _requireUniqueIds(gatheringTypes, (row) => row.id, 'gathering type');
    _requireUniqueIds(gatheringItemTypes, (row) => row.id, 'item type');
    _requireUniqueIds(dropRates, (row) => row.id, 'drop rate');
    _requireUniqueIds(rotations, (row) => row.id, 'rotation');
    final typeIds = gatheringTypes.map((row) => row.id).toSet();
    final itemTypeIds = gatheringItemTypes.map((row) => row.id).toSet();
    for (final drop in dropRates) {
      if (!typeIds.contains(drop.gatheringTypeId) ||
          !itemTypeIds.contains(drop.itemTypeId)) {
        throw FormatException('Drop ${drop.id} has an unresolved reference.');
      }
    }
    for (final route in rotations) {
      if (!typeIds.contains(route.gatheringTypeId) ||
          route.typeRatios.any(
            (ratio) => !typeIds.contains(ratio.gatheringTypeId),
          ) ||
          (route.primaryItemRatios?.keys.any(
                (id) => !itemTypeIds.contains(id),
              ) ??
              false)) {
        throw FormatException(
          'Rotation ${route.id} has an unresolved reference.',
        );
      }
    }
    for (final type in gatheringTypes) {
      final referenced = <int>{
        ...type.afuaruItemAverages.keys,
        ...type.chestItemAverages.keys,
        ...type.feverTimeItemAverages.keys,
      };
      if (referenced.any((id) => !itemTypeIds.contains(id))) {
        throw FormatException(
          'Gathering type ${type.id} has an unresolved item.',
        );
      }
    }

    return BairogCalculatorData._(
      source: source,
      gatheringTypes: gatheringTypes,
      gatheringItemTypes: gatheringItemTypes,
      dropRates: dropRates,
      rotations: rotations,
    );
  }
}

class BairogProjectedItem {
  const BairogProjectedItem({
    required this.itemType,
    required this.basePerHour,
    required this.hedgehogPerHour,
    required this.afuaruPerHour,
    required this.chestPerHour,
    required this.chestX10PerHour,
    required this.feverTimePerHour,
  });

  final BairogGatheringItemType itemType;
  final double basePerHour;
  final double hedgehogPerHour;
  final double afuaruPerHour;
  final double chestPerHour;
  final double chestX10PerHour;
  final double feverTimePerHour;

  double get totalPerHour =>
      basePerHour +
      hedgehogPerHour +
      afuaruPerHour +
      chestPerHour +
      chestX10PerHour +
      feverTimePerHour;
}

class BairogEnergyMetrics {
  const BairogEnergyMetrics({
    required this.energyUsePerHour,
    required this.selectedRecoveryPerHour,
    required this.naturalRecoveryPerHour,
    required this.netEnergyDrainPerHour,
    required this.startingEnergy,
    required this.energyBoost,
    required this.sessionHours,
    required this.hourlyExpenseSilver,
    required this.energyDumpExpenseSilver,
  });

  final double energyUsePerHour;
  final double selectedRecoveryPerHour;
  final double naturalRecoveryPerHour;
  final double netEnergyDrainPerHour;
  final double startingEnergy;
  final double energyBoost;
  final double sessionHours;
  final double hourlyExpenseSilver;
  final double energyDumpExpenseSilver;
}

class BairogRouteProjection {
  const BairogRouteProjection({
    required this.route,
    required this.sourceBenchmark,
    required this.effectiveGathersPerHour,
    required this.items,
    required this.dropAmountsPerHour,
    required this.itemTypeAmountsPerHour,
    required this.bdoItemAmountsPerHour,
    required this.baseSilverPerHour,
    required this.hedgehogSilverPerHour,
    required this.afuaruSilverPerHour,
    required this.chestSilverPerHour,
    required this.chestsPerHour,
    required this.chestX10SilverPerHour,
    required this.chestX10PerHour,
    required this.feverTimeSilverPerHour,
    required this.agrisSilverBonusPerHour,
    required this.agrisPointsPerHour,
    required this.totalSilverPerHour,
    required this.netSilverPerHour,
    required this.energyDumpSilver,
    required this.energy,
  });

  final BairogRotation route;

  /// Bairog's session count, hours, source date, video, and captured baseline.
  /// The calculator deliberately delegates those facts to the audited source
  /// benchmark instead of manufacturing a second metadata record.
  final BairogRouteBenchmark? sourceBenchmark;
  final int effectiveGathersPerHour;
  final List<BairogProjectedItem> items;
  final Map<int, double> dropAmountsPerHour;
  final Map<int, double> itemTypeAmountsPerHour;
  final Map<int, double> bdoItemAmountsPerHour;
  final double baseSilverPerHour;
  final double hedgehogSilverPerHour;
  final double afuaruSilverPerHour;
  final double chestSilverPerHour;
  final double chestsPerHour;
  final double chestX10SilverPerHour;
  final double chestX10PerHour;
  final double feverTimeSilverPerHour;
  final double agrisSilverBonusPerHour;
  final double agrisPointsPerHour;
  final double totalSilverPerHour;
  final double netSilverPerHour;
  final double energyDumpSilver;
  final BairogEnergyMetrics energy;

  BairogProjectedItem? itemByBdoId(int itemId) {
    for (final item in items) {
      if (item.itemType.item.id == itemId) return item;
    }
    return null;
  }
}

class BairogCalculator {
  const BairogCalculator(this.data, {this.benchmarkSet = bairogBenchmarkSet});

  final BairogCalculatorData data;
  final BairogBenchmarkSet benchmarkSet;

  BairogRouteProjection projectRoute({
    required int routeId,
    required BairogCalculatorSettings settings,
    Map<int, double> marketPricesByBdoItemId = const <int, double>{},
  }) {
    final route = data.rotationsById[routeId];
    if (route == null) throw ArgumentError.value(routeId, 'routeId');
    final mastery = bairogBonusesForMastery(settings.mastery);
    final ratios = route.typeRatios.isEmpty
        ? <BairogGatheringTypeRatio>[
            BairogGatheringTypeRatio(
              gatheringTypeId: route.gatheringTypeId,
              ratio: 1,
            ),
          ]
        : route.typeRatios;
    final routeTypeIds = ratios.map((entry) => entry.gatheringTypeId).toSet();
    final routeDrops = data.dropRates
        .where((drop) => routeTypeIds.contains(drop.gatheringTypeId))
        .toList(growable: false);
    final gathers =
        settings.customGathersPerHour[route.id] ?? route.averageGathersPerHour;
    final globalTax = settings.showTaxed ? settings.marketNetRate : 1.0;

    double price(BairogGatheringItemType? itemType) {
      if (itemType == null) return 0;
      final custom = settings.customItemPrices[itemType.id];
      if (custom != null) return custom;
      final vendor = itemType.vendorUnitPrice;
      if (vendor != null) return vendor;
      final market = marketPricesByBdoItemId[itemType.item.id] ?? 0;
      return market.isFinite && market >= 0 ? market : 0;
    }

    double tax(BairogGatheringItemType? itemType, {required bool perItem}) {
      if (itemType?.vendorUnitPrice != null) return 1;
      if (!perItem) return globalTax;
      final taxed = settings.dropTaxed[itemType?.id] ?? settings.showTaxed;
      return taxed ? settings.marketNetRate : 1;
    }

    var silverDrops = routeDrops;
    if (route.primaryItemRatios case final primaryRatios?) {
      // BDO Workshop uses these as composition shares for a single gathering
      // type. Mixed gathering-type routes are already weighted by typeRatios.
      final singleTypeRoute = ratios.length == 1;
      silverDrops = routeDrops
          .map((drop) {
            final itemType = data.gatheringItemTypesById[drop.itemTypeId];
            if (itemType?.isPrimary != true || !singleTypeRoute) return drop;
            final primaryRatio = primaryRatios[drop.itemTypeId] ?? 0;
            return drop.withDropAmount(drop.dropAmount * primaryRatio);
          })
          .toList(growable: false);
    }
    silverDrops = silverDrops
        .where((drop) {
          final itemType = data.gatheringItemTypesById[drop.itemTypeId];
          return !settings.hiddenDropItemTypeIds.contains(drop.itemTypeId) &&
              (settings.includeEvergreenShard ||
                  itemType?.item.id != bairogEvergreenShardItemId);
        })
        .toList(growable: false);

    double standardSilver(bool agrisEnabled) {
      var total = 0.0;
      for (final ratio in ratios) {
        for (final drop in silverDrops) {
          if (drop.gatheringTypeId != ratio.gatheringTypeId) continue;
          final itemType = data.gatheringItemTypesById[drop.itemTypeId];
          if (itemType == null) continue;
          final effective = _effectiveDrop(
            drop,
            itemType,
            mastery,
            settings,
            agrisEnabled: agrisEnabled,
          );
          total +=
              gathers *
              ratio.ratio *
              effective.rate *
              effective.amount *
              price(itemType) *
              tax(itemType, perItem: true);
        }
      }
      return total;
    }

    final baseSilver = standardSilver(settings.agrisEnabled);
    final noAgrisSilver = settings.agrisEnabled ? standardSilver(false) : 0;
    final agrisSilverBonus = settings.agrisEnabled
        ? baseSilver - noAgrisSilver
        : 0.0;

    var hedgehogSilver = 0.0;
    if (settings.hedgehogTier.procRate > 0) {
      for (final ratio in ratios) {
        for (final drop in silverDrops) {
          if (drop.gatheringTypeId != ratio.gatheringTypeId) continue;
          final itemType = data.gatheringItemTypesById[drop.itemTypeId];
          if (itemType?.procsWithHedgehog != true) continue;
          hedgehogSilver +=
              gathers *
              ratio.ratio *
              settings.hedgehogTier.procRate *
              drop.dropRate *
              itemType!.multiDropFactor *
              drop.dropAmount *
              price(itemType) *
              tax(itemType, perItem: false);
        }
      }
    }

    final yieldsByDrop = <int, _MutableProjectedYield>{};
    for (final drop in routeDrops) {
      final itemType = data.gatheringItemTypesById[drop.itemTypeId];
      if (itemType == null) continue;
      final ratio = ratios
          .where((entry) => entry.gatheringTypeId == drop.gatheringTypeId)
          .fold(0.0, (sum, entry) => sum + entry.ratio);
      final primaryRatio = itemType.isPrimary && route.primaryItemRatios != null
          ? route.primaryItemRatios![drop.itemTypeId] ?? 0
          : 1.0;
      final effective = _effectiveDrop(
        drop,
        itemType,
        mastery,
        settings,
        agrisEnabled: settings.agrisEnabled,
      );
      final row = yieldsByDrop.putIfAbsent(
        drop.id,
        () => _MutableProjectedYield(drop: drop),
      );
      row.base +=
          gathers * ratio * primaryRatio * effective.rate * effective.amount;
      if (itemType.procsWithHedgehog) {
        row.hedgehog +=
            gathers *
            ratio *
            primaryRatio *
            settings.hedgehogTier.procRate *
            drop.dropRate *
            itemType.multiDropFactor *
            drop.dropAmount;
      }
    }

    BairogDropRate? firstDrop(int gatheringTypeId, int itemTypeId) {
      for (final drop in routeDrops) {
        if (drop.gatheringTypeId == gatheringTypeId &&
            drop.itemTypeId == itemTypeId) {
          return drop;
        }
      }
      return null;
    }

    final nonMinigameGathers = gathers * (1 - settings.minigameMode.procChance);
    var afuaruSilver = 0.0;
    if (settings.includeAfuaru) {
      for (final ratio in ratios) {
        final type = data.gatheringTypesById[ratio.gatheringTypeId];
        if (type == null || !type.hasAfuaru || type.afuaruSpawnRate == null) {
          continue;
        }
        if (type.name.toLowerCase().contains('sap')) {
          final averageItems = type.afuaruAverageItems;
          if (averageItems == null) continue;
          final totalItems =
              nonMinigameGathers *
              ratio.ratio *
              type.afuaruSpawnRate! *
              averageItems;
          final primaryDrops = routeDrops
              .where((drop) {
                final itemType = data.gatheringItemTypesById[drop.itemTypeId];
                return drop.gatheringTypeId == type.id &&
                    itemType?.isPrimary == true;
              })
              .toList(growable: false);
          double primaryWeight(int itemTypeId) =>
              route.primaryItemRatios?[itemTypeId] ?? 1;
          final weightTotal = primaryDrops.fold(
            0.0,
            (sum, drop) => sum + primaryWeight(drop.itemTypeId),
          );
          if (weightTotal <= 0) continue;
          for (final drop in primaryDrops) {
            final amount =
                totalItems * primaryWeight(drop.itemTypeId) / weightTotal;
            final itemType = data.gatheringItemTypesById[drop.itemTypeId]!;
            yieldsByDrop
                    .putIfAbsent(
                      drop.id,
                      () => _MutableProjectedYield(drop: drop),
                    )
                    .afuaru +=
                amount;
            if (!settings.hiddenDropItemTypeIds.contains(itemType.id)) {
              afuaruSilver +=
                  amount * price(itemType) * tax(itemType, perItem: false);
            }
          }
        } else {
          for (final entry in type.afuaruItemAverages.entries) {
            final itemType = data.gatheringItemTypesById[entry.key];
            if (itemType == null) continue;
            final amount =
                nonMinigameGathers *
                ratio.ratio *
                type.afuaruSpawnRate! *
                entry.value;
            final drop = firstDrop(type.id, entry.key);
            if (drop != null) {
              yieldsByDrop
                      .putIfAbsent(
                        drop.id,
                        () => _MutableProjectedYield(drop: drop),
                      )
                      .afuaru +=
                  amount;
            }
            if (!settings.hiddenDropItemTypeIds.contains(itemType.id)) {
              afuaruSilver +=
                  amount * price(itemType) * tax(itemType, perItem: false);
            }
          }
        }
      }
    }

    var chestSilver = 0.0;
    var chestCount = 0.0;
    var chestX10Silver = 0.0;
    var chestX10Count = 0.0;
    if (settings.includeChest || settings.includeChestX10) {
      final rareRateFactor =
          1 +
          mastery.rareRatePercent / 100 +
          settings.gatheringDropRatePercent / 100;
      final rareAmount = 1 + mastery.rareAmountPercent / 100;
      final amountFloor = rareAmount.floor();
      final fraction = rareAmount - amountFloor;
      final rareAmountFactor =
          amountFloor * (1 - fraction) + (amountFloor + 1) * fraction;
      final goldKeyPrice = marketPricesByBdoItemId[44164] ?? 0;
      for (final ratio in ratios) {
        final type = data.gatheringTypesById[ratio.gatheringTypeId];
        if (type?.chestSpawnRate == null || type!.chestItemAverages.isEmpty) {
          continue;
        }
        final baseEvents =
            gathers * ratio.ratio * type.chestSpawnRate! * rareRateFactor;
        for (final isX10 in <bool>[false, true]) {
          final enabled = isX10
              ? settings.includeChestX10
              : settings.includeChest;
          final eventFactor = isX10
              ? 10 * settings.minigameMode.procChance
              : 1 - settings.minigameMode.procChance;
          if (!enabled || eventFactor <= 0) continue;
          final resultFactor = rareAmountFactor * eventFactor;
          final expectedChests = baseEvents * resultFactor;
          var silver = -expectedChests * goldKeyPrice;
          for (final entry in type.chestItemAverages.entries) {
            final itemType = data.gatheringItemTypesById[entry.key];
            if (itemType == null) continue;
            final amount = baseEvents * entry.value * resultFactor;
            final drop = firstDrop(type.id, entry.key);
            if (drop != null) {
              final row = yieldsByDrop.putIfAbsent(
                drop.id,
                () => _MutableProjectedYield(drop: drop),
              );
              if (isX10) {
                row.chestX10 += amount;
              } else {
                row.chest += amount;
              }
            }
            if (!settings.hiddenDropItemTypeIds.contains(itemType.id)) {
              silver +=
                  amount * price(itemType) * tax(itemType, perItem: false);
            }
          }
          if (isX10) {
            chestX10Count += expectedChests;
            chestX10Silver += silver;
          } else {
            chestCount += expectedChests;
            chestSilver += silver;
          }
        }
      }
    }

    var feverTimeSilver = 0.0;
    if (settings.includeFeverTime) {
      for (final ratio in ratios) {
        final type = data.gatheringTypesById[ratio.gatheringTypeId];
        if (type?.feverTimeSpawnRate == null ||
            type!.feverTimeItemAverages.isEmpty) {
          continue;
        }
        for (final entry in type.feverTimeItemAverages.entries) {
          final itemType = data.gatheringItemTypesById[entry.key];
          if (itemType == null) continue;
          final amount =
              gathers * ratio.ratio * type.feverTimeSpawnRate! * entry.value;
          final drop = firstDrop(type.id, entry.key);
          if (drop != null) {
            yieldsByDrop
                    .putIfAbsent(
                      drop.id,
                      () => _MutableProjectedYield(drop: drop),
                    )
                    .fever +=
                amount;
          }
          if (!settings.hiddenDropItemTypeIds.contains(itemType.id)) {
            feverTimeSilver +=
                amount * price(itemType) * tax(itemType, perItem: false);
          }
        }
      }
    }

    final itemsByType = <int, _MutableItemYield>{};
    final dropAmounts = <int, double>{};
    for (final row in yieldsByDrop.values) {
      dropAmounts[row.drop.id] = row.total;
      itemsByType
          .putIfAbsent(row.drop.itemTypeId, _MutableItemYield.new)
          .add(row);
    }
    final projectedItems =
        itemsByType.entries
            .map((entry) {
              final itemType = data.gatheringItemTypesById[entry.key]!;
              final row = entry.value;
              return BairogProjectedItem(
                itemType: itemType,
                basePerHour: row.base,
                hedgehogPerHour: row.hedgehog,
                afuaruPerHour: row.afuaru,
                chestPerHour: row.chest,
                chestX10PerHour: row.chestX10,
                feverTimePerHour: row.fever,
              );
            })
            .toList(growable: false)
          ..sort((a, b) => a.itemType.id.compareTo(b.itemType.id));
    final itemTypeAmounts = <int, double>{
      for (final item in projectedItems) item.itemType.id: item.totalPerHour,
    };
    final bdoAmounts = <int, double>{};
    for (final item in projectedItems) {
      bdoAmounts.update(
        item.itemType.item.id,
        (value) => value + item.totalPerHour,
        ifAbsent: () => item.totalPerHour,
      );
    }

    final minigameAgrisFactor = settings.minigameMode == BairogMinigameMode.none
        ? 1.0
        : settings.minigameMode.expectedYieldFactor;
    var agrisPoints = 0.0;
    if (settings.agrisEnabled) {
      for (final ratio in ratios) {
        agrisPoints +=
            gathers *
            ratio.ratio *
            (data.gatheringTypesById[ratio.gatheringTypeId]?.agrisPerGather ??
                0) *
            minigameAgrisFactor;
      }
    }

    final energyUse =
        gathers * settings.minigameMode.procChance * 10 +
        gathers *
            (1 - settings.minigameMode.procChance) *
            bairogProfessionalThreePlusEnergyUsePerGather;
    var selectedRecovery = 0.0;
    var energyBoost = 0.0;
    var hourlyExpense = 0.0;
    for (final expense in bairogEnergyExpenses) {
      if (!settings.enabledExpenseItemIds.contains(expense.bdoItemId)) continue;
      selectedRecovery += expense.recoveryPerHour;
      energyBoost += expense.energyBoost;
      final expensePrice = marketPricesByBdoItemId[expense.bdoItemId] ?? 0;
      hourlyExpense += expense.usesPerHour != null
          ? expense.usesPerHour! * expensePrice
          : expensePrice / expense.durationHours!;
    }
    final naturalRecovery = settings.naturalEnergyRecoveryPerThreeMinutes * 20;
    final netDrain = energyUse - (naturalRecovery + selectedRecovery);
    final availableEnergy = settings.yourEnergy + energyBoost;
    final sessionHours = netDrain > 0
        ? availableEnergy / netDrain
        : double.infinity;
    final totalSilver =
        baseSilver +
        hedgehogSilver +
        afuaruSilver +
        chestSilver +
        chestX10Silver +
        feverTimeSilver;
    var dumpExpense = 0.0;
    if (sessionHours.isFinite) {
      for (final expense in bairogEnergyExpenses) {
        if (!settings.enabledExpenseItemIds.contains(expense.bdoItemId)) {
          continue;
        }
        final expensePrice = marketPricesByBdoItemId[expense.bdoItemId] ?? 0;
        dumpExpense += expense.usesPerHour != null
            ? expense.usesPerHour! * sessionHours * expensePrice
            : (sessionHours / expense.durationHours!).ceil() * expensePrice;
      }
    }
    final energyDumpSilver = sessionHours.isFinite
        ? totalSilver * sessionHours - dumpExpense
        : double.infinity;
    BairogRouteBenchmark? sourceBenchmark;
    for (final benchmark in benchmarkSet.routes) {
      if (benchmark.sourceRouteId == route.id) {
        sourceBenchmark = benchmark;
        break;
      }
    }

    return BairogRouteProjection(
      route: route,
      sourceBenchmark: sourceBenchmark,
      effectiveGathersPerHour: gathers,
      items: List.unmodifiable(projectedItems),
      dropAmountsPerHour: Map.unmodifiable(dropAmounts),
      itemTypeAmountsPerHour: Map.unmodifiable(itemTypeAmounts),
      bdoItemAmountsPerHour: Map.unmodifiable(bdoAmounts),
      baseSilverPerHour: baseSilver,
      hedgehogSilverPerHour: hedgehogSilver,
      afuaruSilverPerHour: afuaruSilver,
      chestSilverPerHour: chestSilver,
      chestsPerHour: chestCount,
      chestX10SilverPerHour: chestX10Silver,
      chestX10PerHour: chestX10Count,
      feverTimeSilverPerHour: feverTimeSilver,
      agrisSilverBonusPerHour: agrisSilverBonus,
      agrisPointsPerHour: agrisPoints,
      totalSilverPerHour: totalSilver,
      netSilverPerHour: totalSilver - hourlyExpense,
      energyDumpSilver: energyDumpSilver,
      energy: BairogEnergyMetrics(
        energyUsePerHour: energyUse,
        selectedRecoveryPerHour: selectedRecovery,
        naturalRecoveryPerHour: naturalRecovery,
        netEnergyDrainPerHour: netDrain,
        startingEnergy: settings.yourEnergy,
        energyBoost: energyBoost,
        sessionHours: sessionHours,
        hourlyExpenseSilver: hourlyExpense,
        energyDumpExpenseSilver: dumpExpense,
      ),
    );
  }
}

class _EffectiveDrop {
  const _EffectiveDrop(this.rate, this.amount);

  final double rate;
  final double amount;
}

_EffectiveDrop _effectiveDrop(
  BairogDropRate drop,
  BairogGatheringItemType itemType,
  BairogMasteryBonuses mastery,
  BairogCalculatorSettings settings, {
  required bool agrisEnabled,
}) {
  final rateBonus = mastery.ratePercentFor(itemType.family) / 100;
  final amountBonus = mastery.amountPercentFor(itemType.family) / 100;
  final effectiveRate = math.min(
    1.0,
    drop.dropRate *
        itemType.multiDropFactor *
        (1 + rateBonus + settings.gatheringDropRatePercent / 100),
  );
  var agrisExtra = 0.0;
  if (agrisEnabled &&
      itemType.affectedByAgris &&
      drop.dropMin != null &&
      drop.dropMax != null) {
    final midpoint = (drop.dropMin! + drop.dropMax!) / 2;
    if (midpoint > 0) {
      agrisExtra =
          drop.dropAmount *
          (_averageAgrisResult(drop.dropMin!, drop.dropMax!) / midpoint);
    }
  }
  final minigameFactor = itemType.procsWithMinigame
      ? settings.minigameMode.expectedYieldFactor
      : 1 - settings.minigameMode.procChance;
  final effectiveAmount =
      (drop.dropAmount * (1 + amountBonus) + agrisExtra) * minigameFactor;
  return _EffectiveDrop(effectiveRate, effectiveAmount);
}

double _averageAgrisResult(double minimum, double maximum) {
  final min = minimum.round();
  final max = maximum.round();
  if (min == max) return (min * 1.5).floorToDouble();
  var total = 0.0;
  for (var amount = min; amount <= max; amount++) {
    total += (amount * 1.5).floor();
  }
  return total / (max - min + 1);
}

class _MutableProjectedYield {
  _MutableProjectedYield({required this.drop});

  final BairogDropRate drop;
  double base = 0;
  double hedgehog = 0;
  double afuaru = 0;
  double chest = 0;
  double chestX10 = 0;
  double fever = 0;

  double get total => base + hedgehog + afuaru + chest + chestX10 + fever;
}

class _MutableItemYield {
  double base = 0;
  double hedgehog = 0;
  double afuaru = 0;
  double chest = 0;
  double chestX10 = 0;
  double fever = 0;

  void add(_MutableProjectedYield row) {
    base += row.base;
    hedgehog += row.hedgehog;
    afuaru += row.afuaru;
    chest += row.chest;
    chestX10 += row.chestX10;
    fever += row.fever;
  }
}

Map<String, dynamic> _requiredMap(Map<String, dynamic> source, String key) =>
    _object(source[key], key);

Map<String, dynamic> _object(Object? value, String label) {
  if (value is! Map) throw FormatException('$label must be an object.');
  return value.cast<String, dynamic>();
}

List<dynamic> _requiredList(Map<String, dynamic> source, String key) {
  final value = source[key];
  if (value is! List) throw FormatException('$key must be an array.');
  return value;
}

String _requiredString(Map<String, dynamic> source, String key) {
  final value = source[key]?.toString().trim() ?? '';
  if (value.isEmpty) throw FormatException('$key must not be empty.');
  return value;
}

int _requiredInt(Map<String, dynamic> source, String key) {
  final value = _nullableInt(source[key]);
  if (value == null) throw FormatException('$key must be an integer.');
  return value;
}

double _requiredFinite(Map<String, dynamic> source, String key) {
  final value = _nullableFinite(source[key]);
  if (value == null) throw FormatException('$key must be finite.');
  return value;
}

int? _nullableInt(Object? value) {
  if (value is int) return value;
  if (value is num && value.isFinite && value == value.roundToDouble()) {
    return value.toInt();
  }
  return int.tryParse(value?.toString().trim() ?? '');
}

double? _nullableFinite(Object? value) {
  if (value == null) return null;
  final number = value is num
      ? value.toDouble()
      : double.tryParse(value.toString().trim());
  return number != null && number.isFinite ? number : null;
}

int _asInt(Object? value, {required int fallback}) =>
    _nullableInt(value) ?? fallback;

bool _asBool(Object? value, {bool fallback = false}) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  return switch (value?.toString().trim().toLowerCase()) {
    'true' || '1' || 'yes' => true,
    'false' || '0' || 'no' => false,
    _ => fallback,
  };
}

double _finiteNonNegative(Object? value, double fallback) {
  final number = _nullableFinite(value);
  return number == null ? fallback : math.max(0, number);
}

double _finiteClamped(
  Object? value,
  double fallback,
  double minimum,
  double maximum,
) {
  final number = _nullableFinite(value);
  return number == null ? fallback : number.clamp(minimum, maximum);
}

double _validNonNegative(double value, double fallback) =>
    value.isFinite ? math.max(0, value) : fallback;

double _validClamped(
  double value,
  double fallback,
  double minimum,
  double maximum,
) => value.isFinite ? value.clamp(minimum, maximum) : fallback;

Map<int, double> _requiredNumericMap(Object? value) {
  if (value == null) return const <int, double>{};
  if (value is! Map) throw const FormatException('Expected a numeric map.');
  final result = <int, double>{};
  for (final entry in value.entries) {
    final key = int.tryParse(entry.key.toString());
    final number = _nullableFinite(entry.value);
    if (key == null || number == null) {
      throw const FormatException('Invalid numeric map entry.');
    }
    result[key] = number;
  }
  return result;
}

Map<int, bool> _boolMap(Object? value) {
  if (value is! Map) return <int, bool>{};
  final result = <int, bool>{};
  for (final entry in value.entries) {
    final key = int.tryParse(entry.key.toString());
    if (key != null && key > 0) result[key] = _asBool(entry.value);
  }
  return result;
}

Set<int> _enabledIds(Object? value) {
  final result = <int>{};
  if (value is Map) {
    for (final entry in value.entries) {
      final key = int.tryParse(entry.key.toString());
      if (key != null && key > 0 && _asBool(entry.value)) result.add(key);
    }
  } else if (value is List) {
    for (final entry in value) {
      final key = _nullableInt(entry);
      if (key != null && key > 0) result.add(key);
    }
  }
  return result;
}

Map<int, int> _positiveIntMap(Object? value) {
  if (value is! Map) return <int, int>{};
  final result = <int, int>{};
  for (final entry in value.entries) {
    final key = int.tryParse(entry.key.toString());
    final number = _nullableInt(entry.value);
    if (key != null && key > 0 && number != null && number > 0) {
      result[key] = number;
    }
  }
  return result;
}

Map<int, double> _nonNegativeDoubleMap(Object? value) {
  if (value is! Map) return <int, double>{};
  final result = <int, double>{};
  for (final entry in value.entries) {
    final key = int.tryParse(entry.key.toString());
    final number = _nullableFinite(entry.value);
    if (key != null && key > 0 && number != null && number >= 0) {
      result[key] = number;
    }
  }
  return result;
}

Map<String, T> _sortedStringMap<T>(Map<int, T> source) => <String, T>{
  for (final entry
      in source.entries.toList()..sort((a, b) => a.key.compareTo(b.key)))
    '${entry.key}': entry.value,
};

void _requireUniqueIds<T>(
  Iterable<T> rows,
  int Function(T row) idOf,
  String label,
) {
  final seen = <int>{};
  for (final row in rows) {
    final id = idOf(row);
    if (!seen.add(id)) throw FormatException('Duplicate $label id $id.');
  }
}
