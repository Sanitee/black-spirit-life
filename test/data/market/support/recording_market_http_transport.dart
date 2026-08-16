import 'package:bdo_craft_planner_flutter/data/market/market_http_transport.dart';

typedef MarketHttpHandler =
    Future<MarketHttpResponse> Function(MarketHttpRequest request);

final class RecordingMarketHttpTransport implements MarketHttpTransport {
  RecordingMarketHttpTransport(this._handler);

  final MarketHttpHandler _handler;
  final List<MarketHttpRequest> requests = <MarketHttpRequest>[];
  int activeRequests = 0;
  int maximumActiveRequests = 0;

  @override
  Future<MarketHttpResponse> send(MarketHttpRequest request) async {
    requests.add(request);
    activeRequests++;
    if (activeRequests > maximumActiveRequests) {
      maximumActiveRequests = activeRequests;
    }
    try {
      return await _handler(request);
    } finally {
      activeRequests--;
    }
  }
}
