import 'dart:io';

import '../../domain/market/market_cancellation.dart';
import '../../domain/market/market_price_models.dart';
import 'bounded_async.dart';
import 'market_http_transport.dart';
import 'market_payload_parser.dart';
import 'market_service_configuration.dart';
import 'market_source_failure.dart';

final class ArshaMarketSource {
  factory ArshaMarketSource({
    required MarketHttpExecutor executor,
    required MarketServiceConfiguration configuration,
    required DateTime Function() clock,
    required MarketDelay delay,
  }) => ArshaMarketSource._(executor, configuration, clock, delay);

  const ArshaMarketSource._(
    this._executor,
    this._configuration,
    this._clock,
    this._delay,
  );

  static const _stockFieldNames = <String>[
    'amountListed',
    'currentStock',
    'stock',
    'count',
  ];

  final MarketHttpExecutor _executor;
  final MarketServiceConfiguration _configuration;
  final DateTime Function() _clock;
  final MarketDelay _delay;

  Future<List<MarketPriceRow>> fetchBatch(
    List<MarketPriceRequest> requests, {
    MarketCancellationToken? cancellationToken,
    int? maximumAttempts,
  }) async {
    final attemptLimit = maximumAttempts ?? _configuration.arshaBatchAttempts;
    if (attemptLimit < 1) {
      throw ArgumentError.value(
        maximumAttempts,
        'maximumAttempts',
        'must be positive',
      );
    }
    final endpoint = Uri.parse(
      '${_arshaBaseUrl()}/v2/'
      '${Uri.encodeComponent(_configuration.normalizedRegion)}/'
      'GetWorldMarketSubList?lang='
      '${Uri.encodeQueryComponent(_configuration.normalizedLanguage)}',
    );
    final body = '[${requests.map((request) => request.id).join(',')}]';

    MarketHttpResponse? response;
    for (var attempt = 1; attempt <= attemptLimit; attempt++) {
      cancellationToken?.throwIfCancelled();
      try {
        response = await _executor.send(
          MarketHttpRequest(
            method: MarketHttpMethod.post,
            uri: endpoint,
            headers: const <String, String>{
              'Content-Type': 'application/json; charset=utf-8',
            },
            body: body,
          ),
          timeout: _configuration.requestTimeout,
          cancellationToken: cancellationToken,
        );
      } on MarketFetchCancelledException {
        rethrow;
      } on MarketHttpTimeoutException {
        throw const MarketSourceFailure(MarketDiagnosticCode.timeout);
      } on Object {
        throw const MarketSourceFailure(MarketDiagnosticCode.network);
      }

      if (response.isSuccessful) {
        break;
      }
      final transient = _isTransient(response.statusCode);
      if (!transient || attempt == attemptLimit) {
        throw MarketSourceFailure(
          MarketDiagnosticCode.httpStatus,
          httpStatus: response.statusCode,
        );
      }
      await _delay(
        _configuration.arshaRetryBaseDelay * attempt,
        cancellationToken,
      );
    }

    if (response == null || !response.isSuccessful) {
      throw const MarketSourceFailure(MarketDiagnosticCode.network);
    }

    final List<ParsedMarketItem> parsedItems;
    try {
      parsedItems = MarketPayloadParser.parseArshaItems(
        response.body,
        stockFieldNames: _stockFieldNames,
      );
    } on FormatException {
      throw const MarketSourceFailure(MarketDiagnosticCode.malformedResponse);
    }
    final byId = <String, ParsedMarketItem>{};
    for (final item in parsedItems) {
      byId.putIfAbsent(item.id, () => item);
    }

    final fetchedAt = _clock().toUtc();
    return requests
        .map(
          (request) => _rowFromParsed(
            request,
            byId[request.id],
            source: MarketPriceSource.arshaV2Batch,
            fetchedAt: fetchedAt,
          ),
        )
        .toList(growable: false);
  }

  Future<List<MarketPriceRow>> fetchSingles(
    List<MarketPriceRequest> requests, {
    MarketCancellationToken? cancellationToken,
  }) => mapWithBoundedConcurrency<MarketPriceRequest, MarketPriceRow>(
    requests,
    _configuration.maximumConcurrency,
    (request) => _fetchSingle(request, cancellationToken: cancellationToken),
  );

