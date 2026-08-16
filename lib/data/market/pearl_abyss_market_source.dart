import '../../domain/market/market_cancellation.dart';
import '../../domain/market/market_price_models.dart';
import 'bounded_async.dart';
import 'market_http_transport.dart';
import 'market_payload_parser.dart';
import 'market_service_configuration.dart';

final class PearlAbyssMarketSource {
  factory PearlAbyssMarketSource({
    required MarketHttpExecutor executor,
    required MarketServiceConfiguration configuration,
    required DateTime Function() clock,
  }) => PearlAbyssMarketSource._(executor, configuration, clock);

  const PearlAbyssMarketSource._(
    this._executor,
    this._configuration,
    this._clock,
  );

  final MarketHttpExecutor _executor;
  final MarketServiceConfiguration _configuration;
  final DateTime Function() _clock;

  Future<List<MarketPriceRow>> fetch(
    List<MarketPriceRequest> requests, {
    MarketCancellationToken? cancellationToken,
  }) async {
    final baseUrl = _configuration.pearlAbyssBaseUrl;
    if (baseUrl == null || baseUrl == '') {
      final fetchedAt = _clock().toUtc();
      return requests
          .map(
            (request) => _failure(
              request,
              MarketDiagnosticCode.unsupportedRegion,
              fetchedAt: fetchedAt,
            ),
          )
          .toList(growable: false);
    }

    return mapWithBoundedConcurrency<MarketPriceRequest, MarketPriceRow>(
      requests,
      _configuration.maximumConcurrency,
      (request) =>
          _fetchOne(request, baseUrl, cancellationToken: cancellationToken),
    );
  }

  Future<MarketPriceRow> _fetchOne(
    MarketPriceRequest request,
    String baseUrl, {
    MarketCancellationToken? cancellationToken,
  }) async {
    try {
      cancellationToken?.throwIfCancelled();
      final endpoint = Uri.parse(
        '${_withoutTrailingSlash(baseUrl)}/Trademarket/GetWorldMarketSubList',
      );
      final response = await _executor.send(
        MarketHttpRequest(
          method: MarketHttpMethod.post,
          uri: endpoint,
          headers: const <String, String>{
            'Content-Type': 'application/json; charset=utf-8',
            'User-Agent': 'BlackDesert',
          },
          // The ID remains a validated decimal string. Embedding it as a JSON
          // number preserves the endpoint's audited wire contract without a
          // platform-integer conversion.
          body: '{"keyType":0,"mainKey":${request.id}}',
        ),
        timeout: _configuration.requestTimeout,
        cancellationToken: cancellationToken,
      );
      final fetchedAt = _clock().toUtc();
      if (!response.isSuccessful) {
        return _failure(
          request,
          MarketDiagnosticCode.httpStatus,
          fetchedAt: fetchedAt,
          httpStatus: response.statusCode,
        );
      }

      final parsed = MarketPayloadParser.parsePearlAbyssItem(
        response.body,
        request.id,
      );
      if (parsed == null) {
        return _failure(
          request,
          MarketDiagnosticCode.itemMissing,
          fetchedAt: fetchedAt,
        );
      }
      if (parsed.price <= 0) {
        return _failure(
          request,
          MarketDiagnosticCode.unusablePrice,
          fetchedAt: fetchedAt,
          stock: parsed.stock,
        );
      }
      return MarketPriceRow(
        name: request.name,
        id: request.id,
        ok: true,
        price: parsed.price,
        stock: parsed.stock,
        source: MarketPriceSource.pearlAbyssCentralMarket,
        fetchedAt: fetchedAt,
        diagnosticCode: MarketDiagnosticCode.none,
      );
    } on MarketFetchCancelledException {
      rethrow;
    } on MarketHttpTimeoutException {
      return _failure(
        request,
        MarketDiagnosticCode.timeout,
        fetchedAt: _clock().toUtc(),
      );
    } on FormatException {
      return _failure(
        request,
        MarketDiagnosticCode.malformedResponse,
        fetchedAt: _clock().toUtc(),
      );
    } on Object {
      return _failure(
        request,
        MarketDiagnosticCode.network,
        fetchedAt: _clock().toUtc(),
      );
    }
  }

  static MarketPriceRow _failure(
    MarketPriceRequest request,
    MarketDiagnosticCode code, {
    required DateTime fetchedAt,
    int? stock,
    int? httpStatus,
  }) => MarketPriceRow(
    name: request.name,
    id: request.id,
    ok: false,
    price: 0,
    stock: stock,
    source: MarketPriceSource.pearlAbyssCentralMarket,
    fetchedAt: fetchedAt,
    diagnosticCode: code,
    httpStatus: httpStatus,
  );

  static String _withoutTrailingSlash(String value) =>
      value.endsWith('/') ? value.substring(0, value.length - 1) : value;
}
