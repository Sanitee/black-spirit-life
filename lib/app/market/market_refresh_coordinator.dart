import '../../data/catalog/catalog_repository.dart';
import '../../domain/market/market_cancellation.dart';
import '../../domain/market/market_price_gateway.dart';
import '../../domain/market/market_price_models.dart';
import '../../domain/models/catalog_models.dart';
import '../../domain/models/craft_mode.dart';
import '../../domain/state/planner_state.dart';

enum MarketRefreshStatus {
  updated,
  partiallyUpdated,
  noMarketListings,
  noResolvableItems,
  failed,
  cancelled,
}

enum MarketRefreshDiagnosticCode {
  emptyMaterialName,
  duplicateMaterialName,
  duplicateMarketId,
  unresolvedMarketId,
  invalidMarketId,
  marketUnlisted,
  rowFailure,
  missingResponse,
  unexpectedResponse,
  unusableSuccessfulRow,
  gatewayFailure,
  cancelled,
}

final class MarketRefreshDiagnostic {
  const MarketRefreshDiagnostic({
    required this.code,
    required this.message,
    this.materialName,
    this.marketId,
    this.gatewayCode,
    this.relatedMaterialNames = const <String>[],
  });

  final MarketRefreshDiagnosticCode code;
  final String message;
  final String? materialName;
  final String? marketId;
  final MarketDiagnosticCode? gatewayCode;
  final List<String> relatedMaterialNames;
}

final class MarketRefreshSummary {
  const MarketRefreshSummary({
    required this.status,
    required this.requestedNameCount,
    required this.uniqueNameCount,
    required this.resolvedMaterialCount,
    required this.requestCount,
    required this.successfulRequestCount,
    required this.failedRequestCount,
    required this.unlistedRequestCount,
    required this.updatedMaterialCount,
    required this.unresolvedMaterialCount,
    required this.duplicateNameCount,
    required this.duplicateIdCount,
    required this.unknownStockCount,
  });

  final MarketRefreshStatus status;
  final int requestedNameCount;
  final int uniqueNameCount;
  final int resolvedMaterialCount;
  final int requestCount;
  final int successfulRequestCount;
  final int failedRequestCount;
  final int unlistedRequestCount;
  final int updatedMaterialCount;
  final int unresolvedMaterialCount;
  final int duplicateNameCount;
  final int duplicateIdCount;
  final int unknownStockCount;

  bool get hasUpdates => updatedMaterialCount > 0;

  String get message => switch (status) {
    MarketRefreshStatus.updated =>
      'Market updated for $updatedMaterialCount material(s).',
    MarketRefreshStatus.partiallyUpdated =>
      'Market updated for $updatedMaterialCount material(s); '
          '$failedRequestCount request(s) failed and '
          '$unresolvedMaterialCount material(s) need a market ID.',
    MarketRefreshStatus.noMarketListings =>
      'None of the requested materials are registered on the Central Market.',
    MarketRefreshStatus.noResolvableItems =>
      'No requested materials have a usable market ID. Add or correct the '
          'market ID in item metadata, then retry.',
    MarketRefreshStatus.failed =>
      'The market check returned no usable updates. Existing cached values '
          'were kept.',
    MarketRefreshStatus.cancelled =>
      'The market check was cancelled. Existing cached values were kept.',
  };
}

final class MarketRefreshResult {
  MarketRefreshResult({
    required this.summary,
    required this.market,
    required List<MarketRefreshDiagnostic> diagnostics,
    this.fetchResult,
  }) : diagnostics = List<MarketRefreshDiagnostic>.unmodifiable(diagnostics);

  final MarketRefreshSummary summary;
  final MarketState market;
  final List<MarketRefreshDiagnostic> diagnostics;
  final MarketPriceFetchResult? fetchResult;

