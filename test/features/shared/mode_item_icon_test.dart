import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:bdo_craft_planner_flutter/data/catalog/bundled_catalog_parser.dart';
import 'package:bdo_craft_planner_flutter/data/catalog/catalog_repository.dart';
import 'package:bdo_craft_planner_flutter/data/icons/custom_icon_store.dart';
import 'package:bdo_craft_planner_flutter/domain/state/planner_state.dart';
import 'package:bdo_craft_planner_flutter/domain/state/state_copy.dart';
import 'package:bdo_craft_planner_flutter/features/shared/custom_icon_store_scope.dart';
import 'package:bdo_craft_planner_flutter/features/shared/mode_item_icon.dart';
import 'package:bdo_craft_planner_flutter/visual/foundations/theme_spec.dart';
import 'package:bdo_craft_planner_flutter/visual/standard/standard_spec.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../planner/planner_test_fixture.dart';
import 'custom_icon_test_support.dart';

void main() {
  testWidgets(
    'custom files load asynchronously and missing files replace cached art',
    (tester) async {
      final stored = (await tester.runAsync(StoredIconTestFixture.create))!;
      addTearDown(() => tester.runAsync(stored.dispose));
      final harness = PlannerTestHarness();
      harness.controller.active.updateState(
        (state) => state.copyWith(
          customIcons: <String, CustomIconReference>{
            'Clear Liquid Reagent': stored.reference,
          },
        ),
        immediate: true,
      );

      Widget subject() => _host(
        harness: harness,
        store: stored.store,
        name: 'Clear Liquid Reagent',
      );

      await tester.pumpWidget(subject());
      expect(
        find.byKey(ModeItemIconKeys.loading('Clear Liquid Reagent')),
        findsOneWidget,
      );
      final image = find.byKey(ModeItemIconKeys.image('Clear Liquid Reagent'));
      await pumpUntilIconState(tester, image);
      expect(
        (tester.widget<Image>(image).image as MemoryImage).bytes,
        orderedEquals(stored.bytes),
      );

      await tester.runAsync(() => stored.store.remove(stored.reference));
      await tester.pumpWidget(subject());
      final failure = find.byKey(
        ModeItemIconKeys.failure('Clear Liquid Reagent'),
      );
      await pumpUntilIconState(tester, failure);
      expect(image, findsNothing);
      expect(
        tester
            .widget<Tooltip>(
              find.descendant(of: failure, matching: find.byType(Tooltip)),
            )
            .message,
        contains('invalid or missing'),
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await harness.controller.dispose();
      stored.store.dispose();
    },
  );

  testWidgets('a stale custom-icon future cannot replace a newer choice', (
    tester,
  ) async {
    final stored = (await tester.runAsync(StoredIconTestFixture.create))!;
    addTearDown(() => tester.runAsync(stored.dispose));
    final harness = PlannerTestHarness();
    final oldLoad = Completer<Uint8List>();
    final newLoad = Completer<Uint8List>();
    final newReference = CustomIconReference(
      relativePath: 'icons/${List<String>.filled(64, 'b').join()}.png',
      sha256: List<String>.filled(64, 'B').join(),
      mediaType: 'image/png',
      byteCount: stored.reference.byteCount,
      width: stored.reference.width,
      height: stored.reference.height,
    );
    Future<Uint8List> loader(_, CustomIconReference reference) {
      if (reference.sha256 == stored.reference.sha256) return oldLoad.future;
      if (reference.sha256 == newReference.sha256) return newLoad.future;
      throw StateError('Unexpected custom-icon reference.');
    }

    harness.controller.active.updateState(
      (state) => state.copyWith(
        customIcons: <String, CustomIconReference>{
          'Clear Liquid Reagent': stored.reference,
        },
      ),
      immediate: true,
    );

    await tester.pumpWidget(
      _host(
        harness: harness,
        store: stored.store,
        name: 'Clear Liquid Reagent',
        loader: loader,
      ),
    );
    expect(
      find.byKey(ModeItemIconKeys.loading('Clear Liquid Reagent')),
      findsOneWidget,
    );

    harness.controller.active.updateState(
      (state) => state.copyWith(
        customIcons: <String, CustomIconReference>{
          'Clear Liquid Reagent': newReference,
        },
      ),
      immediate: true,
    );
    await tester.pump();
    newLoad.complete(stored.bytes);
    await tester.pump();
    final image = find.byKey(ModeItemIconKeys.image('Clear Liquid Reagent'));
    expect(image, findsOneWidget);

    oldLoad.completeError(
      const CustomIconValidationException('The old file disappeared.'),
    );
    await tester.pump();
    expect(image, findsOneWidget);
    expect(
      find.byKey(ModeItemIconKeys.failure('Clear Liquid Reagent')),
      findsNothing,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await harness.controller.dispose();
    stored.store.dispose();
  });

  testWidgets('resource-only game artwork resolves across craft modes', (
    tester,
  ) async {
    final stored = (await tester.runAsync(StoredIconTestFixture.create))!;
    addTearDown(() => tester.runAsync(stored.dispose));
    final harness = PlannerTestHarness();
    final productionCatalog = const BundledCatalogParser().parse(
      File('assets/data/app-data.json').readAsStringSync(),
    );

    await tester.pumpWidget(
      _host(
        harness: harness,
        store: stored.store,
        name: 'Vedelona',
        searchAcrossModes: true,
        fallbackIcon: Icons.local_florist_rounded,
        catalogRepository: CatalogRepository(productionCatalog),
      ),
    );

    expect(find.byKey(ModeItemIconKeys.image('Vedelona')), findsOneWidget);
    expect(find.byKey(ModeItemIconKeys.failure('Vedelona')), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await harness.controller.dispose();
    stored.store.dispose();
  });
}

Widget _host({
  required PlannerTestHarness harness,
  required CustomIconStore store,
  required String name,
  CustomIconBytesLoader? loader,
  bool searchAcrossModes = false,
  IconData? fallbackIcon,
  CatalogRepository? catalogRepository,
}) => MaterialApp(
  theme: StandardSpec.theme.materialTheme(),
  home: ThemeSpecScope(
    spec: StandardSpec.theme,
    child: Scaffold(
      body: Center(
        child: CustomIconStoreScope(
          store: store,
          child: ModeItemIcon(
            controller: harness.controller.active,
            name: name,
            size: 48,
            searchAcrossModes: searchAcrossModes,
            fallbackIcon: fallbackIcon,
            catalogRepository: catalogRepository,
            customIconLoader:
                loader ??
                (iconStore, reference) =>
                    iconStore.readValidatedBytesAsync(reference),
          ),
        ),
      ),
    ),
  ),
);
