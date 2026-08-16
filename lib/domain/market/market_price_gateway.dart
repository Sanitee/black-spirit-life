import 'market_cancellation.dart';
import 'market_price_models.dart';

abstract interface class MarketPriceGateway {
  Future<MarketPriceFetchResult> fetch(
    Iterable<MarketPriceRequest> requests, {
    MarketCancellationToken? cancellationToken,
  });
}
