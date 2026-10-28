import 'dart:convert';
import 'dart:io';

import '../../data/persistence/atomic_file_store.dart';
import '../../domain/models/craft_mode.dart';
import 'opportunities_content_scale.dart';

/// Kept apart from planner targets, inventory and recipe choices.
class OpportunitiesPreferences {
  factory OpportunitiesPreferences.fromJson(Object? value) {
    if (value is! Map<String, dynamic> || value['version'] != 1) {
      throw const FormatException('Unrecognized Opportunities settings.');
    }
    final result = OpportunitiesPreferences();
    String choice(String key, List<String> choices, String fallback) =>
        choices.contains(value[key]) ? value[key] as String : fallback;
    double number(String key, double fallback, double max) {
      final n = value[key];
      return n is num && n.isFinite && n >= 0 && n <= max
          ? n.toDouble()
          : fallback;
    }

    result.section = choice('section', [
      'crafting',
      'exchanges',
      'best-use',
    ], 'crafting');
    result.mode = CraftMode.values.firstWhere(
      (mode) => mode.key == value['mode'],
      orElse: () => CraftMode.cooking,
    );
    result.region = choice('region', ['eu', 'na'], 'eu');
    result.glassFinish = choice('glassFinish', ['bronze', 'moon'], 'bronze');
    result.contentScale = normalizeOpportunitiesContentScale(
      value['contentScale'],
    );
    result.craftSearch = value['craftSearch'] is String
        ? value['craftSearch'] as String
        : '';
    result.exchangeSearch = value['exchangeSearch'] is String
        ? value['exchangeSearch'] as String
        : '';
    result.bestUseItem = value['bestUseItem'] is String
        ? (value['bestUseItem'] as String).trim()
        : '';
    result.craftSale = choice('craftSale', ['buyers', 'listing'], 'buyers');
    result.exchangeSale = choice('exchangeSale', [
      'buyers',
      'listing',
    ], 'buyers');
    // The old Demand label conflated an output filter with preorder ordering.
    // Canonical "preorders" records identify deliberate new ordering choices,
    // so this correction cannot reset them on a later load.
    final legacyDemandSort = const [
      'demand',
      'activity',
    ].contains(value['craftSort']);
    result.craftSort = choice('craftSort', [
      'profit',
      'preorders',
      'exp',
    ], 'profit');
    result.unknownExpFilter = choice('unknownExpFilter', [
      'include',
      'hide',
      'only',
    ], 'include');
    final directions = value['craftSortAscending'];
    if (directions is Map) {
      for (final sort in result.craftSortAscending.keys) {
        if (directions[sort] is bool) {
          result.craftSortAscending[sort] = directions[sort] as bool;
        }
      }
    }
    result.profitableOnly = value['profitableOnly'] != false;
    result.demandOnly = legacyDemandSort || value['demandOnly'] == true;
    result.readyOnly = value['readyOnly'] == true;
    result.useInventory = value['useInventory'] == true;
    result.crafts = number('crafts', 1, 1000000).toInt().clamp(1, 1000000);
    result.currencyId = value['currencyId'] is String
        ? value['currencyId'] as String
        : 'sangpyeong';
    for (final entry in {'owned': result.owned}.entries) {
      final source = value[entry.key];
      if (source is Map) {
        for (final item in source.entries) {
          final Object? amount = item.value;
          if (item.key is String &&
              amount is int &&
              amount >= 0 &&
              amount <= 1000000000) {
            entry.value[item.key as String] = amount;
          }
        }
      }
    }
    // Account limits must be checked again each session, not carried past a reset.
    result.extraCostPerRun = number('extraCostPerRun', 0, 1000000000000);
    result.extraCostPerCraft = number('extraCostPerCraft', 0, 1000000000);
    return result;
  }

  OpportunitiesPreferences();
  String section = 'crafting';
  CraftMode mode = CraftMode.cooking;
  String region = 'eu';
  String glassFinish = 'bronze';
  double contentScale = 1;
  String craftSearch = '';
  String exchangeSearch = '';
  String bestUseItem = '';
  String craftSale = 'buyers';
  String exchangeSale = 'buyers';
  String craftSort = 'profit';
  String unknownExpFilter = 'include';
  final Map<String, bool> craftSortAscending = {
    'profit': false,
    'preorders': false,
    'exp': false,
  };
  bool get craftAscending => craftSortAscending[craftSort] ?? false;
  bool profitableOnly = true;
  bool demandOnly = false;
  bool readyOnly = false;
  bool useInventory = false;
  // Retired global controls: retained for saved-file/export/rollback
  // compatibility only. Overview calculations use one craft and zero extras;
  // detail quantities are local to the inspected recipe.
  int crafts = 1;
  String currencyId = 'sangpyeong';
  final Map<String, int> owned = {};
  final Map<String, int> remainingLimits = {};
  final Set<String> confirmedRequirements = {};
  // Compatibility-only values, like crafts above; never implicit quote costs.
  double extraCostPerRun = 0;
  double extraCostPerCraft = 0;

  Map<String, Object?> toJson() => {
    'version': 1,
    'section': section,
    'mode': mode.key,
    'region': region,
    'glassFinish': glassFinish,
    'contentScale': contentScale,
    'craftSearch': craftSearch,
    'exchangeSearch': exchangeSearch,
    'bestUseItem': bestUseItem,
    'craftSale': craftSale,
    'exchangeSale': exchangeSale,
    'craftSort': craftSort,
    'unknownExpFilter': unknownExpFilter,
    'craftSortAscending': Map<String, bool>.of(craftSortAscending),
    'profitableOnly': profitableOnly,
    'demandOnly': demandOnly,
    'readyOnly': readyOnly,
    'useInventory': useInventory,
    'crafts': crafts,
    'currencyId': currencyId,
    'owned': owned,
    'extraCostPerRun': extraCostPerRun,
    'extraCostPerCraft': extraCostPerCraft,
  };
}

class OpportunitiesPreferenceStore {
  OpportunitiesPreferenceStore(Directory directory)
    : _store = AtomicFileStore(
        directory: directory,
        fileName: 'opportunities-settings.json',
      );
  final AtomicFileStore _store;
  Future<OpportunitiesPreferences> load({String fallbackRegion = 'eu'}) async {
    final file = File(_store.targetPath);
    if (!await file.exists()) {
      return OpportunitiesPreferences()
        ..region = fallbackRegion == 'na' ? 'na' : 'eu';
    }
    return OpportunitiesPreferences.fromJson(
      jsonDecode(await file.readAsString()),
    );
  }

  Future<void> save(OpportunitiesPreferences value) async {
    await _store.writeJson(
      value.toJson(),
      validate: (bytes) {
        OpportunitiesPreferences.fromJson(jsonDecode(utf8.decode(bytes)));
      },
    );
  }
}
