// Diagnostic uses only the checked-in synthetic lifecycle fixture.
import 'dart:convert';
import 'dart:io';
import 'package:bdo_craft_planner_flutter/app/application_bootstrap.dart';
import 'package:bdo_craft_planner_flutter/data/persistence/planner_state_repository.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('synthetic legacy inventory projection diagnostic', () async {
    final scratch = await Directory.systemTemp.createTemp(
      'bsl-synthetic-projection-',
    );
    addTearDown(() => scratch.delete(recursive: true));
    await File(
      'tool/release/lifecycle/fixtures/planner-state.v1.json',
    ).copy('${scratch.path}/planner-state.json');
    final bundle =
        await const ApplicationBootstrapService(
          applicationVersion: 'synthetic-audit',
        ).load(
          pathPolicy: PlannerStatePathPolicy(
            applicationDirectory: scratch,
            legacyStateFile: File('${scratch.path}/absent-legacy.json'),
          ),
        );
    addTearDown(bundle.controller.dispose);
    stdout.writeln(
      jsonEncode({
        for (final mode in CraftMode.values)
          mode.name: {
            'saved': bundle.stateLoad.state.forMode(mode).inventory,
            'projected': bundle.controller.modes[mode]!.state.value.inventory,
          },
      }),
    );
  });
}
