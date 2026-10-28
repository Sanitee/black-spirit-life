import 'dart:convert';
import 'dart:io';

import 'package:bdo_craft_planner_flutter/data/catalog/catalog_repository.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/features/opportunities/opportunities_controller.dart';
import 'package:bdo_craft_planner_flutter/features/opportunities/opportunities_preferences.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/application_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('glass finish migrates safely and persists separately from recipes', () {
    for (final value in [null, 'removed', 4]) {
      expect(
        OpportunitiesPreferences.fromJson({
          'version': 1,
          'glassFinish': value,
        }).glassFinish,
        'bronze',
      );
    }
    final original = _preferences()..glassFinish = 'moon';
    final restored = OpportunitiesPreferences.fromJson(
      jsonDecode(jsonEncode(original.toJson())),
    );
    expect(restored.glassFinish, 'moon');
    expect(restored.toJson(), original.toJson());
  });

  test('inventory comparison defaults off and persists independently', () {
    final legacy = OpportunitiesPreferences.fromJson({
      'version': 1,
      'owned': {'fairy-breath': 4},
    });
    expect(legacy.useInventory, isFalse);
    legacy.useInventory = true;
    legacy.readyOnly = false;
    final restored = OpportunitiesPreferences.fromJson(
      jsonDecode(jsonEncode(legacy.toJson())),
    );
    expect(restored.useInventory, isTrue);
    expect(restored.readyOnly, isFalse);
    expect(restored.owned, {'fairy-breath': 4});
    expect(
      OpportunitiesPreferences.fromJson({
        'version': 1,
        'useInventory': 'true',
      }).useInventory,
      isFalse,
    );
  });

  test('the former Sales sort becomes Demand filtered by profit', () {
    final saved = _preferences().toJson()..['craftSort'] = 'activity';
    final restored = OpportunitiesPreferences.fromJson(saved);
    expect(restored.craftSort, 'profit');
    expect(restored.demandOnly, isTrue);
    expect(restored.toJson()['craftSort'], 'profit');
  });

  test('pane settings and exact owned balances round-trip independently', () {
    final original = _preferences();
    final restored = OpportunitiesPreferences.fromJson(
      jsonDecode(jsonEncode(original.toJson())),
    );
    expect(restored.toJson(), original.toJson());
    expect(restored.craftSearch, 'Beer');
    expect(restored.exchangeSearch, 'Fairy');
    expect(restored.craftSale, 'listing');
    expect(restored.exchangeSale, 'buyers');
    expect(restored.owned, {'sangpyeong': 10001, 'fairy-breath': 37});
    expect(restored.crafts, 300);
    expect(restored.extraCostPerRun, 12000);
    expect(restored.extraCostPerCraft, 75.5);
  });

  test('account limits and requirements cannot survive a session reset', () {
    final original = _preferences()
      ..remainingLimits['weekly-reward'] = 4
      ..remainingLimits['once-per-family-reward'] = 1
      ..confirmedRequirements.add('quest-reward');
    final saved = original.toJson();
    expect(saved.containsKey('remainingLimits'), isFalse);
    expect(saved.containsKey('confirmedRequirements'), isFalse);
    final restored = OpportunitiesPreferences.fromJson({
      ...saved,
      // Even a hand-edited or older file must not confirm account eligibility.
      'remainingLimits': {'weekly-reward': 4, 'once-per-family-reward': 1},
      'confirmedRequirements': ['quest-reward'],
    });
    expect(restored.remainingLimits, isEmpty);
    expect(restored.confirmedRequirements, isEmpty);
  });

  test(
    'retired timing settings cannot restore an invisible hourly estimate',
    () {
      final restored = OpportunitiesPreferences.fromJson({
        'version': 1,
        'craftSort': 'hour',
        'timeEnabled': true,
        'secondsPerCraft': 1,
        'preparationMinutes': 5,
        'craftsPerLoad': 10,
        'refillMinutes': 2,
      });
      expect(restored.craftSort, 'profit');
      for (final retired in [
        'timeEnabled',
        'secondsPerCraft',
        'preparationMinutes',
        'craftsPerLoad',
        'refillMinutes',
      ]) {
        expect(restored.toJson().containsKey(retired), isFalse);
      }
    },
  );

  test(
    'malformed scalar values do not become negative or nonfinite amounts',
    () {
      final restored = OpportunitiesPreferences.fromJson({
        'version': 1,
        'section': 'unknown',
        'mode': 'unknown',
        'region': 'unknown',
        'craftSale': 'unknown',
        'exchangeSale': 'unknown',
        'craftSort': 'unknown',
        'crafts': -1,
        'secondsPerCraft': double.nan,
        'preparationMinutes': double.infinity,
        'refillMinutes': -1,
        'extraCostPerRun': double.infinity,
        'extraCostPerCraft': -1,
        'craftsPerLoad': 1000001,
        'owned': {
          'valid': 42,
          'zero': 0,
          'max': 1000000000,
          'negative': -1,
          'fractional': 2.5,
          'string': '10',
          'too-large': 1000000001,
          123: 10,
        },
      });
      expect(restored.section, 'crafting');
      expect(restored.mode, CraftMode.cooking);
      expect(restored.region, 'eu');
      expect(restored.craftSale, 'buyers');
      expect(restored.exchangeSale, 'buyers');
      expect(restored.craftSort, 'profit');
      expect(restored.crafts, 1);
      expect(restored.extraCostPerRun, 0);
      expect(restored.extraCostPerCraft, 0);
      expect(restored.owned, {'valid': 42, 'zero': 0, 'max': 1000000000});
    },
  );

  test(
    'unsupported settings schemas fail explicitly instead of masquerading as defaults',
    () {
      for (final invalid in <Object?>[
        null,
        [],
        {},
        {'version': 2},
        'settings',
      ]) {
        expect(
          () => OpportunitiesPreferences.fromJson(invalid),
          throwsFormatException,
        );
      }
    },
  );

  test('missing settings are read without creating a file', () async {
    final directory = await _temporaryDirectory();
    final preferences = await OpportunitiesPreferenceStore(directory).load();
    expect(preferences.toJson(), OpportunitiesPreferences().toJson());
    expect(await directory.list().isEmpty, isTrue);
  });

  test(
    'first use inherits the planner region without writing settings',
    () async {
      final directory = await _temporaryDirectory();
      final preferences = await OpportunitiesPreferenceStore(
        directory,
      ).load(fallbackRegion: 'na');
      expect(preferences.region, 'na');
      expect(await directory.list().isEmpty, isTrue);
    },
  );

  test(
    'atomic saves preserve the prior settings as a recoverable backup',
    () async {
      final directory = await _temporaryDirectory();
      final store = OpportunitiesPreferenceStore(directory);
      final original = _preferences();
      await store.save(original);
      final firstBytes = await _settingsFile(directory).readAsBytes();
      final next = _preferences()..craftSearch = 'Vinegar';
      await store.save(next);
      expect((await store.load()).craftSearch, 'Vinegar');
      final backups = await directory
          .list()
          .where(
            (entry) =>
                entry.path.contains('opportunities-settings.json.backup-'),
          )
          .cast<File>()
          .toList();
      expect(backups, hasLength(1));
      expect(await backups.single.readAsBytes(), firstBytes);
    },
  );

  for (final scenario in [
    (name: 'malformed JSON', bytes: utf8.encode('{broken settings')),
    (
      name: 'unsupported schema',
      bytes: utf8.encode('{"version":2,"owned":{"coins":900}}'),
    ),
    (name: 'unreadable UTF-8', bytes: <int>[0xff, 0xfe, 0xff]),
  ]) {
    test(
      '${scenario.name} stays byte-identical after failed load and save',
      () async {
        final directory = await _temporaryDirectory();
        final file = _settingsFile(directory);
        await file.writeAsBytes(scenario.bytes, flush: true);
        final store = OpportunitiesPreferenceStore(directory);
        await expectLater(
          store.load(),
          scenario.name == 'unreadable UTF-8'
              ? throwsA(isA<FileSystemException>())
              : throwsFormatException,
        );
        await expectLater(store.save(_preferences()), throwsFormatException);
        expect(await file.readAsBytes(), scenario.bytes);
        expect(
          await directory
              .list()
              .map((entry) => entry.uri.pathSegments.last)
              .toList(),
          ['opportunities-settings.json'],
        );
      },
    );
  }

  test(
    'controller saves latest independent settings without changing any Planner state',
    () async {
      final harness = await ApplicationTestHarness.create();
      addTearDown(harness.dispose);
      final directory = Directory(
        '${harness.temporaryDirectory.path}/opportunities',
      );
      final plannerBefore = harness.bundle.controller.documentSnapshot;
      final controller = _controller(harness, directory);
      addTearDown(controller.dispose);
      await controller.ready;
      controller.change((p) {
        p.section = 'exchanges';
        p.craftSearch = 'Beer';
        p.exchangeSearch = 'Fairy';
        p.craftSale = 'listing';
        p.exchangeSale = 'buyers';
        p.craftSort = 'preorders';
        p.bestUseItem = 'Milk';
        p.demandOnly = true;
        p.owned['sangpyeong'] = 10001;
        p.owned['fairy-breath'] = 37;
        p.remainingLimits['weekly-reward'] = 2;
        p.confirmedRequirements.add('quest-reward');
      });
      final firstFlush = controller.flush();
      controller.selectGlassFinish('moon');
      controller.change((p) {
        p.craftSearch = 'Vinegar';
        p.bestUseItem = 'Aloe';
        p.owned['sangpyeong'] = 10007;
      });
      await Future.wait([firstFlush, controller.flush()]);
      expect(harness.bundle.controller.documentSnapshot, same(plannerBefore));
      final restored = await OpportunitiesPreferenceStore(directory).load();
      expect(restored.glassFinish, 'moon');
      expect(restored.section, 'exchanges');
      expect(restored.craftSearch, 'Vinegar');
      expect(restored.exchangeSearch, 'Fairy');
      expect(restored.craftSale, 'listing');
      expect(restored.exchangeSale, 'buyers');
      expect(restored.craftSort, 'preorders');
      expect(restored.bestUseItem, isEmpty);
      expect(controller.preferences.bestUseItem, 'Aloe');
      expect(restored.demandOnly, isTrue);
      expect(restored.owned, {'sangpyeong': 10007, 'fairy-breath': 37});
      expect(restored.remainingLimits, isEmpty);
      expect(restored.confirmedRequirements, isEmpty);
      // A normal save must not reset the current session's own confirmations.
      expect(controller.preferences.remainingLimits['weekly-reward'], 2);
      expect(
        controller.preferences.confirmedRequirements,
        contains('quest-reward'),
      );
      expect(controller.saveError, isNull);
      expect(
        await harness.temporaryDirectory
            .list()
            .where((entry) => entry is File)
            .isEmpty,
        isTrue,
      );
    },
  );

  test(
    'searches reset on restart while Best use stays session-only through navigation and saves',
    () async {
      final harness = await ApplicationTestHarness.create();
      addTearDown(harness.dispose);
      final directory = Directory(
        '${harness.temporaryDirectory.path}/opportunities',
      );
      final saved = _preferences()
        ..section = 'best-use'
        ..useInventory = true
        ..bestUseItem = 'Milk';
      await OpportunitiesPreferenceStore(directory).save(saved);
      final fileBefore = await _settingsFile(directory).readAsBytes();
      final plannerBefore = harness.bundle.controller.documentSnapshot;
      final expected = saved.toJson()
        ..['craftSearch'] = ''
        ..['exchangeSearch'] = ''
        ..['bestUseItem'] = '';

      final first = _controller(harness, directory);
      try {
        await first.ready;
        expect(first.preferences.toJson(), expected);
        // Startup must not rewrite the user's file just to clear visible search.
        expect(await _settingsFile(directory).readAsBytes(), fileBefore);
        await first.flush();
        expect(await _settingsFile(directory).readAsBytes(), fileBefore);
        first.selectBestUseItem('Aloe');
        first.change((p) {
          p.section = 'best-use';
          p.craftSearch = 'Vinegar';
          p.exchangeSearch = 'Milk';
        });
        await first.calculationSettled;
        expect(first.preferences.bestUseItem, 'Aloe');
        for (final mode in CraftMode.values) {
          first.change((p) {
            p.section = 'crafting';
            p.mode = mode;
          }, assemble: true);
          await first.calculationSettled;
          expect(first.preferences.craftSearch, 'Vinegar');
          expect(first.preferences.exchangeSearch, 'Milk');
          expect(first.preferences.bestUseItem, 'Aloe');
        }
        first.change((p) => p.section = 'exchanges');
        expect(first.preferences.bestUseItem, 'Aloe');
        first.change((p) => p.section = 'best-use');
        await first.flush();
        expect(first.preferences.craftSearch, 'Vinegar');
        expect(first.preferences.exchangeSearch, 'Milk');
        expect(first.preferences.bestUseItem, 'Aloe');
        final disk = await OpportunitiesPreferenceStore(directory).load();
        expect(
          disk.toJson(),
          first.preferences.toJson()..['bestUseItem'] = '',
          reason:
              'Saving removes only the session selection from the snapshot.',
        );
        expect(
          (jsonDecode(await _settingsFile(directory).readAsString())
              as Map<String, dynamic>)['bestUseItem'],
          isEmpty,
        );
      } finally {
        first.dispose();
      }

      final restarted = _controller(harness, directory);
      try {
        await restarted.ready;
        expect(restarted.preferences.toJson(), expected);
        expect(harness.bundle.controller.documentSnapshot, same(plannerBefore));
        expect(restarted.notice, isNull);
      } finally {
        await restarted.flush();
        restarted.dispose();
      }
    },
  );

  test(
    'unchanged controller flush leaves an unreadable settings file untouched',
    () async {
      final harness = await ApplicationTestHarness.create();
      addTearDown(harness.dispose);
      final directory = Directory(
        '${harness.temporaryDirectory.path}/opportunities',
      );
      await directory.create();
      final file = _settingsFile(directory);
      final bytes = utf8.encode('{"version":9,"important":"retain"}');
      await file.writeAsBytes(bytes, flush: true);
      final controller = _controller(harness, directory);
      addTearDown(controller.dispose);
      await controller.ready;
      expect(controller.notice, contains('left untouched'));
      await controller.flush();
      expect(await file.readAsBytes(), bytes);
      expect(controller.saveError, isNull);
      controller.change((p) => p.craftSearch = 'Beer');
      await expectLater(controller.flush(), throwsStateError);
      expect(controller.saveError, contains('could not be saved'));
      expect(await file.readAsBytes(), bytes);
    },
  );
}

