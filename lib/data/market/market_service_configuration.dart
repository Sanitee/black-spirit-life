import '../../domain/market/market_cancellation.dart';

typedef MarketDelay =
    Future<void> Function(
      Duration duration,
      MarketCancellationToken? cancellationToken,
    );

const Map<String, String> defaultPearlAbyssMarketBaseUrls = {
  'eu': 'https://eu-trade.naeu.playblackdesert.com',
  'na': 'https://na-trade.naeu.playblackdesert.com',
};

final class MarketServiceConfiguration {
  const MarketServiceConfiguration({
    this.region = 'eu',
    this.language = 'en',
    this.maximumRequests = 80,
    this.maximumConcurrency = 16,
    this.requestTimeout = const Duration(seconds: 3),
    this.arshaBatchAttempts = 3,
    this.arshaRetryBaseDelay = const Duration(milliseconds: 350),
    this.pearlAbyssBaseUrls = defaultPearlAbyssMarketBaseUrls,
    this.arshaBaseUrl = 'https://api.arsha.io',
    this.collectTradeEvidence = true,
  });

  final String region;
  final String language;

  /// Maximum number of unique items sent through one bounded source batch.
  /// Larger refreshes are processed as consecutive batches.
  final int maximumRequests;
  final int maximumConcurrency;
  final Duration requestTimeout;
  final int arshaBatchAttempts;
  final Duration arshaRetryBaseDelay;
  final Map<String, String> pearlAbyssBaseUrls;
  final String arshaBaseUrl;

  /// Enriches authoritative direct prices with cumulative Arsha trade counts.
  ///
  /// Evidence collection is best-effort: its failure never discards a
  /// successful Pearl Abyss price/stock response.
  final bool collectTradeEvidence;

  String get normalizedRegion => region.trim().toLowerCase();

  String get normalizedLanguage => language.trim().toLowerCase();

  String? get pearlAbyssBaseUrl => pearlAbyssBaseUrls[normalizedRegion]?.trim();

  void validate() {
    if (normalizedRegion == '') {
      throw ArgumentError.value(region, 'region', 'must not be blank');
    }
    if (normalizedLanguage == '') {
      throw ArgumentError.value(language, 'language', 'must not be blank');
    }
    if (maximumRequests < 1 || maximumRequests > 80) {
      throw ArgumentError.value(
        maximumRequests,
        'maximumRequests',
        'must be between 1 and 80',
      );
    }
    if (maximumConcurrency < 1 || maximumConcurrency > 16) {
      throw ArgumentError.value(
        maximumConcurrency,
        'maximumConcurrency',
        'must be between 1 and 16',
      );
    }
    if (requestTimeout.inMicroseconds <= 0) {
      throw ArgumentError.value(
        requestTimeout,
        'requestTimeout',
        'must be positive',
      );
    }
    if (arshaBatchAttempts < 1 || arshaBatchAttempts > 3) {
      throw ArgumentError.value(
        arshaBatchAttempts,
        'arshaBatchAttempts',
        'must be between 1 and 3',
      );
    }
    if (arshaRetryBaseDelay.isNegative) {
      throw ArgumentError.value(
        arshaRetryBaseDelay,
        'arshaRetryBaseDelay',
        'must not be negative',
      );
    }
    _validateBaseUrl(arshaBaseUrl, 'arshaBaseUrl');
    for (final entry in pearlAbyssBaseUrls.entries) {
      if (entry.key.trim() == '') {
        throw ArgumentError.value(
          entry.key,
          'pearlAbyssBaseUrls',
          'region keys must not be blank',
        );
      }
      _validateBaseUrl(entry.value, 'pearlAbyssBaseUrls[${entry.key}]');
    }
  }

  static void _validateBaseUrl(String value, String name) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null ||
        !uri.hasScheme ||
        !uri.hasAuthority ||
        (uri.scheme != 'https' && uri.scheme != 'http')) {
      throw ArgumentError.value(value, name, 'must be an absolute HTTP URL');
    }
  }
}

Future<void> defaultMarketDelay(
  Duration duration,
  MarketCancellationToken? cancellationToken,
) async {
  cancellationToken?.throwIfCancelled();
  if (cancellationToken == null) {
    await Future<void>.delayed(duration);
    return;
  }

  await Future.any<void>([
    Future<void>.delayed(duration),
    cancellationToken.whenCancelled.then<void>((_) {
      throw const MarketFetchCancelledException();
    }),
  ]);
}
