import 'dart:convert';

import 'package:http/http.dart' as http;

import 'market_http_transport.dart';

/// Production transport. Tests use [MarketHttpTransport] fakes instead.
final class PackageHttpMarketTransport implements MarketHttpTransport {
  PackageHttpMarketTransport({http.Client? client})
    : _client = client ?? http.Client(),
      _ownsClient = client == null;

  final http.Client _client;
  final bool _ownsClient;

  void close() {
    if (_ownsClient) {
      _client.close();
    }
  }

  @override
  Future<MarketHttpResponse> send(MarketHttpRequest request) async {
    final outgoing = http.AbortableRequest(
      request.method.name.toUpperCase(),
      request.uri,
      abortTrigger: request.abortTrigger,
    );
    outgoing.headers.addAll(request.headers);
    outgoing.body = request.body;

    final response = await _client.send(outgoing);
    final body = await response.stream.transform(utf8.decoder).join();
    return MarketHttpResponse(
      statusCode: response.statusCode,
      body: body,
      headers: response.headers,
    );
  }
}
