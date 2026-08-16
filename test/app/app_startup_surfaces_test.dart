import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bdo_craft_planner_flutter/app/app.dart';
import 'package:bdo_craft_planner_flutter/app/application_bootstrap.dart';
import 'package:bdo_craft_planner_flutter/app/first_run_setup_view.dart';
import 'package:bdo_craft_planner_flutter/app/window/app_title_bar.dart';
import 'package:bdo_craft_planner_flutter/app/window/world_root_startup_animation.dart';
import 'package:bdo_craft_planner_flutter/app_identity.dart';
import 'package:bdo_craft_planner_flutter/data/persistence/planner_state_repository.dart';
import 'package:bdo_craft_planner_flutter/domain/models/catalog_models.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/shared/overlays/draggable_overlay_surface.dart';
import 'package:bdo_craft_planner_flutter/visual/components/app_surface.dart';
import 'package:bdo_craft_planner_flutter/visual/components/section_header.dart';
import 'package:bdo_craft_planner_flutter/visual/foundations/app_scroll_behavior.dart';
import 'package:bdo_craft_planner_flutter/visual/foundations/theme_spec.dart';
import 'package:bdo_craft_planner_flutter/visual/sakura_night_garden/sakura_backdrop.dart';
import 'package:bdo_craft_planner_flutter/visual/sakura_night_garden/sakura_spec.dart';
import 'package:bdo_craft_planner_flutter/visual/standard/standard_backdrop.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('startup loading uses Sakura Night before state resolves', (
    tester,
  ) async {
    final pending = Completer<ApplicationBundle>();

    await tester.pumpWidget(
      BdoCraftPlannerApp(applicationFuture: pending.future),
    );

    expect(find.byType(SakuraNightGardenBackdrop), findsOneWidget);
    expect(find.byType(StandardBackdrop), findsNothing);
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).scrollBehavior,
      isA<AppScrollBehavior>(),
    );
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).title,
      AppIdentity.displayName,
    );
    expect(find.byType(AppSurface), findsOneWidget);
    expect(find.byType(WorldRootStartupAnimation), findsOneWidget);
    expect(find.byKey(WorldRootStartupAnimation.artworkKey), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('startup-loading-indicator')),
      findsOneWidget,
    );
    expect(find.text('Preparing your planner'), findsOneWidget);
    _expectOwnedStartupFrame(tester, find.text('Preparing your planner'));
    expect(
      find.bySemanticsLabel(
        'Loading the complete BDO catalog and planner state',
      ),
      findsOneWidget,
    );
    _expectNoGenericStartupControls();
  });

  testWidgets('startup loading remains readable at 200% text scale', (
    tester,
  ) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(1200, 752);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final pending = Completer<ApplicationBundle>();

    await tester.pumpWidget(
      BdoCraftPlannerApp(applicationFuture: pending.future),
    );

    expect(find.text('Preparing your planner'), findsOneWidget);
    expect(
      find.text('Loading the complete catalog and saved state…'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('startup failure is a retained danger surface', (tester) async {
    final pending = Completer<ApplicationBundle>();
    await tester.pumpWidget(
      BdoCraftPlannerApp(applicationFuture: pending.future),
    );

    pending.completeError(StateError('catalog unavailable'));
    await tester.pump();

    expect(find.byType(WorldRootStartupAnimation), findsNothing);
    expect(find.byType(SakuraNightGardenBackdrop), findsOneWidget);
    expect(find.byType(StandardBackdrop), findsNothing);
    expect(find.byType(SectionHeader), findsOneWidget);
    expect(
      find.text('${AppIdentity.displayName} could not start.'),
      findsOneWidget,
    );
    expect(find.textContaining('catalog unavailable'), findsOneWidget);
    _expectOwnedStartupFrame(
      tester,
      find.textContaining('No test or fallback data'),
    );
    final dangerSurfaces = tester
        .widgetList<AppSurface>(find.byType(AppSurface))
        .where((surface) => surface.tone == AppSurfaceTone.danger);
    expect(dangerSurfaces, hasLength(2));
    _expectNoGenericStartupControls();
  });

  testWidgets('migration preview, confirmation, and report stay app-owned', (
    tester,
  ) async {
    final temporaryDirectory = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('bdo-startup-surface-'),
    ))!;
    addTearDown(() async {
      if (await temporaryDirectory.exists()) {
        await temporaryDirectory.delete(recursive: true);
      }
    });
    final applicationDirectory = Directory(
      '${temporaryDirectory.path}${Platform.pathSeparator}flutter',
    );
    final legacyStateFile = File(
      '${temporaryDirectory.path}${Platform.pathSeparator}avalonia'
      '${Platform.pathSeparator}planner-state.json',
    );
    await tester.runAsync(() async {
      await legacyStateFile.parent.create(recursive: true);
      await legacyStateFile.writeAsString(
        jsonEncode(<String, Object?>{
          'version': 1,
          'activeMode': 'alchemy',
          'alchemy': <String, Object?>{
            'version': 1,
            'target': 'Alchemy Target',
            'want': 7,
          },
          'cooking': <String, Object?>{
            'version': 1,
            'target': 'Cooking Target',
          },
          'processing': <String, Object?>{
            'version': 1,
            'target': 'Processing Target',
          },
        }),
        flush: true,
      );
    });
    final seedBundle = (await tester.runAsync(
      () => const ApplicationBootstrapService(applicationVersion: 'test').load(
        catalogFuture: Future<CatalogSnapshot>.value(_catalog()),
        pathPolicy: PlannerStatePathPolicy(
          applicationDirectory: applicationDirectory,
          legacyStateFile: legacyStateFile,
        ),
      ),
    ))!;
    addTearDown(seedBundle.controller.dispose);
    final preview = seedBundle.firstLaunchMigration!.preview;
    final resolvedBundle = ApplicationBundle(
      catalog: seedBundle.catalog,
      stateLoad: PlannerStateLoadResult(
        state: preview.freshState,
        origin: PlannerStateLoadOrigin.fresh,
        notices: const <String>[
          'Started with a clean Flutter profile. The Avalonia state was not imported or modified.',
        ],
        migrationReport: preview.report,
        sourceUnchangedAfterMigration: true,
      ),
      stateRepository: seedBundle.stateRepository,
      personalDataLocation: seedBundle.personalDataLocation,
      controller: seedBundle.controller,
    );
    final migration = ApplicationFirstLaunchMigration(
      preview: preview,
      accept: () async => resolvedBundle,
      startFresh: () async => resolvedBundle,
    );
    final pendingBundle = ApplicationBundle(
      catalog: seedBundle.catalog,
      stateLoad: seedBundle.stateLoad,
      stateRepository: seedBundle.stateRepository,
      personalDataLocation: seedBundle.personalDataLocation,
      controller: seedBundle.controller,
      firstLaunchMigration: migration,
    );

    await tester.pumpWidget(
      BdoCraftPlannerApp(
        applicationFuture: Future<ApplicationBundle>.value(pendingBundle),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(SakuraNightGardenBackdrop), findsOneWidget);
    expect(find.byType(StandardBackdrop), findsNothing);
    expect(find.text('Bring your Avalonia planner state?'), findsOneWidget);
    expect(find.byType(WorldRootStartupAnimation), findsNothing);
    expect(find.byKey(const ValueKey('migration-start-fresh')), findsOneWidget);
    expect(find.byKey(const ValueKey('migration-import-copy')), findsOneWidget);
    _expectOwnedStartupFrame(
      tester,
      find.text(
        'This is a read-only preview. Nothing has been imported, archived, moved, or changed yet.',
      ),
    );
    _expectNoGenericStartupControls();

    await tester.ensureVisible(
      find.byKey(const ValueKey('migration-start-fresh')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('migration-start-fresh')));
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(DraggableModalRouteSurface), findsOneWidget);
    final draggableDialog = find.byType(DraggableModalRouteSurface);
    final dialogSurface = tester.widget<AppSurface>(
      find.descendant(of: draggableDialog, matching: find.byType(AppSurface)),
    );
    expect(dialogSurface.role, AppSurfaceRole.modal);
    expect(dialogSurface.tone, AppSurfaceTone.warning);
    expect(
      find.byKey(const ValueKey('migration-confirm-cancel')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('migration-confirm-fresh')),
      findsOneWidget,
    );
    final dialogSurfaceFinder = find.descendant(
      of: draggableDialog,
      matching: find.byType(AppSurface),
    );
    final dialogBefore = tester.getRect(dialogSurfaceFinder);
    await tester.drag(
      find.byKey(const ValueKey('migration-confirm-drag')),
      const Offset(32, 20),
    );
    await tester.pump();
    expect(
      tester.getRect(dialogSurfaceFinder).topLeft,
      dialogBefore.topLeft + const Offset(32, 20),
    );

    await tester.tap(find.byKey(const ValueKey('migration-confirm-cancel')));
    await tester.pumpAndSettle();
    expect(find.text('Bring your Avalonia planner state?'), findsOneWidget);

    await tester.ensureVisible(
      find.byKey(const ValueKey('migration-start-fresh')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('migration-start-fresh')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('migration-confirm-fresh')));
    await tester.pumpAndSettle();

    expect(find.text('Clean profile created'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('migration-report-title')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('migration-report-continue')),
      findsOneWidget,
    );
    _expectOwnedStartupFrame(
      tester,
      find.text(
        'No Avalonia data was imported. The original Avalonia state remains available and untouched.',
      ),
    );
    _expectNoGenericStartupControls();

    await tester.ensureVisible(
      find.byKey(const ValueKey('migration-report-continue')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('migration-report-continue')));
    await tester.pumpAndSettle();

    expect(find.byType(FirstRunSetupView), findsOneWidget);
    expect(find.text('Set up your planner'), findsOneWidget);
    expect(find.text('Mastery'), findsOneWidget);
    _expectOwnedStartupFrame(tester, find.text('Set up your planner'));
  });
}

