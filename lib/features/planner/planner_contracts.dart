import '../../app/state/planner_application_controller.dart';
import '../../domain/planner/planner_models.dart';

enum RecipeBookCallingContext { planner, bonus }

final class RecipeBookRequest {
  const RecipeBookRequest({
    required this.controller,
    required this.context,
    required this.allowedTargets,
  });

  final ModeFeatureController controller;
  final RecipeBookCallingContext context;
  final List<String> allowedTargets;
}

typedef OpenRecipeBook = void Function(RecipeBookRequest request);

/// The application host owns the native clipboard and the named toast. Keeping
/// the two effects behind one callback prevents a successful copy from losing
/// its user-visible confirmation.
typedef CopyPlannerName = Future<void> Function(String exactName);

/// Copies a complete, human-readable AFK loading list without treating the
/// multi-line payload as an item name in the host's copy confirmation.
typedef CopyAfkLoad = Future<void> Function(String text);

/// Opens the one shared character-weight profile in Craft Profile.
typedef OpenAfkWeightSettings = void Function();

final class PlannerMarketRequest {
  const PlannerMarketRequest({
    required this.controller,
    required this.materials,
    this.materialNames = const <String>[],
  });

  final ModeFeatureController controller;
  final List<MissingMaterial> materials;
  final List<String> materialNames;

  /// The retained application refreshes every currently visible material and
  /// every substitute that can replace it. Refreshing only the selected name
  /// leaves alternatives on stale cached prices, which can make the planner
  /// silently choose a different substitute when the refresh completes.
  Iterable<String> get namesForRefresh sync* {
    yield* materialNames;
    for (final material in materials) {
      yield material.name;
      final choice = material.choice;
      if (choice != null) yield* choice.options;
    }
  }
}

final class PlannerMarketRefresh {
  const PlannerMarketRefresh({
    required this.prices,
    required this.stock,
    required this.unlistedItemNames,
    required this.fetchedAt,
    required this.summary,
    this.region = 'eu',
    this.tradeMarketIds = const <String, String>{},
    this.totalTrades = const <String, int>{},
    this.tradeObservedAt = const <String, int>{},
    this.observedDailyTrades = const <String, double>{},
    this.tradeObservationHours = const <String, double>{},
    this.lastSoldAtEpochSeconds = const <String, int>{},
    this.rowDiagnostics = const <String, List<PlannerMarketRowDiagnostic>>{},
  });

  final Map<String, double> prices;
  final Map<String, double> stock;
  final Set<String> unlistedItemNames;
  final int fetchedAt;
  final String summary;
  final String region;
  final Map<String, String> tradeMarketIds;
  final Map<String, int> totalTrades;
  final Map<String, int> tradeObservedAt;
  final Map<String, double> observedDailyTrades;
  final Map<String, double> tradeObservationHours;
  final Map<String, int> lastSoldAtEpochSeconds;
  final Map<String, List<PlannerMarketRowDiagnostic>> rowDiagnostics;
}

enum PlannerMarketDiagnosticSeverity { info, warning, error }

final class PlannerMarketRowDiagnostic {
  const PlannerMarketRowDiagnostic({
    required this.message,
    required this.severity,
    this.isMarketUnlisted = false,
  });

  final String message;
  final PlannerMarketDiagnosticSeverity severity;

  /// True only after the market gateway confirms that the item cannot be
  /// registered. Missing IDs and transient request failures must leave this
  /// false so the UI does not hide otherwise useful cached market values.
  final bool isMarketUnlisted;
}

typedef CheckPlannerPrices =
    Future<PlannerMarketRefresh> Function(PlannerMarketRequest request);

enum PlannerMapLookupSource { npcVendors, manualGathering, workerNodes }

final class PlannerMapLookupAvailability {
  const PlannerMapLookupAvailability({
    required this.materialName,
    this.hasNpcVendors = false,
    this.npcVendorCount = 0,
    this.hasManualGathering = false,
    this.manualResourceId,
    this.manualLocationCount = 0,
    this.hasWorkerNodes = false,
    this.workerResourceId,
    this.workerNodeCount = 0,
  });

  final String materialName;
  final bool hasNpcVendors;
  final int npcVendorCount;
  final bool hasManualGathering;
  final String? manualResourceId;
  final int manualLocationCount;
  final bool hasWorkerNodes;
  final String? workerResourceId;
  final int workerNodeCount;

  bool get hasAnySource =>
      hasNpcVendors || hasManualGathering || hasWorkerNodes;

  String? resourceIdFor(PlannerMapLookupSource source) => switch (source) {
    PlannerMapLookupSource.npcVendors => null,
    PlannerMapLookupSource.manualGathering => manualResourceId,
    PlannerMapLookupSource.workerNodes => workerResourceId,
  };
}

final class PlannerMapLookupRequest {
  const PlannerMapLookupRequest({
    required this.materialName,
    required this.source,
    this.resourceId,
  });

  final String materialName;
  final String? resourceId;
  final PlannerMapLookupSource source;
}

typedef ResolvePlannerMapLookup =
    Future<PlannerMapLookupAvailability> Function(String materialName);
typedef OpenPlannerMapLookup = void Function(PlannerMapLookupRequest request);
typedef AddPlannerGatherChecklistItem =
    void Function(PlannerMapLookupAvailability availability);
typedef AddPlannerWorkerNetworkMaterial =
    void Function(PlannerMapLookupAvailability availability);

final class PlannerSourceInfoRequest {
  const PlannerSourceInfoRequest({
    required this.name,
    required this.category,
    required this.role,
    required this.sourceNote,
    required this.vendor,
    required this.location,
    required this.npcPrice,
  });

  final String name;
  final String category;
  final String role;
  final String? sourceNote;
  final String? vendor;
  final String? location;
  final double npcPrice;

  /// The compact `?` action is reserved for dependable, always-available NPC
  /// sources. Market and gathering guidance belongs in the item's map actions.
  bool get hasDetails =>
      vendor?.trim().isNotEmpty == true ||
      sourceNote?.trim().isNotEmpty == true;
}

final class PlannerExternalActions {
  const PlannerExternalActions({
    required this.openRecipeBook,
    required this.copyName,
    required this.checkPrices,
    this.resolveMapLookup,
    this.openMapLookup,
    this.addToGatherChecklist,
    this.addToPlannedNetwork,
    this.copyAfkLoad,
    this.openAfkWeightSettings,
  });

  final OpenRecipeBook openRecipeBook;
  final CopyPlannerName copyName;
  final CheckPlannerPrices checkPrices;
  final ResolvePlannerMapLookup? resolveMapLookup;
  final OpenPlannerMapLookup? openMapLookup;
  final AddPlannerGatherChecklistItem? addToGatherChecklist;
  final AddPlannerWorkerNetworkMaterial? addToPlannedNetwork;
  final CopyAfkLoad? copyAfkLoad;
  final OpenAfkWeightSettings? openAfkWeightSettings;
}
