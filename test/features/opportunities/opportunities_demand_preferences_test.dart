import 'dart:convert';
import 'dart:io';

import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/features/opportunities/opportunities_preferences.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Demand defaults off without changing Profit or availability', () {
    final preferences = OpportunitiesPreferences();
    expect(preferences.demandOnly, isFalse);
    expect(preferences.readyOnly, isFalse);
    expect(preferences.profitableOnly, isTrue);
    expect(preferences.craftSort, 'profit');
    expect(preferences.toJson()['demandOnly'], isFalse);
    expect(preferences.toJson()['version'], 1);
  });

  for (final legacy in [
    (stored: 'profit', demandOnly: false),
    (stored: 'demand', demandOnly: true),
    (stored: 'activity', demandOnly: true),
  ]) {
    test('${legacy.stored} legacy sort has the intended Demand filter', () {
      final preferences = OpportunitiesPreferences.fromJson({
        'version': 1,
        'craftSort': legacy.stored,
        'readyOnly': true,
        'profitableOnly': false,
      });
      expect(preferences.craftSort, 'profit');
      expect(preferences.demandOnly, legacy.demandOnly);
      expect(preferences.readyOnly, isTrue);
      expect(preferences.profitableOnly, isFalse);
      expect(preferences.toJson()['craftSort'], 'profit');
    });
  }

  test('only literal true enables the current saved Demand filter', () {
    for (final value in <Object?>[
      null,
      false,
      0,
      1,
      'true',
      'false',
      [],
      <String, Object?>{},
    ]) {
      final preferences = OpportunitiesPreferences.fromJson({
        'version': 1,
        'demandOnly': value,
      });
      expect(preferences.demandOnly, isFalse, reason: '$value');
    }
    expect(
      OpportunitiesPreferences.fromJson({
        'version': 1,
        'demandOnly': true,
      }).demandOnly,
      isTrue,
    );
  });

  test('all independent sort and filter combinations round-trip exactly', () {
    for (final sort in ['profit', 'preorders']) {
      for (final demandOnly in [false, true]) {
        for (final readyOnly in [false, true]) {
          for (final profitableOnly in [false, true]) {
            final original = OpportunitiesPreferences()
              ..mode = CraftMode.alchemy
              ..region = 'na'
              ..craftSearch = 'Elixir'
              ..crafts = 300
              ..currencyId = 'fairy-breath'
              ..owned['fairy-breath'] = 37
              ..craftSort = sort
              ..demandOnly = demandOnly
              ..readyOnly = readyOnly
              ..profitableOnly = profitableOnly;
            final restored = OpportunitiesPreferences.fromJson(
              jsonDecode(jsonEncode(original.toJson())),
            );
            expect(restored.toJson(), original.toJson());
            expect(restored.craftSort, sort);
            expect(restored.demandOnly, demandOnly);
            expect(restored.readyOnly, readyOnly);
            expect(restored.profitableOnly, profitableOnly);
          }
        }
      }
    }
  });

  test('loading an older file corrects intent without rewriting it', () async {
    final directory = await _temporaryDirectory();
    final file = File('${directory.path}/opportunities-settings.json');
    const legacy = '{"version":1,"craftSort":"demand","readyOnly":true}';
    await file.writeAsString(legacy, flush: true);

    final preferences = await OpportunitiesPreferenceStore(directory).load();

    expect(preferences.demandOnly, isTrue);
    expect(preferences.craftSort, 'profit');
    expect(preferences.readyOnly, isTrue);
    expect(await file.readAsString(), legacy);
    expect(await directory.list().length, 1);
  });

  test('legacy ambiguity is corrected even when its old filter was off', () {
    for (final sort in ['demand', 'activity']) {
      for (final demandOnly in [false, true]) {
        final original = OpportunitiesPreferences()
          ..mode = CraftMode.processing
          ..region = 'na'
          ..craftSearch = 'Copper'
          ..exchangeSearch = 'Fairy'
          ..craftSort = sort
          ..demandOnly = demandOnly
          ..readyOnly = true
          ..profitableOnly = false
          ..crafts = 700
          ..owned['fairy-breath'] = 53
          ..extraCostPerCraft = 72.5;
        final saved = original.toJson();
        final corrected = OpportunitiesPreferences.fromJson(saved);
        expect(corrected.toJson(), {
          ...saved,
          'craftSort': 'profit',
          'demandOnly': true,
        });
        expect(
          OpportunitiesPreferences.fromJson(corrected.toJson()).toJson(),
          corrected.toJson(),
          reason: 'The normalized record is stable on repeated loads.',
        );
      }
    }
  });

  test(
    'a deliberate Most preorders selection survives migration and restart',
    () async {
      final directory = await _temporaryDirectory();
      final file = File('${directory.path}/opportunities-settings.json');
      const legacy =
          '{"version":1,"craftSort":"demand","demandOnly":false,"readyOnly":true}';
      await file.writeAsString(legacy, flush: true);
      final store = OpportunitiesPreferenceStore(directory);
      final corrected = await store.load();
      expect(corrected.craftSort, 'profit');
      expect(corrected.demandOnly, isTrue);
      await store.save(corrected);
      final canonical =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      expect(canonical['craftSort'], 'profit');

      corrected.craftSort = 'preorders';
      await store.save(corrected);
      final reopened = await store.load();
      expect(reopened.craftSort, 'preorders');
      expect(reopened.demandOnly, isTrue);
      expect(reopened.readyOnly, isTrue);
      expect(
        OpportunitiesPreferences.fromJson(reopened.toJson()).craftSort,
        'preorders',
      );
      final backups = await directory
          .list()
          .where((entry) => entry.path.contains('.backup-'))
          .cast<File>()
          .toList();
      expect(backups, hasLength(2));
      expect(
        await Future.wait(backups.map((entry) => entry.readAsString())),
        contains(legacy),
      );
    },
  );

  test(
    'saved filters toggle independently and retain the prior backup',
    () async {
      final directory = await _temporaryDirectory();
      final store = OpportunitiesPreferenceStore(directory);
      final original = OpportunitiesPreferences()
        ..craftSort = 'profit'
        ..demandOnly = true
        ..readyOnly = true;
      await store.save(original);
      final first = await store.load();
      expect(first.craftSort, 'profit');
      expect(first.demandOnly, isTrue);
      expect(first.readyOnly, isTrue);

      first.demandOnly = false;
      await store.save(first);
      final restored = await store.load();
      expect(restored.craftSort, 'profit');
      expect(restored.demandOnly, isFalse);
      expect(restored.readyOnly, isTrue);
      final backup =
          (await directory
                  .list()
                  .where((file) => file.path.contains('.backup-'))
                  .cast<File>()
                  .toList())
              .single;
      final previous = OpportunitiesPreferences.fromJson(
        jsonDecode(await backup.readAsString()),
      );
      expect(previous.demandOnly, isTrue);
      expect(previous.craftSort, 'profit');
      expect(previous.readyOnly, isTrue);
    },
  );
}

Future<Directory> _temporaryDirectory() async {
  final directory = await Directory.systemTemp.createTemp(
    'opportunities-demand-preferences-test-',
  );
  addTearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });
  return directory;
}