  MarketRefreshStatus get status => summary.status;
  Map<String, double> get prices => market.prices;
  Map<String, double> get stock => market.stock;
  Map<String, String> get tradeMarketIds => market.tradeMarketIds;
  Map<String, int> get totalTrades => market.totalTrades;
  Map<String, int> get tradeObservedAt => market.tradeObservedAt;
  Map<String, double> get observedDailyTrades => market.observedDailyTrades;
  Map<String, double> get tradeObservationHours => market.tradeObservationHours;
  Map<String, int> get lastSoldAtEpochSeconds => market.lastSoldAtEpochSeconds;

  /// Milliseconds since Unix epoch, directly consumable by
  /// `ModeFeatureController.replaceMarketValues`.
  int get fetchedAt => market.fetchedAt;
}

/// Resolves plan materials into bounded gateway requests and merges the
/// response into an immutable cache snapshot.
final class MarketRefreshCoordinator {
  const MarketRefreshCoordinator({
    required this.gateway,
    required this.catalogRepository,
  });

  final MarketPriceGateway gateway;
  final CatalogRepository catalogRepository;

  Future<MarketRefreshResult> refresh({
    required CraftMode mode,
    required Map<String, Recipe> assembledRecipes,
    required MarketState currentMarket,
    required Iterable<String> missingMaterialNames,
    MarketCancellationToken? cancellationToken,
  }) async {
    final resolution = _resolveRequests(
      mode: mode,
      assembledRecipes: assembledRecipes,
      names: missingMaterialNames,
    );

    if (cancellationToken?.isCancelled ?? false) {
      return _cancelled(currentMarket, resolution);
    }
    if (resolution.requests.isEmpty) {
      return MarketRefreshResult(
        summary: _summary(
          status: MarketRefreshStatus.noResolvableItems,
          resolution: resolution,
        ),
        market: _copyMarket(currentMarket),
        diagnostics: resolution.diagnostics,
      );
    }

    MarketPriceFetchResult fetched;
    try {
      fetched = await gateway.fetch(
        resolution.requests,
        cancellationToken: cancellationToken,
      );
      cancellationToken?.throwIfCancelled();
    } on MarketFetchCancelledException {
      return _cancelled(currentMarket, resolution);
    } catch (error) {
      return MarketRefreshResult(
        summary: _summary(
          status: MarketRefreshStatus.failed,
          resolution: resolution,
          failedRequestCount: resolution.requests.length,
        ),
        market: _copyMarket(currentMarket),
        diagnostics: [
          ...resolution.diagnostics,
          MarketRefreshDiagnostic(
            code: MarketRefreshDiagnosticCode.gatewayFailure,
            message:
                'The market gateway could not complete the refresh '
                '(${error.runtimeType}). Check the connection and retry.',
          ),
        ],
      );
    }

    return _merge(currentMarket, resolution, fetched);
  }