OpportunitiesPreferences _preferences() => OpportunitiesPreferences()
  ..section = 'exchanges'
  ..mode = CraftMode.processing
  ..region = 'na'
  ..craftSearch = 'Beer'
  ..exchangeSearch = 'Fairy'
  ..craftSale = 'listing'
  ..exchangeSale = 'buyers'
  ..craftSort = 'preorders'
  ..demandOnly = true
  ..profitableOnly = false
  ..readyOnly = true
  ..crafts = 300
  ..currencyId = 'fairy-breath'
  ..owned.addAll({'sangpyeong': 10001, 'fairy-breath': 37})
  ..extraCostPerRun = 12000
  ..extraCostPerCraft = 75.5;

Future<Directory> _temporaryDirectory() async {
  final directory = await Directory.systemTemp.createTemp(
    'opportunities-preferences-test-',
  );
  addTearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });
  return directory;
}

File _settingsFile(Directory directory) =>
    File('${directory.path}/opportunities-settings.json');

OpportunitiesController _controller(
  ApplicationTestHarness harness,
  Directory directory,
) => OpportunitiesController(
  appController: harness.bundle.controller,
  catalog: CatalogRepository(harness.bundle.catalog),
  directory: directory,
  clock: () => DateTime.utc(2026, 9, 8, 16),
  serviceFactory: (_) =>
      throw StateError('No network is permitted in preference tests.'),
);
