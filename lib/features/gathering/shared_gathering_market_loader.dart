import 'dart:async';

import 'package:bdo_gathering_companion/bdo_gathering_companion.dart';

import '../../data/market/shared_market_repository.dart';
import '../../domain/catalog/temporarily_archived_items.dart';

/// Adapts the app's shared raw market receipts without owning another client,
/// cache, or request pool. Standalone Gathering does not depend on this adapter.
final class SharedGatheringMarketLoader {
  SharedGatheringMarketLoader({required this.repository, String region = 'eu'})
    : region = region.trim().toLowerCase() {
    if (!const {'eu', 'na'}.contains(this.region)) {
      throw ArgumentError.value(region, 'region');
    }
    updates = repository.receipts
        .where(
          (receipt) =>
              receipt.key.region == this.region && receipt.key.subId == 0,
        )
        .map(_receipt);
  }

  final SharedMarketRepository repository;
  final String region;
  late final Stream<GatheringMarketReceipt> updates;

  Future<GatheringMarketLoadResult> load(
    Map<String, String> itemsById, {
    required bool includePreorders,
    required bool forceRefresh,
    required void Function(GatheringMarketReceipt) onItem,
    Future<void>? cancelled,
  }) async {
    final cancellation = MarketCancellationController();
    if (cancelled != null) {
      unawaited(cancelled.then((_) => cancellation.cancel()));
    }
    final keys = <SharedMarketKey>{};
    final priceFailures = <String>{};
    final preorderFailures = <String>{};
    for (final id in itemsById.keys) {
      // Historical session loot remains saved, but an intentional archive is
      // neither a new market request nor a failed market read.
      if (isTemporarilyArchivedMarketItemId(id)) continue;
      try {
        keys.add(SharedMarketKey(region: region, itemId: id));
      } on ArgumentError {
        priceFailures.add(id);
      }
    }
    final pendingBooks = <Future<void>>[];
    final requestedBooks = <SharedMarketKey>{};
    void receive(SharedMarketReceipt receipt) {
      if (cancellation.isCancelled) return;
      onItem(_receipt(receipt));
      // Value mode only needs preorder counts for known zero-stock items.
      // Queue each one as soon as its quote arrives, not after all quotes.
      if (!includePreorders &&
          receipt.part == SharedMarketPart.quote &&
          receipt.item.stock == 0 &&
          !receipt.item.unlisted &&
          requestedBooks.add(receipt.key)) {
        pendingBooks.add(
          repository
              .fetch(
                bookKeys: [receipt.key],
                forceRefresh: forceRefresh,
                userInitiated: forceRefresh,
                cancellationToken: cancellation.token,
                onItem: (book) {
                  if (!cancellation.isCancelled) onItem(_receipt(book));
                },
                priorityKeys: () => [receipt.key],
              )
              .then<void>(
                (batch) {
                  preorderFailures.addAll(
                    batch.bookFailures.map((key) => key.itemId),
                  );
                },
                onError: (Object _, StackTrace _) {
                  preorderFailures.add(receipt.key.itemId);
                },
              ),
        );
      }
    }

    try {
      final batch = await repository.fetch(
        quoteKeys: keys,
        bookKeys: includePreorders ? keys : const [],
        forceRefresh: forceRefresh,
        // Gathering sets force only for its explicit Refresh action.
        userInitiated: forceRefresh,
        cancellationToken: cancellation.token,
        onItem: receive,
        priorityKeys: () => keys,
      );
      priceFailures.addAll(batch.quoteFailures.map((key) => key.itemId));
      preorderFailures.addAll(batch.bookFailures.map((key) => key.itemId));
      await Future.wait(pendingBooks);
      cancellation.token.throwIfCancelled();
      return GatheringMarketLoadResult(
        priceFailures: Set.unmodifiable(priceFailures),
        preorderFailures: Set.unmodifiable(preorderFailures),
      );
    } finally {
      cancellation.cancel();
    }
  }

  static GatheringMarketReceipt _receipt(SharedMarketReceipt receipt) {
    final item = receipt.item;
    return switch (receipt.part) {
      SharedMarketPart.quote => GatheringMarketReceipt(
        itemId: receipt.key.itemId,
        price: item.basePrice,
        stock: item.stock,
        quoteFetchedAt: item.quoteFetchedAt,
        unavailable: item.unlisted,
      ),
      SharedMarketPart.orderBook => GatheringMarketReceipt(
        itemId: receipt.key.itemId,
        preorders: item.preorderCount,
        preorderFetchedAt: item.bookFetchedAt,
      ),
    };
  }
}
