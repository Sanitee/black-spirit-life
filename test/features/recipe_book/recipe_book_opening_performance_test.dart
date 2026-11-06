import 'dart:io';
import 'package:bdo_craft_planner_flutter/data/catalog/bundled_catalog_parser.dart';
import 'package:bdo_craft_planner_flutter/data/catalog/catalog_repository.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/features/planner/planner_contracts.dart';
import 'package:bdo_craft_planner_flutter/features/recipe_book/recipe_book.dart';
import 'package:bdo_craft_planner_flutter/visual/visual.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../planner/planner_review_projection_test.dart' as fixture;

void main() {
  final catalog = const BundledCatalogParser().parse(
    File('assets/data/app-data.json').readAsStringSync(),
  );
  for (final mode in CraftMode.values) {
    testWidgets('opening work ${mode.name}', (tester) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final app = fixture.controller(catalog, mode, 'Beer', 1);
      RecipeBookController makeBook() => RecipeBookController(
        modeController: app.active,
        catalogRepository: CatalogRepository.cached(catalog),
        callingContext: RecipeBookCallingContext.planner,
        allowedTargets: app.active.craftableNames,
      );
      final probe = makeBook();
      final watch = Stopwatch()..start();
      final first = probe.snapshot;
      final snapshotMicros = watch.elapsedMicroseconds;
      watch.reset();
      probe.snapshot;
      final repeatedSnapshotMicros = watch.elapsedMicroseconds;
      watch.reset();
      for (final entry in first.entries.take(24)) {
        probe.itemInfoFor(entry.name);
      }
      final infoMicros = watch.elapsedMicroseconds;
      probe.dispose();
      final book = makeBook();
      watch.reset();
      await tester.pumpWidget(
        MaterialApp(
          home: ThemeSpecScope(
            spec: SakuraNightGardenSpec.theme,
            child: RecipeBookModal(
              controller: book,
              onClose: () {},
              onActivated: (_) {},
            ),
          ),
        ),
      );
      final openingMicros = watch.elapsedMicroseconds;
      await tester.pumpAndSettle();
      expect(
        book.debugCachedItemInfoCount,
        0,
        reason: 'Closed previews must not project any item reference.',
      );
      final icon = find.byType(RecipeBookItemIcon).first;
      final name = tester.widget<RecipeBookItemIcon>(icon).name;
      await tester.tap(icon);
      await tester.pumpAndSettle();
      expect(find.byType(ItemReferenceCard), findsOneWidget);
      expect(book.debugCachedItemInfoCount, 1);
      expect(book.itemInfoFor(name), isNotNull);
      // Timings are diagnostics, not hardware-sensitive pass/fail budgets.
      debugPrint(
        'OPENING ${mode.name}: snapshot=$snapshotMicros repeated=$repeatedSnapshotMicros info24=$infoMicros firstFrame=$openingMicros entries=${first.entries.length}',
      );
      expect(tester.takeException(), isNull);
      expect(first.entries, isNotEmpty);
      await tester.pumpWidget(const SizedBox());
      book.dispose();
      await app.dispose();
    });
  }
}