  _ResolutionPlan _resolveRequests({
    required CraftMode mode,
    required Map<String, Recipe> assembledRecipes,
    required Iterable<String> names,
  }) {
    final requests = <MarketPriceRequest>[];
    final materialNamesById = <String, List<String>>{};
    final diagnostics = <MarketRefreshDiagnostic>[];
    final seenNames = <String>{};
    final supporting = catalogRepository.snapshot.supportingData;
    final idResolver = _MarketIdResolver(
      catalogRecipes: catalogRepository.snapshot.forMode(mode).items,
      marketIds: _stringMap(supporting['marketIds']),
      normalizedIds: _stringMap(supporting['marketNameIds']),
      aliases: _FoldedStringLookup(_stringMap(supporting['marketNameAliases'])),
    );
    var requestedNameCount = 0;
    var duplicateNameCount = 0;
    var duplicateIdCount = 0;
    var unresolvedMaterialCount = 0;
    var resolvedMaterialCount = 0;

    for (final rawName in names) {
      requestedNameCount++;
      final name = rawName.trim();
      if (name.isEmpty) {
        unresolvedMaterialCount++;
        diagnostics.add(
          const MarketRefreshDiagnostic(
            code: MarketRefreshDiagnosticCode.emptyMaterialName,
            message: 'An empty material name was skipped.',
          ),
        );
        continue;
      }
      if (!seenNames.add(name)) {
        duplicateNameCount++;
        diagnostics.add(
          MarketRefreshDiagnostic(
            code: MarketRefreshDiagnosticCode.duplicateMaterialName,
            materialName: name,
            message: '$name was requested more than once and was deduplicated.',
          ),
        );
        continue;
      }

      final resolved = _resolveId(
        assembledRecipes: assembledRecipes,
        name: name,
        resolver: idResolver,
      );
      if (resolved.id == null) {
        unresolvedMaterialCount++;
        diagnostics.add(
          MarketRefreshDiagnostic(
            code: resolved.hadInvalidCandidate
                ? MarketRefreshDiagnosticCode.invalidMarketId
                : MarketRefreshDiagnosticCode.unresolvedMarketId,
            materialName: name,
            message: resolved.hadInvalidCandidate
                ? '$name has a non-positive or non-decimal market ID. Correct '
                      'the item metadata before checking prices again.'
                : 'No market ID was found for $name. Add one in item metadata '
                      'before checking prices again.',
          ),
        );
        continue;
      }

      resolvedMaterialCount++;
      final targets = materialNamesById.putIfAbsent(resolved.id!, () {
        requests.add(MarketPriceRequest(name: name, id: resolved.id!));
        return <String>[];
      });
      if (targets.isNotEmpty) {
        duplicateIdCount++;
        diagnostics.add(
          MarketRefreshDiagnostic(
            code: MarketRefreshDiagnosticCode.duplicateMarketId,
            materialName: name,
            marketId: resolved.id,
            message:
                '$name shares market ID ${resolved.id} with ${targets.first}; '
                'one gateway request will update both cache entries.',
          ),
        );
      }
      if (!targets.contains(name)) targets.add(name);
    }

    return _ResolutionPlan(
      requests: requests,
      materialNamesById: materialNamesById,
      diagnostics: diagnostics,
      requestedNameCount: requestedNameCount,
      uniqueNameCount: seenNames.length,
      resolvedMaterialCount: resolvedMaterialCount,
      unresolvedMaterialCount: unresolvedMaterialCount,
      duplicateNameCount: duplicateNameCount,
      duplicateIdCount: duplicateIdCount,
    );
  }

  _ResolvedId _resolveId({
    required Map<String, Recipe> assembledRecipes,
    required String name,
    required _MarketIdResolver resolver,
  }) {
    final alias = resolver.aliases.find(name);
    final catalogRecipe = resolver.catalogRecipes[name];
    final candidates = <String?>[
      assembledRecipes[name]?.marketId,
      catalogRecipe?.marketId,
      resolver.marketIds[name],
      if (alias != null) resolver.marketIds[alias],
      resolver.normalizedIds[normalizeMarketName(name)],
      if (alias != null) resolver.normalizedIds[normalizeMarketName(alias)],
    ];
    var hadInvalidCandidate = false;
    for (final candidate in candidates) {
      if (candidate == null || candidate.trim().isEmpty) continue;
      final normalized = normalizeNumericMarketId(candidate);
      if (normalized != null) {
        return _ResolvedId(
          id: normalized,
          hadInvalidCandidate: hadInvalidCandidate,
        );
      }
      hadInvalidCandidate = true;
    }
    return _ResolvedId(id: null, hadInvalidCandidate: hadInvalidCandidate);
  }

