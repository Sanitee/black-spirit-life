import 'dart:async';

import '../../domain/catalog/temporarily_archived_items.dart';
import '../../domain/market/market_price_gateway.dart';
import '../../domain/market/market_price_models.dart';
import 'shared_market_repository.dart';

/// Planner and map adapter. Summary prices, stock and sales counters come from
/// the same raw receipts as Opportunities. Only sold-out quotes need a book
/// read to budget preorders; stocked items do not trigger an enrichment scan.
final class SharedMarketPriceGateway implements ProgressiveMarketPriceGateway {
  SharedMarketPriceGateway({
    required this.repository,
    DateTime Function()? utcNow,
  }) : _clock = utcNow ?? DateTime.now;
  final SharedMarketRepository repository;
  final DateTime Function() _clock;

  @override
  Future<MarketPriceFetchResult> fetch(
    Iterable<MarketPriceRequest> requests, {
    MarketCancellationToken? cancellationToken,
  }) => fetchProgressive(
    requests,
    region: 'eu',
    cancellationToken: cancellationToken,
  );

  @override
  Future<MarketPriceFetchResult> fetchProgressive(
    Iterable<MarketPriceRequest> requests, {
    required String region,
    bool forceRefresh = false,
    MarketCancellationToken? cancellationToken,
    void Function(MarketPriceFetchResult)? onUpdate,
  }) async {
    cancellationToken?.throwIfCancelled();
    final normalized = normalizeMarketPriceRequests(requests);
    final rows = <String, MarketPriceRow>{};
    final names = {
      for (final request in normalized.requests) request.id: request.name,
    };
    final keys = <SharedMarketKey>[];
    final normalizedRegion = region.trim().toLowerCase();
    for (final request in normalized.requests) {
      if (isTemporarilyArchivedMarketItemId(request.id)) {
        rows[request.id] = _failure(
          request,
          MarketDiagnosticCode.temporarilyArchived,
        );
      } else if (!const {'eu', 'na'}.contains(normalizedRegion) ||
          int.tryParse(request.id) == null) {
        rows[request.id] = _failure(
          request,
          MarketDiagnosticCode.unsupportedRegion,
        );
      } else {
        keys.add(SharedMarketKey(region: normalizedRegion, itemId: request.id));
      }
    }
    MarketPriceFetchResult result() => MarketPriceFetchResult(
      region: normalizedRegion,
      language: 'en',
      fetchedAt:
          rows.values
              .where((row) => row.ok)
              .fold<DateTime?>(
                null,
                (oldest, row) =>
                    oldest == null || row.fetchedAt.isBefore(oldest)
                    ? row.fetchedAt
                    : oldest,
              ) ??
          DateTime.now().toUtc(),
      items: rows.values.toList(),
      attemptedSources: keys.isEmpty
          ? const []
          : const [MarketPriceSource.pearlAbyssCentralMarket],
      invalidRequestCount: normalized.invalidCount,
      duplicateRequestCount: normalized.duplicateCount,
    );
    Timer? publication;
    void publish() {
      publication?.cancel();
      publication = null;
      if (!(cancellationToken?.isCancelled ?? false)) onUpdate?.call(result());
    }

    try {
      if (keys.isNotEmpty) {
        final batch = await repository.fetch(
          quoteKeys: keys,
          forceRefresh: forceRefresh,
          // This adapter's forced reads come from Planner/Map refresh buttons.
          userInitiated: forceRefresh,
          cancellationToken: cancellationToken,
          onItem: (receipt) {
            if (receipt.part != SharedMarketPart.quote) return;
            rows[receipt.key.itemId] = sharedMarketPriceRow(
              repository.cachedItem(receipt.key) ?? receipt.item,
              name: names[receipt.key.itemId]!,
              now: _clock().toUtc(),
              maxAge: repository.cacheMaxAge,
            );
            publication ??= Timer(const Duration(milliseconds: 100), publish);
          },
        );
        for (final key in keys) {
          if (batch.quoteFailures.contains(key)) {
            rows[key.itemId] = _failure(
              MarketPriceRequest(name: names[key.itemId]!, id: key.itemId),
              MarketDiagnosticCode.network,
            );
          } else if (batch.items[key] case final item?) {
            rows[key.itemId] = sharedMarketPriceRow(
              repository.cachedItem(key) ?? item,
              name: names[key.itemId]!,
              now: _clock().toUtc(),
              maxAge: repository.cacheMaxAge,
            );
          }
        }
        final soldOut = keys.where((key) {
          final row = rows[key.itemId];
          return row != null &&
              row.ok &&
              (row.stock == 0 ||
                  (row.stock == null && row.aggregateStock == 0));
        }).toList();
        if (soldOut.isNotEmpty) {
          publish();
          await repository.fetch(
            bookKeys: soldOut,
            forceRefresh: forceRefresh,
            userInitiated: forceRefresh,
            cancellationToken: cancellationToken,
            onItem: (receipt) {
              final item = repository.cachedItem(receipt.key);
              if (item == null) return;
              rows[receipt.key.itemId] = sharedMarketPriceRow(
                item,
                name: names[receipt.key.itemId]!,
                now: _clock().toUtc(),
                maxAge: repository.cacheMaxAge,
              );
              publication ??= Timer(const Duration(milliseconds: 100), publish);
            },
          );
        }
      }
      cancellationToken?.throwIfCancelled();
      return result();
    } finally {
      publication?.cancel();
    }
  }
}

MarketPriceRow sharedMarketPriceRow(
  OpportunityMarketItem item, {
  required String name,
  DateTime? now,
  Duration maxAge = const Duration(minutes: 5),
}) {
  final hasBook = item.bookIsFresh(now ?? DateTime.now().toUtc(), maxAge);
  final stock =
      hasBook &&
          (item.stock == null ||
              item.quoteFetchedAt == null ||
              item.bookFetchedAt!.isAfter(item.quoteFetchedAt!))
      ? item.asks!.fold<int>(0, (sum, level) => sum + level.quantity)
      : item.stock;
  final preorderPrice = hasBook && stock == 0
      ? item.bids!
            .where((level) => level.price > 0 && level.quantity > 0)
            .fold<int>(
              0,
              (highest, level) => level.price > highest ? level.price : highest,
            )
      : hasBook
      ? 0
      : null;
  final valid =
      !item.unlisted &&
      (item.basePrice ?? 0) > 0 &&
      item.quoteFetchedAt != null;
  return MarketPriceRow(
    name: name,
    id: item.itemId,
    ok: valid,
    price: valid ? item.basePrice! : 0,
    stock: stock,
    preorderPrice: preorderPrice,
    preorderFetchedAt: hasBook ? item.bookFetchedAt : null,
    aggregateStock: item.aggregateStock,
    source: MarketPriceSource.pearlAbyssCentralMarket,
    fetchedAt:
        item.quoteFetchedAt ??
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    diagnosticCode: valid
        ? MarketDiagnosticCode.none
        : item.unlisted
        ? MarketDiagnosticCode.itemMissing
        : MarketDiagnosticCode.malformedResponse,
    totalTrades: item.totalTrades,
    lastSoldAtEpochSeconds: item.lastSoldAt == null
        ? null
        : item.lastSoldAt!.millisecondsSinceEpoch ~/ 1000,
  );
}

MarketPriceRow _failure(
  MarketPriceRequest request,
  MarketDiagnosticCode code,
) => MarketPriceRow(
  name: request.name,
  id: request.id,
  ok: false,
  price: 0,
  stock: null,
  source: MarketPriceSource.pearlAbyssCentralMarket,
  fetchedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
  diagnosticCode: code,
);