void _expectOwnedStartupFrame(WidgetTester tester, Finder bodyText) {
  expect(find.byType(AppTitleBar), findsOneWidget);
  expect(find.byKey(AppTitleBar.materialKey), findsOneWidget);
  expect(bodyText, findsOneWidget);
  expect(
    find.ancestor(of: bodyText, matching: find.byType(Material)),
    findsOneWidget,
  );

  final inherited = DefaultTextStyle.of(tester.element(bodyText)).style;
  expect(inherited.color, SakuraNightGardenSpec.typography.body.color);
  expect(
    inherited.fontFamily,
    SakuraNightGardenSpec.typography.body.fontFamily,
  );
  expect(inherited.fontSize, SakuraNightGardenSpec.typography.body.fontSize);
  expect(inherited.decoration, isNot(TextDecoration.underline));
}

void _expectNoGenericStartupControls() {
  expect(find.byType(Scaffold), findsNothing);
  expect(find.byType(Card), findsNothing);
  expect(find.byType(AlertDialog), findsNothing);
  expect(find.byType(ElevatedButton), findsNothing);
  expect(find.byType(FilledButton), findsNothing);
  expect(find.byType(OutlinedButton), findsNothing);
  expect(find.byType(TextButton), findsNothing);
}

CatalogSnapshot _catalog() => CatalogSnapshot(
  sourceSha256: 'fixture',
  sourceByteCount: 1,
  alchemy: _mode(CraftMode.alchemy, 'Alchemy Target'),
  cooking: _mode(CraftMode.cooking, 'Cooking Target'),
  processing: _mode(CraftMode.processing, 'Processing Target'),
  supportingData: const <String, Object?>{},
  collisions: const <CaseCollision>[],
);

ModeCatalog _mode(CraftMode mode, String target) => ModeCatalog(
  mode: mode,
  items: <String, Recipe>{target: _recipe(target, mode)},
  iconDataUris: const <String, String>{},
  defaults: <String, Object?>{
    'target': target,
    'want': 100,
    'yieldMult': mode == CraftMode.alchemy ? 3.2 : 1,
    'inv': const <String, double>{},
    'favoriteRecipes': <String>[target],
  },
  metadata: const <String, Object?>{},
  searchAliases: const <String, String>{},
);

Recipe _recipe(String name, CraftMode mode) => Recipe(
  name: name,
  type: mode.key,
  baseOutput: 1,
  group: null,
  method: null,
  ingredients: <Ingredient>[
    Ingredient(
      name: 'Base',
      quantity: 1,
      options: <String>[],
      substituteGroup: null,
      substituteRatios: <String, double>{},
    ),
  ],
  marketId: null,
  sourceNote: null,
  vendor: null,
  location: null,
  npcPrice: 0,
  qualityBase: null,
  qualityGrade: null,
  outputMinimum: 1,
  outputMaximum: 1,
);