  MarketRefreshResult _merge(
    MarketState current,
    _ResolutionPlan resolution,
    MarketPriceFetchResult fetched,
  ) {
    final prices = Map<String, double>.of(current.prices);
    final stock = Map<String, double>.of(current.stock);
    final tradeMarketIds = Map<String, String>.of(current.tradeMarketIds);
    final totalTrades = Map<String, int>.of(current.totalTrades);
    final tradeObservedAt = Map<String, int>.of(current.tradeObservedAt);
    final observedDailyTrades = Map<String, double>.of(
      current.observedDailyTrades,
    );
    final tradeObservationHours = Map<String, double>.of(
      current.tradeObservationHours,
    );
    final lastSoldAtEpochSeconds = Map<String, int>.of(
      current.lastSoldAtEpochSeconds,
    );
    final unlistedItemNames = Set<String>.of(current.unlistedItemNames);
    final diagnostics = <MarketRefreshDiagnostic>[...resolution.diagnostics];
    final respondedIds = <String>{};
    final successfulIds = <String>{};
    final unlistedIds = <String>{};
    var updatedMaterialCount = 0;
    var unknownStockCount = 0;

    for (final row in fetched.items) {
      final id = normalizeNumericMarketId(row.id);
      final targets = id == null ? null : resolution.materialNamesById[id];
      if (id == null || targets == null) {
        diagnostics.add(
          MarketRefreshDiagnostic(
            code: MarketRefreshDiagnosticCode.unexpectedResponse,
            materialName: row.name,
            marketId: row.id,
            message:
                'The gateway returned an unrequested or invalid market ID '
                '(${row.id}); that row was ignored.',
          ),
        );
        continue;
      }
      if (!respondedIds.add(id)) {
        diagnostics.add(
          MarketRefreshDiagnostic(
            code: MarketRefreshDiagnosticCode.unexpectedResponse,
            materialName: row.name,
            marketId: id,
            message:
                'The gateway returned market ID $id more than once; only the '
                'first row was used.',
          ),
        );
        continue;
      }
      if (!row.ok) {
        if (_isExpectedUnlisted(row.diagnosticCode)) {
          unlistedIds.add(id);
          for (final target in targets) {
            prices.remove(target);
            stock.remove(target);
            tradeMarketIds.remove(target);
            totalTrades.remove(target);
            tradeObservedAt.remove(target);
            observedDailyTrades.remove(target);
            tradeObservationHours.remove(target);
            lastSoldAtEpochSeconds.remove(target);
            unlistedItemNames.add(_marketItemKey(target));
          }
          diagnostics.add(
            MarketRefreshDiagnostic(
              code: MarketRefreshDiagnosticCode.marketUnlisted,
              materialName: targets.first,
              marketId: id,
              gatewayCode: row.diagnosticCode,
              relatedMaterialNames: targets,
              message: "Can't be registered on the Central Market.",
            ),
          );
          continue;
        }
        diagnostics.add(
          MarketRefreshDiagnostic(
            code: MarketRefreshDiagnosticCode.rowFailure,
            materialName: targets.first,
            marketId: id,
            gatewayCode: row.diagnosticCode,
            relatedMaterialNames: targets,
            message:
                'No market update was available for ${targets.join(', ')} '
                '(${row.diagnosticCode.name}). Existing values were kept.',
          ),
        );
        continue;
      }

      for (final target in targets) {
        unlistedItemNames.remove(_marketItemKey(target));
      }
      var appliedAnyField = false;
      if (row.price > 0) {
        for (final target in targets) {
          prices[target] = row.price.toDouble();
        }
        appliedAnyField = true;
      }
      if (row.stock != null) {
        for (final target in targets) {
          stock[target] = row.stock!.toDouble();
        }
        appliedAnyField = true;
      } else {
        unknownStockCount += targets.length;
      }
      for (final target in targets) {
        if (_mergeTradeEvidence(
          target: target,
          marketId: id,
          row: row,
          tradeMarketIds: tradeMarketIds,
          totalTrades: totalTrades,
          tradeObservedAt: tradeObservedAt,
          observedDailyTrades: observedDailyTrades,
          tradeObservationHours: tradeObservationHours,
          lastSoldAtEpochSeconds: lastSoldAtEpochSeconds,
        )) {
          appliedAnyField = true;
        }
      }
      if (!appliedAnyField) {
        diagnostics.add(
          MarketRefreshDiagnostic(
            code: MarketRefreshDiagnosticCode.unusableSuccessfulRow,
            materialName: targets.first,
            marketId: id,
            relatedMaterialNames: targets,
            message:
                'The successful response for ${targets.join(', ')} contained '
                'neither a usable price nor known stock. Existing values were '
                'kept.',
          ),
        );
        continue;
      }
      successfulIds.add(id);
      updatedMaterialCount += targets.length;
    }

    for (final request in resolution.requests) {
      if (respondedIds.contains(request.id)) continue;
      diagnostics.add(
        MarketRefreshDiagnostic(
          code: MarketRefreshDiagnosticCode.missingResponse,
          materialName: request.name,
          marketId: request.id,
          relatedMaterialNames: resolution.materialNamesById[request.id]!,
          message:
              'The gateway did not return market ID ${request.id}. Existing '
              'values for ${resolution.materialNamesById[request.id]!.join(', ')} '
              'were kept.',
        ),
      );
    }

    final failedRequestCount =
        resolution.requests.length - successfulIds.length - unlistedIds.length;
    if (successfulIds.isEmpty && failedRequestCount > 0) {
      return MarketRefreshResult(
        summary: _summary(
          status: MarketRefreshStatus.failed,
          resolution: resolution,
          failedRequestCount: failedRequestCount,
          unlistedRequestCount: unlistedIds.length,
          unknownStockCount: unknownStockCount,
        ),
        market: _copyMarket(
          current,
          prices: prices,
          stock: stock,
          tradeMarketIds: tradeMarketIds,
          totalTrades: totalTrades,
          tradeObservedAt: tradeObservedAt,
          observedDailyTrades: observedDailyTrades,
          tradeObservationHours: tradeObservationHours,
          lastSoldAtEpochSeconds: lastSoldAtEpochSeconds,
          unlistedItemNames: unlistedItemNames,
        ),
        diagnostics: diagnostics,
        fetchResult: fetched,
      );
    }

    final status =
        failedRequestCount > 0 || resolution.unresolvedMaterialCount > 0
        ? MarketRefreshStatus.partiallyUpdated
        : successfulIds.isEmpty
        ? MarketRefreshStatus.noMarketListings
        : MarketRefreshStatus.updated;
    final fetchedAt = fetched.fetchedAt.millisecondsSinceEpoch;
    final updatedMarket = _copyMarket(
      current,
      prices: prices,
      stock: stock,
      tradeMarketIds: tradeMarketIds,
      totalTrades: totalTrades,
      tradeObservedAt: tradeObservedAt,
      observedDailyTrades: observedDailyTrades,
      tradeObservationHours: tradeObservationHours,
      lastSoldAtEpochSeconds: lastSoldAtEpochSeconds,
      unlistedItemNames: unlistedItemNames,
      fetchedAt: fetchedAt,
      region: fetched.region,
    );
    return MarketRefreshResult(
      summary: _summary(
        status: status,
        resolution: resolution,
        successfulRequestCount: successfulIds.length,
        failedRequestCount: failedRequestCount,
        unlistedRequestCount: unlistedIds.length,
        updatedMaterialCount: updatedMaterialCount,
        unknownStockCount: unknownStockCount,
      ),
      market: updatedMarket,
      diagnostics: diagnostics,
      fetchResult: fetched,
    );
  }

