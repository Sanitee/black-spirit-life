import 'dart:convert';
import 'dart:io';

import 'package:bdo_craft_planner_flutter/app/application_bootstrap.dart';
import 'package:bdo_craft_planner_flutter/data/persistence/personal_data_location_service.dart';
import 'package:bdo_craft_planner_flutter/data/persistence/planner_state_repository.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/domain/state/inventory_storage.dart';
import 'package:bdo_craft_planner_flutter/domain/state/planner_state_json_codec.dart';
import 'package:bdo_craft_planner_flutter/features/opportunities/opportunities_preferences.dart';
import 'package:bdo_gathering_companion/services/session_store.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

// Explicit, local-only validation. Never put a user's profile in test fixtures.
// All app loading and writes operate on a disposable copy, not the input.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final inputPath = Platform.environment['BSL_VALIDATE_PROFILE'];
  test(
    'copied profile loads intact, saves across builds and follows a move',
    () async {
      final input = Directory(inputPath!);
      final before = await _hashes(input);
      final fixture = await Directory.systemTemp.createTemp(
        'bsl-migration-check-',
      );
      addTearDown(() => fixture.delete(recursive: true));
      final documents = Directory('${fixture.path}/Documents');
      final personal = Directory('${documents.path}/Black Spirit Life');
      await _copy(input, personal);
      final environment = <String, String>{
        'APPDATA': '${fixture.path}/Roaming',
        'LOCALAPPDATA': '${fixture.path}/Local',
        'BSL_DOCUMENTS_DIR': documents.path,
      };
      PersonalDataLocationService location(String executable) =>
          PersonalDataLocationService.fromEnvironment(
            environment,
            shared: true,
            resolvedExecutable: '${fixture.path}/$executable/app.exe',
          );
      const codec = PlannerStateJsonCodec();
      final original = codec.decode(
        await File('${personal.path}/planner-state.json').readAsString(),
      );
      final firstLocation = location('first-build');
      addTearDown(firstLocation.sharedProfileGuard!.release);
      final first = await const ApplicationBootstrapService(
        applicationVersion: 'shared-check-1',
      ).load(personalDataLocation: firstLocation);
      addTearDown(first.controller.dispose);
      expect(first.stateLoad.origin, PlannerStateLoadOrigin.native);
      expect(first.firstLaunchMigration, isNull);
      expect(
        _same(first.stateLoad.state.toJson(), original.toJson()),
        isTrue,
        reason:
            'Every decoded setting, plan, inventory and extension must survive loading.',
      );
      // Current Inventory is shared: legacy mode-local values are unioned with
      // a case-insensitive maximum, not summed or silently discarded.
      final expectedInventory = <String, double>{};
      final canonicalNames = <String, String>{};
      for (final mode in CraftMode.values) {
        for (final entry in original.forMode(mode).inventory.entries) {
          if (entry.value <= 0) continue;
          final folded = entry.key.trim().toLowerCase();
          final name = canonicalNames.putIfAbsent(
            folded,
            () => entry.key.trim(),
          );
          if (entry.value > (expectedInventory[name] ?? 0)) {
            expectedInventory[name] = entry.value;
          }
        }
      }
      for (final mode in CraftMode.values) {
        expect(
          _same(
            first.controller.modes[mode]!.state.value.inventory,
            expectedInventory,
          ),
          isTrue,
        );
      }
      if (original.extensions.containsKey(
        inventoryStorageArchiveExtensionKey,
      )) {
        expect(
          _same(
            first
                .controller
                .documentSnapshot
                .extensions[inventoryStorageArchiveExtensionKey],
            original.extensions[inventoryStorageArchiveExtensionKey],
          ),
          isTrue,
        );
      } else if (CraftMode.values.any(
        (mode) => !_same(original.forMode(mode).inventory, expectedInventory),
      )) {
        final archive =
            first
                    .controller
                    .documentSnapshot
                    .extensions[inventoryStorageArchiveExtensionKey]
                as Map;
        for (final mode in CraftMode.values) {
          expect(
            _same(
              (archive[mode.name] as Map)['inventory'],
              original.forMode(mode).inventory,
            ),
            isTrue,
          );
        }
      }
      expect(
        first.runtimeRoot.path.replaceAll('\\', '/'),
        contains('/Local/Black Spirit Life/Shared Runtime'),
      );
      final gathering = SessionStore(
        directory: Directory('${personal.path}/gathering'),
      );
      await gathering.load();
      expect(gathering.recoveredBackup, isFalse);
      final preferences = await OpportunitiesPreferenceStore(
        Directory('${personal.path}/opportunities'),
      ).load();
      final expectedPreferences = OpportunitiesPreferences.fromJson(
        jsonDecode(
          await File(
            '${personal.path}/opportunities/opportunities-settings.json',
          ).readAsString(),
        ),
      );
      expect(_same(preferences.toJson(), expectedPreferences.toJson()), isTrue);

      final secondLocation = location('second-build');
      addTearDown(secondLocation.sharedProfileGuard!.release);
      await expectLater(
        secondLocation.resolveApplicationDirectory(),
        throwsA(isA<FileSystemException>()),
      );
      final feature = first.controller.active;
      final slot = feature.ensureInventoryStorageLocation(
        'Disposable validation only',
      );
      expect(
        feature.setInventoryStorageQuantity(
          locationId: slot,
          itemName: 'Water',
          text: '123',
        ),
        isTrue,
      );
      await first.controller.flush();
      final saved = codec.decode(
        await File('${personal.path}/planner-state.json').readAsString(),
      );
      await first.controller.dispose();
      await firstLocation.sharedProfileGuard!.release();
      final second = await const ApplicationBootstrapService(
        applicationVersion: 'shared-check-2',
      ).load(personalDataLocation: secondLocation);
      addTearDown(second.controller.dispose);
      expect(_same(second.stateLoad.state.toJson(), saved.toJson()), isTrue);
      await second.controller.dispose();
      final moved = Directory('${fixture.path}/Moved shared profile');
      await secondLocation.moveTo(moved.path);
      await secondLocation.sharedProfileGuard!.release();
      final thirdLocation = location('third-build');
      addTearDown(thirdLocation.sharedProfileGuard!.release);
      expect(
        (await thirdLocation.resolveApplicationDirectory()).absolute.path
            .replaceAll('\\', '/'),
        moved.absolute.path.replaceAll('\\', '/'),
      );
      expect(
        await File('${moved.path}/fishing/fish-journal.sqlite3').exists(),
        isTrue,
      );
      expect(
        _same(before, await _hashes(input)),
        isTrue,
        reason: 'The staged input must remain byte-identical.',
      );
    },
    skip: inputPath == null
        ? 'Requires an explicitly approved local staging path.'
        : false,
  );
}

// Boolean assertions avoid printing private values on a failed comparison.
bool _same(Object? left, Object? right) => equals(right).matches(left, {});

Future<void> _copy(Directory source, Directory target) async {
  await target.create(recursive: true);
  await for (final entity in source.list(followLinks: false)) {
    final name = entity.path.split(Platform.pathSeparator).last;
    if (entity is Directory) {
      await _copy(entity, Directory('${target.path}/$name'));
    } else if (entity is File) {
      await entity.copy('${target.path}/$name');
    } else {
      throw StateError('Profile input must not contain links.');
    }
  }
}

Future<Map<String, String>> _hashes(Directory directory) async => {
  await for (final entity in directory.list(
    recursive: true,
    followLinks: false,
  ))
    if (entity is File)
      entity.path.substring(directory.path.length): sha256
          .convert(await entity.readAsBytes())
          .toString(),
};
