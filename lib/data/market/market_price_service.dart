import '../../domain/market/market_cancellation.dart';
import '../../domain/market/market_price_gateway.dart';
import '../../domain/market/market_price_models.dart';
import 'arsha_market_source.dart';
import 'market_http_transport.dart';
import 'market_service_configuration.dart';
import 'market_source_failure.dart';
import 'pearl_abyss_market_source.dart';

final class MarketPriceService implements MarketPriceGateway {
  MarketPriceService({
    required MarketHttpTransport transport,
    this.configuration = const MarketServiceConfiguration(),
    DateTime Function()? clock,
    MarketDelay delay = defaultMarketDelay,
  }) : _clock = clock ?? DateTime.now {
    configuration.validate();
    final executor = MarketHttpExecutor(transport);
    _pearlAbyss = PearlAbyssMarketSource(
      executor: executor,
      configuration: configuration,
      clock: _clock,
    );
    _arsha = ArshaMarketSource(
      executor: executor,
      configuration: configuration,
      clock: _clock,
      delay: delay,
    );
  }

  final MarketServiceConfiguration configuration;
  final DateTime Function() _clock;
  late final PearlAbyssMarketSource _pearlAbyss;
  late final ArshaMarketSource _arsha;

  @override
  Future<MarketPriceFetchResult> fetch(
    Iterable<MarketPriceRequest> requests, {
    MarketCancellationToken? cancellationToken,
  }) async {
    cancellationToken?.throwIfCancelled();
    final normalized = normalizeMarketPriceRequests(requests);
    if (normalized.requests.isEmpty) {
      return _result(normalized, const <MarketPriceRow>[], const []);
    }

    final rows = <MarketPriceRow>[];
    final attemptedSources = <MarketPriceSource>[];
    for (
      var offset = 0;
      offset < normalized.requests.length;
      offset += configuration.maximumRequests
    ) {
      cancellationToken?.throwIfCancelled();
      final candidateEnd = offset + configuration.maximumRequests;
      final end = candidateEnd < normalized.requests.length
          ? candidateEnd
          : normalized.requests.length;
      final chunk = normalized.requests.sublist(offset, end);
      final result = await _fetchChunk(
        chunk,
        cancellationToken: cancellationToken,
      );
      rows.addAll(result.rows);
      for (final source in result.attemptedSources) {
        if (!attemptedSources.contains(source)) attemptedSources.add(source);
      }
    }
    return _result(normalized, rows, attemptedSources);
  }

  Future<_MarketChunkResult> _fetchChunk(
    List<MarketPriceRequest> requests, {
    MarketCancellationToken? cancellationToken,
  }) async {
    final directRows = await _pearlAbyss.fetch(
      requests,
      cancellationToken: cancellationToken,
    );
    if (directRows.any((row) => row.ok)) {
      if (configuration.collectTradeEvidence) {
        try {
          final evidenceRows = await _arsha.fetchBatch(
            requests,
            cancellationToken: cancellationToken,
            maximumAttempts: 1,
          );
          return _MarketChunkResult(
            rows: _mergeTradeEvidence(directRows, evidenceRows),
            attemptedSources: const [
              MarketPriceSource.pearlAbyssCentralMarket,
              MarketPriceSource.arshaV2Batch,
            ],
          );
        } on MarketFetchCancelledException {
          rethrow;
        } on MarketSourceFailure {
          return _MarketChunkResult(
            rows: directRows,
            attemptedSources: const [
              MarketPriceSource.pearlAbyssCentralMarket,
              MarketPriceSource.arshaV2Batch,
            ],
          );
        }
      }
      return _MarketChunkResult(
        rows: directRows,
        attemptedSources: const [MarketPriceSource.pearlAbyssCentralMarket],
      );
    }

    try {
      final batchRows = await _arsha.fetchBatch(
        requests,
        cancellationToken: cancellationToken,
      );
      return _MarketChunkResult(
        rows: batchRows,
        attemptedSources: const [
          MarketPriceSource.pearlAbyssCentralMarket,
          MarketPriceSource.arshaV2Batch,
        ],
      );
    } on MarketFetchCancelledException {
      rethrow;
    } on MarketSourceFailure {
      final singleRows = await _arsha.fetchSingles(
        requests,
        cancellationToken: cancellationToken,
      );
      return _MarketChunkResult(
        rows: singleRows,
        attemptedSources: const [
          MarketPriceSource.pearlAbyssCentralMarket,
          MarketPriceSource.arshaV2Batch,
          MarketPriceSource.arshaV1Item,
        ],
      );
    }
  }

  MarketPriceFetchResult _result(
    MarketRequestNormalization normalization,
    List<MarketPriceRow> rows,
    List<MarketPriceSource> attemptedSources,
  ) => MarketPriceFetchResult(
    region: configuration.normalizedRegion,
    language: configuration.normalizedLanguage,
    fetchedAt: _clock().toUtc(),
    items: rows,
    attemptedSources: attemptedSources,
    invalidRequestCount: normalization.invalidCount,
    duplicateRequestCount: normalization.duplicateCount,
    truncatedRequestCount: normalization.truncatedCount,
  );
}

List<MarketPriceRow> _mergeTradeEvidence(
  List<MarketPriceRow> authoritativeRows,
  List<MarketPriceRow> evidenceRows,
) {
  final evidenceById = <String, MarketPriceRow>{
    for (final row in evidenceRows)
      if (row.ok) row.id: row,
  };
  return authoritativeRows
      .map((row) {
        final evidence = row.ok ? evidenceById[row.id] : null;
        if (evidence == null ||
            evidence.totalTrades == null &&
                evidence.lastSoldAtEpochSeconds == null) {
          return row;
        }
        return MarketPriceRow(
          name: row.name,
          id: row.id,
          ok: row.ok,
          price: row.price,
          stock: row.stock,
          source: row.source,
          fetchedAt: row.fetchedAt,
          diagnosticCode: row.diagnosticCode,
          apiName: row.apiName,
          httpStatus: row.httpStatus,
          totalTrades: evidence.totalTrades ?? row.totalTrades,
          lastSoldAtEpochSeconds:
              evidence.lastSoldAtEpochSeconds ?? row.lastSoldAtEpochSeconds,
        );
      })
      .toList(growable: false);
}

final class _MarketChunkResult {
  const _MarketChunkResult({
    required this.rows,
    required this.attemptedSources,
  });

  final List<MarketPriceRow> rows;
  final List<MarketPriceSource> attemptedSources;
}