  MarketRefreshResult _cancelled(
    MarketState current,
    _ResolutionPlan resolution,
  ) => MarketRefreshResult(
    summary: _summary(
      status: MarketRefreshStatus.cancelled,
      resolution: resolution,
    ),
    market: _copyMarket(current),
    diagnostics: [
      ...resolution.diagnostics,
      const MarketRefreshDiagnostic(
        code: MarketRefreshDiagnosticCode.cancelled,
        message:
            'The market refresh was cancelled; no cached prices or stock were '
            'changed.',
      ),
    ],
  );
}

MarketRefreshSummary _summary({
  required MarketRefreshStatus status,
  required _ResolutionPlan resolution,
  int successfulRequestCount = 0,
  int failedRequestCount = 0,
  int unlistedRequestCount = 0,
  int updatedMaterialCount = 0,
  int unknownStockCount = 0,
}) => MarketRefreshSummary(
  status: status,
  requestedNameCount: resolution.requestedNameCount,
  uniqueNameCount: resolution.uniqueNameCount,
  resolvedMaterialCount: resolution.resolvedMaterialCount,
  requestCount: resolution.requests.length,
  successfulRequestCount: successfulRequestCount,
  failedRequestCount: failedRequestCount,
  unlistedRequestCount: unlistedRequestCount,
  updatedMaterialCount: updatedMaterialCount,
  unresolvedMaterialCount: resolution.unresolvedMaterialCount,
  duplicateNameCount: resolution.duplicateNameCount,
  duplicateIdCount: resolution.duplicateIdCount,
  unknownStockCount: unknownStockCount,
);

