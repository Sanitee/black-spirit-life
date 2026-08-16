import '../../domain/market/market_price_models.dart';

final class MarketSourceFailure implements Exception {
  const MarketSourceFailure(this.diagnosticCode, {this.httpStatus});

  final MarketDiagnosticCode diagnosticCode;
  final int? httpStatus;

  @override
  String toString() => 'Market source failed: ${diagnosticCode.name}';
}