  Future<MarketPriceRow> _fetchSingle(
    MarketPriceRequest request, {
    MarketCancellationToken? cancellationToken,
  }) async {
    try {
      cancellationToken?.throwIfCancelled();
      final endpoint = Uri.parse(
        '${_arshaBaseUrl()}/v1/'
        '${Uri.encodeComponent(_configuration.normalizedRegion)}/price',
      );
      final response = await _executor.send(
        MarketHttpRequest(
          method: MarketHttpMethod.post,
          uri: endpoint,
          headers: <String, String>{
            'id': request.id,
            'sid': '0',
            'lang': _configuration.normalizedLanguage,
          },
        ),
        timeout: _configuration.requestTimeout,
        cancellationToken: cancellationToken,
      );
      final fetchedAt = _clock().toUtc();
      if (!response.isSuccessful) {
        return _failure(
          request,
          MarketPriceSource.arshaV1Item,
          MarketDiagnosticCode.httpStatus,
          fetchedAt: fetchedAt,
          httpStatus: response.statusCode,
        );
      }

      final items = MarketPayloadParser.parseArshaItems(
        response.body,
        stockFieldNames: _stockFieldNames,
      );
      ParsedMarketItem? parsed;
      for (final item in items) {
        if (item.id == request.id) {
          parsed = item;
          break;
        }
      }
      parsed ??= items.firstOrNull;
      return _rowFromParsed(
        request,
        parsed,
        source: MarketPriceSource.arshaV1Item,
        fetchedAt: fetchedAt,
      );
    } on MarketFetchCancelledException {
      rethrow;
    } on MarketHttpTimeoutException {
      return _failure(
        request,
        MarketPriceSource.arshaV1Item,
        MarketDiagnosticCode.timeout,
        fetchedAt: _clock().toUtc(),
      );
    } on FormatException {
      return _failure(
        request,
        MarketPriceSource.arshaV1Item,
        MarketDiagnosticCode.malformedResponse,
        fetchedAt: _clock().toUtc(),
      );
    } on Object {
      return _failure(
        request,
        MarketPriceSource.arshaV1Item,
        MarketDiagnosticCode.network,
        fetchedAt: _clock().toUtc(),
      );
    }
  }

  static MarketPriceRow _rowFromParsed(
    MarketPriceRequest request,
    ParsedMarketItem? item, {
    required MarketPriceSource source,
    required DateTime fetchedAt,
  }) {
    if (item == null) {
      return _failure(
        request,
        source,
        MarketDiagnosticCode.itemMissing,
        fetchedAt: fetchedAt,
      );
    }
    if (item.price <= 0) {
      return _failure(
        request,
        source,
        MarketDiagnosticCode.unusablePrice,
        fetchedAt: fetchedAt,
        stock: item.stock,
        apiName: item.apiName,
        totalTrades: item.totalTrades,
        lastSoldAtEpochSeconds: item.lastSoldAtEpochSeconds,
      );
    }
    return MarketPriceRow(
      name: request.name,
      id: request.id,
      ok: true,
      price: item.price,
      stock: item.stock,
      source: source,
      fetchedAt: fetchedAt,
      diagnosticCode: MarketDiagnosticCode.none,
      apiName: item.apiName,
      totalTrades: item.totalTrades,
      lastSoldAtEpochSeconds: item.lastSoldAtEpochSeconds,
    );
  }

  static MarketPriceRow _failure(
    MarketPriceRequest request,
    MarketPriceSource source,
    MarketDiagnosticCode code, {
    required DateTime fetchedAt,
    int? stock,
    String apiName = '',
    int? httpStatus,
    int? totalTrades,
    int? lastSoldAtEpochSeconds,
  }) => MarketPriceRow(
    name: request.name,
    id: request.id,
    ok: false,
    price: 0,
    stock: stock,
    source: source,
    fetchedAt: fetchedAt,
    diagnosticCode: code,
    apiName: apiName,
    httpStatus: httpStatus,
    totalTrades: totalTrades,
    lastSoldAtEpochSeconds: lastSoldAtEpochSeconds,
  );

  static bool _isTransient(int statusCode) =>
      statusCode == HttpStatus.tooManyRequests ||
      statusCode == HttpStatus.internalServerError ||
      statusCode == HttpStatus.badGateway ||
      statusCode == HttpStatus.serviceUnavailable ||
      statusCode == HttpStatus.gatewayTimeout;

  String _arshaBaseUrl() {
    final value = _configuration.arshaBaseUrl;
    return value.endsWith('/') ? value.substring(0, value.length - 1) : value;
  }
}