bool _mergeTradeEvidence({
  required String target,
  required String marketId,
  required MarketPriceRow row,
  required Map<String, String> tradeMarketIds,
  required Map<String, int> totalTrades,
  required Map<String, int> tradeObservedAt,
  required Map<String, double> observedDailyTrades,
  required Map<String, double> tradeObservationHours,
  required Map<String, int> lastSoldAtEpochSeconds,
}) {
  final previousMarketId = tradeMarketIds[target];
  final hasStoredEvidence =
      previousMarketId != null ||
      totalTrades.containsKey(target) ||
      tradeObservedAt.containsKey(target) ||
      observedDailyTrades.containsKey(target) ||
      tradeObservationHours.containsKey(target) ||
      lastSoldAtEpochSeconds.containsKey(target);
  final hasNewEvidence =
      row.totalTrades != null || row.lastSoldAtEpochSeconds != null;
  var changed = false;

  // A material can be remapped to a different Central Market ID. Old counters
  // must not be compared with the replacement item's counter.
  if (hasStoredEvidence && previousMarketId != marketId) {
    tradeMarketIds.remove(target);
    totalTrades.remove(target);
    tradeObservedAt.remove(target);
    observedDailyTrades.remove(target);
    tradeObservationHours.remove(target);
    lastSoldAtEpochSeconds.remove(target);
    changed = true;
  }
  if (!hasNewEvidence) return changed;

  if (tradeMarketIds[target] != marketId) {
    tradeMarketIds[target] = marketId;
    changed = true;
  }

  final nextTotal = row.totalTrades;
  final observedAt = row.fetchedAt.millisecondsSinceEpoch;
  if (nextTotal != null && observedAt >= 0) {
    final previousTotal = totalTrades[target];
    final previousObservedAt = tradeObservedAt[target];
    if (previousTotal == null || previousObservedAt == null) {
      totalTrades[target] = nextTotal;
      tradeObservedAt[target] = observedAt;
      observedDailyTrades.remove(target);
      tradeObservationHours.remove(target);
      changed = true;
    } else if (observedAt > previousObservedAt) {
      final elapsedMilliseconds = observedAt - previousObservedAt;
      if (nextTotal >= previousTotal) {
        final delta = nextTotal - previousTotal;
        observedDailyTrades[target] =
            delta.toDouble() *
            Duration.millisecondsPerDay /
            elapsedMilliseconds;
        tradeObservationHours[target] =
            elapsedMilliseconds / Duration.millisecondsPerHour;
      } else {
        // Maintenance, an upstream reset, or a corrected counter starts a new
        // baseline. Never surface a negative or stale demand estimate.
        observedDailyTrades.remove(target);
        tradeObservationHours.remove(target);
      }
      totalTrades[target] = nextTotal;
      tradeObservedAt[target] = observedAt;
      changed = true;
    }
  }

  final nextLastSoldAt = row.lastSoldAtEpochSeconds;
  final previousLastSoldAt = lastSoldAtEpochSeconds[target];
  if (nextLastSoldAt != null &&
      (previousLastSoldAt == null || nextLastSoldAt > previousLastSoldAt)) {
    lastSoldAtEpochSeconds[target] = nextLastSoldAt;
    changed = true;
  }
  return changed;
}

