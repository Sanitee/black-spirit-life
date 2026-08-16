import 'dart:io';

import 'package:bdo_craft_planner_flutter/app/appearance/appearance_actions.dart';
import 'package:bdo_craft_planner_flutter/app/application_bootstrap.dart';
import 'package:bdo_craft_planner_flutter/app/first_run_setup.dart';
import 'package:bdo_craft_planner_flutter/app/state/planner_application_controller.dart';
import 'package:bdo_craft_planner_flutter/app_identity.dart';
import 'package:bdo_craft_planner_flutter/data/catalog/bundled_catalog_parser.dart';
import 'package:bdo_craft_planner_flutter/data/persistence/personal_data_location_service.dart';
import 'package:bdo_craft_planner_flutter/data/persistence/planner_state_repository.dart';
import 'package:bdo_craft_planner_flutter/domain/market/market_cancellation.dart';
import 'package:bdo_craft_planner_flutter/domain/market/market_price_gateway.dart';
import 'package:bdo_craft_planner_flutter/domain/market/market_price_models.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/domain/planner/mastery_yields.dart';
import 'package:bdo_craft_planner_flutter/domain/state/planner_state.dart';
import 'package:bdo_craft_planner_flutter/domain/state/state_copy.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final class ApplicationTestHarness {
  ApplicationTestHarness._({
    required this.temporaryDirectory,
    required this.bundle,
  });

  final Directory temporaryDirectory;
  final ApplicationBundle bundle;

  static Future<ApplicationTestHarness> create({
    String? backgroundId,
    CraftMode activeMode = CraftMode.alchemy,
    String view = 'plan',
    bool setupCompleted = true,
    bool showDeleteTools = false,
    SavePlannerState Function(PlannerStateRepository repository)?
    saveStateFactory,
  }) async {
    final temporaryDirectory = await Directory.systemTemp.createTemp(
      'bdo-application-workspace-',
    );
    final catalog = const BundledCatalogParser().parse(
      await File('assets/data/app-data.json').readAsString(),
    );
    final repository = PlannerStateRepository(
      paths: PlannerStatePathPolicy(
        applicationDirectory: Directory(
          '${temporaryDirectory.path}${Platform.pathSeparator}state',
        ),
        legacyStateFile: File(
          '${temporaryDirectory.path}${Platform.pathSeparator}legacy${Platform.pathSeparator}planner-state.json',
        ),
      ),
      applicationVersion: 'test',
      utcNow: () => DateTime.utc(2026, 7, 20, 12),
    );
    final load = await repository.load(catalog);
    var state = backgroundId == null
        ? load.state
        : AppearanceActions.selectSharedBackground(load.state, backgroundId);
    state = _replaceMode(
      state.copyWith(activeMode: activeMode, showDeleteTools: showDeleteTools),
      activeMode,
      state.forMode(activeMode).copyWith(view: view),
    );
    if (setupCompleted) state = _markSetupCompleted(state);
    final controller = PlannerApplicationController(
      catalog: catalog,
      initialState: state,
      saveState: saveStateFactory?.call(repository) ?? (value) async => value,
      saveDebounce: Duration.zero,
    );
    return ApplicationTestHarness._(
      temporaryDirectory: temporaryDirectory,
      bundle: ApplicationBundle(
        catalog: catalog,
        stateLoad: load,
        stateRepository: repository,
        personalDataLocation: PersonalDataLocationService.fixed(
          repository.paths.applicationDirectory,
        ),
        controller: controller,
      ),
    );
  }

  Future<void> dispose() async {
    await bundle.controller.dispose();
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  }

  Future<void> disposeControllerOnly() => bundle.controller.dispose();

  /// Recreates only the reactive controller in the caller's Zone.
  ///
  /// Widget tests load the 14 MB catalog and temporary repository through
  /// `tester.runAsync`. A controller created in that real-time Zone must not
  /// later own save-chain continuations in Flutter's fake-time Zone. Rebinding
  /// after the I/O phase keeps the production controller unchanged and makes
  /// widget-test persistence/disposal deterministic.
  ApplicationTestHarness rebindControllerInCurrentZone({
    SavePlannerState Function(PlannerStateRepository repository)?
    saveStateFactory,
  }) {
    final controller = PlannerApplicationController(
      catalog: bundle.catalog,
      initialState: bundle.controller.documentSnapshot,
      saveState:
          saveStateFactory?.call(bundle.stateRepository) ??
          (value) async => value,
      saveDebounce: Duration.zero,
    );
    return ApplicationTestHarness._(
      temporaryDirectory: temporaryDirectory,
      bundle: ApplicationBundle(
        catalog: bundle.catalog,
        stateLoad: bundle.stateLoad,
        stateRepository: bundle.stateRepository,
        personalDataLocation: bundle.personalDataLocation,
        controller: controller,
      ),
    );
  }
}

final class EmptyMarketGateway implements MarketPriceGateway {
  const EmptyMarketGateway();

  @override
  Future<MarketPriceFetchResult> fetch(
    Iterable<MarketPriceRequest> requests, {
    MarketCancellationToken? cancellationToken,
  }) async => MarketPriceFetchResult(
    region: 'eu',
    language: 'en-US',
    fetchedAt: DateTime.utc(2026, 7, 20, 12),
    items: const <MarketPriceRow>[],
    attemptedSources: const <MarketPriceSource>[],
  );
}

void configureApplicationTestSurface(
  WidgetTester tester,
  Size logicalSize, {
  double devicePixelRatio = 1,
  double textScaleFactor = 1,
}) {
  tester.view
    ..devicePixelRatio = devicePixelRatio
    ..physicalSize = Size(
      logicalSize.width * devicePixelRatio,
      logicalSize.height * devicePixelRatio,
    );
  tester.platformDispatcher.textScaleFactorTestValue = textScaleFactor;
  tester.platformDispatcher.accessibilityFeaturesTestValue =
      const FakeAccessibilityFeatures(disableAnimations: true);
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

PlannerState _replaceMode(
  PlannerState document,
  CraftMode mode,
  ModeState state,
) => switch (mode) {
  CraftMode.alchemy => document.copyWith(alchemy: state),
  CraftMode.cooking => document.copyWith(cooking: state),
  CraftMode.processing => document.copyWith(processing: state),
};

PlannerState _markSetupCompleted(PlannerState document) {
  final configured = document.copyWith(
    alchemy: document.alchemy.copyWith(
      alchemyMastery: 1900,
      compatibility: document.alchemy.compatibility.copyWith(
        alchemyYield: alchemyExpectedOutput(1900, 1, 4),
      ),
    ),
    cooking: document.cooking.copyWith(cookingMastery: 0),
    processing: document.processing.copyWith(processingMastery: 2),
  );
  final extensions = Map<String, Object?>.of(document.extensions);
  extensions[firstRunSetupExtensionKey] = <String, Object?>{
    firstRunSetupCompletedKey: true,
    firstRunSetupSchemaVersionKey: FirstRunSetupSchema.currentVersion,
    firstRunSetupCompletedBetaVersionsKey: <String, Object?>{
      AppIdentity.applicationVersion: FirstRunSetupSchema.currentVersion,
    },
  };
  return configured.copyWith(extensions: extensions);
}
