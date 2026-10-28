import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:bdo_craft_planner_flutter/data/catalog/bundled_catalog_parser.dart';
import 'package:bdo_craft_planner_flutter/data/catalog/catalog_repository.dart';
import 'package:bdo_craft_planner_flutter/data/icons/custom_icon_store.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
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
  testWidgets('contain keeps non-square bundled artwork bytes and full edges', (
    tester,
  ) async {
    final stored = (await tester.runAsync(StoredIconTestFixture.create))!;
    addTearDown(() => tester.runAsync(stored.dispose));
    final harness = PlannerTestHarness();
    final repository = CatalogRepository(
      const BundledCatalogParser().parse(
        File('assets/data/app-data.json').readAsStringSync(),
      ),
    );
    try {
      expect(
        ModeItemIcon(
          controller: harness.controller.active,
          name: 'Magnetite Ore',
          size: 44,
        ).fit,
        BoxFit.contain,
      );
      for (final source in [
        (name: "Margahan's Artifact", width: 48),
        (name: 'Melted Magnetite Shard', width: 56),
        (name: 'Magnetite Ore', width: 48),
      ]) {
        final uri = repository.iconDataUriAcrossModes(
          CraftMode.processing,
          source.name,
          preferCleanArtwork: true,
        );
        expect(uri, isNotNull);
        final originalBytes = Uri.parse(uri!).data!.contentAsBytes();
        final dimensions = await tester.runAsync(() async {
          final codec = await ui.instantiateImageCodec(originalBytes);
          try {
            final frame = await codec.getNextFrame();
            try {
              return Size(
                frame.image.width.toDouble(),
                frame.image.height.toDouble(),
              );
            } finally {
              frame.image.dispose();
            }
          } finally {
            codec.dispose();
          }
        });
        expect(dimensions!.width, greaterThan(0));
        expect(dimensions.height, greaterThan(0));
        for (final fit in [null, BoxFit.contain]) {
          await tester.pumpWidget(
            _host(
              harness: harness,
              store: stored.store,
              name: source.name,
              searchAcrossModes: true,
              catalogRepository: repository,
              fit: fit,
              size: 44,
            ),
          );
          final image = tester.widget<Image>(
            find.byKey(ModeItemIconKeys.image(source.name)),
          );
          expect(image.fit, fit ?? BoxFit.contain);
          expect(
            (image.image as MemoryImage).bytes,
            orderedEquals(originalBytes),
          );
          expect(tester.getSize(find.byType(ModeItemIcon)), const Size(44, 44));
          if (fit == BoxFit.contain) {
            final fitted = applyBoxFit(fit!, dimensions, const Size(44, 44));
            expect(fitted.source, dimensions);
            expect(fitted.destination.width, lessThanOrEqualTo(44));
            expect(fitted.destination.height, lessThanOrEqualTo(44));
          }
        }
      }
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await harness.controller.dispose();
      stored.store.dispose();
    }
  });

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
      expect(tester.widget<Image>(image).fit, BoxFit.contain);
      await tester.pumpWidget(
        _host(
          harness: harness,
          store: stored.store,
          name: 'Clear Liquid Reagent',
          fit: BoxFit.contain,
        ),
      );
      await pumpUntilIconState(tester, image);
      expect(tester.widget<Image>(image).fit, BoxFit.contain);
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

    final repository = CatalogRepository(productionCatalog);
    for (final name in <String>['Vedelona', 'Tears of the Falling Moon']) {
      await tester.pumpWidget(
        _host(
          harness: harness,
          store: stored.store,
          name: name,
          searchAcrossModes: true,
          fallbackIcon: Icons.local_florist_rounded,
          catalogRepository: repository,
        ),
      );

      expect(find.byKey(ModeItemIconKeys.image(name)), findsOneWidget);
      expect(find.byKey(ModeItemIconKeys.failure(name)), findsNothing);
    }

    await tester.pumpWidget(const SizedBox.shrink());
    await harness.controller.dispose();
    stored.store.dispose();
  });

  testWidgets('synthetic quality item uses its reviewed base artwork', (
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
        name: 'Special Rainbow Button Mushroom',
        aliases: const <String>['Rainbow Button Mushroom'],
        searchAcrossModes: true,
        catalogRepository: CatalogRepository(productionCatalog),
      ),
    );

    expect(
      find.byKey(ModeItemIconKeys.image('Special Rainbow Button Mushroom')),
      findsOneWidget,
    );
    expect(
      find.byKey(ModeItemIconKeys.failure('Special Rainbow Button Mushroom')),
      findsNothing,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await harness.controller.dispose();
    stored.store.dispose();
  });
}

Widget _host({
  required PlannerTestHarness harness,
  required CustomIconStore store,
  required String name,
  List<String> aliases = const <String>[],
  CustomIconBytesLoader? loader,
  bool searchAcrossModes = false,
  IconData? fallbackIcon,
  CatalogRepository? catalogRepository,
  BoxFit? fit,
  double size = 48,
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
            size: size,
            fit: fit ?? BoxFit.contain,
            aliases: aliases,
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