MarketState _copyMarket(
  MarketState source, {
  Map<String, double>? prices,
  Map<String, double>? stock,
  Map<String, String>? tradeMarketIds,
  Map<String, int>? totalTrades,
  Map<String, int>? tradeObservedAt,
  Map<String, double>? observedDailyTrades,
  Map<String, double>? tradeObservationHours,
  Map<String, int>? lastSoldAtEpochSeconds,
  Iterable<String>? unlistedItemNames,
  int? fetchedAt,
  String? region,
}) => MarketState(
  prices: prices ?? source.prices,
  stock: stock ?? source.stock,
  tradeMarketIds: tradeMarketIds ?? source.tradeMarketIds,
  totalTrades: totalTrades ?? source.totalTrades,
  tradeObservedAt: tradeObservedAt ?? source.tradeObservedAt,
  observedDailyTrades: observedDailyTrades ?? source.observedDailyTrades,
  tradeObservationHours: tradeObservationHours ?? source.tradeObservationHours,
  lastSoldAtEpochSeconds:
      lastSoldAtEpochSeconds ?? source.lastSoldAtEpochSeconds,
  unlistedItemNames: unlistedItemNames ?? source.unlistedItemNames,
  search: source.search,
  sort: source.sort,
  amount: source.amount,
  selected: source.selected,
  fetchedAt: fetchedAt ?? source.fetchedAt,
  region: region ?? source.region,
  extensions: source.extensions,
);

bool _isExpectedUnlisted(MarketDiagnosticCode code) =>
    code == MarketDiagnosticCode.itemMissing ||
    code == MarketDiagnosticCode.unusablePrice;

String _marketItemKey(String name) => name.trim().toLowerCase();

Map<String, String> _stringMap(Object? value) {
  if (value is! Map) return const <String, String>{};
  return value.map((key, item) => MapEntry('$key', '$item'));
}

final class _MarketIdResolver {
  const _MarketIdResolver({
    required this.catalogRecipes,
    required this.marketIds,
    required this.normalizedIds,
    required this.aliases,
  });

  final Map<String, Recipe> catalogRecipes;
  final Map<String, String> marketIds;
  final Map<String, String> normalizedIds;
  final _FoldedStringLookup aliases;
}

final class _FoldedStringLookup {
  _FoldedStringLookup(Map<String, String> values) : _exact = values {
    final entries = values.entries.toList()
      ..sort((left, right) => left.key.compareTo(right.key));
    final folded = <String, String>{};
    for (final entry in entries) {
      folded.putIfAbsent(entry.key.toLowerCase(), () => entry.value);
    }
    _folded = folded;
  }

  final Map<String, String> _exact;
  late final Map<String, String> _folded;

  String? find(String name) {
    final exact = _exact[name];
    if (exact != null && exact.trim().isNotEmpty) return exact;
    return _folded[name.toLowerCase()];
  }
}

final class _ResolvedId {
  const _ResolvedId({required this.id, required this.hadInvalidCandidate});

  final String? id;
  final bool hadInvalidCandidate;
}

final class _ResolutionPlan {
  _ResolutionPlan({
    required List<MarketPriceRequest> requests,
    required Map<String, List<String>> materialNamesById,
    required List<MarketRefreshDiagnostic> diagnostics,
    required this.requestedNameCount,
    required this.uniqueNameCount,
    required this.resolvedMaterialCount,
    required this.unresolvedMaterialCount,
    required this.duplicateNameCount,
    required this.duplicateIdCount,
  }) : requests = List<MarketPriceRequest>.unmodifiable(requests),
       materialNamesById = Map<String, List<String>>.unmodifiable({
         for (final entry in materialNamesById.entries)
           entry.key: List<String>.unmodifiable(entry.value),
       }),
       diagnostics = List<MarketRefreshDiagnostic>.unmodifiable(diagnostics);

  final List<MarketPriceRequest> requests;
  final Map<String, List<String>> materialNamesById;
  final List<MarketRefreshDiagnostic> diagnostics;
  final int requestedNameCount;
  final int uniqueNameCount;
  final int resolvedMaterialCount;
  final int unresolvedMaterialCount;
  final int duplicateNameCount;
  final int duplicateIdCount;
}
