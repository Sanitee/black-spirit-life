import 'market_cancellation.dart';
import 'market_price_models.dart';

abstract interface class MarketPriceGateway {
  Future<MarketPriceFetchResult> fetch(
    Iterable<MarketPriceRequest> requests, {
    MarketCancellationToken? cancellationToken,
  });
}

/// Optional capability; older integrations can keep the single-result API.
abstract interface class ProgressiveMarketPriceGateway
    implements MarketPriceGateway {
  Future<MarketPriceFetchResult> fetchProgressive(
    Iterable<MarketPriceRequest> requests, {
    required String region,
    bool forceRefresh = false,
    MarketCancellationToken? cancellationToken,
    void Function(MarketPriceFetchResult)? onUpdate,
  });
}
