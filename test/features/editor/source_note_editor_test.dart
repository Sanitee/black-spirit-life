import 'dart:io';

import 'package:bdo_craft_planner_flutter/data/catalog/bundled_catalog_parser.dart';
import 'package:bdo_craft_planner_flutter/domain/state/state_copy.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../inventory/inventory_test_fixture.dart';
import 'editor_test_fixture.dart';

void main() {
  testWidgets(
    'Editor leaves bundled BDO import provenance out of Source Note',
    (tester) async {
      final catalog = const BundledCatalogParser().parse(
        File('assets/data/app-data.json').readAsStringSync(),
      );
      final base = inventoryDocument(showDeleteTools: true);
      final initialState = base.copyWith(
        alchemy: base.alchemy.copyWith(
          target: 'Red Pepper Powder',
          ingredientMeta: const {},
        ),
      );
      final harness = EditorTestHarness(
        catalog: catalog,
        initialState: initialState,
      );

      await pumpEditor(tester, harness, size: const Size(1500, 940));

      final field = tester.widget<EditableText>(
        editorForSemantics('Recipe source note'),
      );
      expect(field.controller.text, isEmpty);
      expect(find.textContaining('Imported from BDO'), findsNothing);
      await finishEditor(tester, harness);
    },
  );

  testWidgets('Editor keeps a persisted user RecipeEdit note', (tester) async {
    final harness = EditorTestHarness(initialState: editorDeepDocument());

    await pumpEditor(tester, harness, size: const Size(1500, 940));

    final field = tester.widget<EditableText>(
      editorForSemantics('Recipe source note'),
    );
    expect(field.controller.text, 'Bundled source override');
    await finishEditor(tester, harness);
  });
}
