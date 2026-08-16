import 'dart:async';

import '../../domain/market/market_cancellation.dart';

enum MarketHttpMethod { post }

final class MarketHttpRequest {
  MarketHttpRequest({
    required this.method,
    required this.uri,
    this.headers = const <String, String>{},
    this.body = '',
    this.abortTrigger,
  });

  final MarketHttpMethod method;
  final Uri uri;
  final Map<String, String> headers;
  final String body;

  /// Completing this future asks an abort-capable transport to stop I/O.
  final Future<void>? abortTrigger;

  MarketHttpRequest withAbortTrigger(Future<void> trigger) => MarketHttpRequest(
    method: method,
    uri: uri,
    headers: headers,
    body: body,
    abortTrigger: trigger,
  );
}

final class MarketHttpResponse {
  const MarketHttpResponse({
    required this.statusCode,
    this.body = '',
    this.headers = const <String, String>{},
  });

  final int statusCode;
  final String body;
  final Map<String, String> headers;

  bool get isSuccessful => statusCode >= 200 && statusCode < 300;
}

abstract interface class MarketHttpTransport {
  Future<MarketHttpResponse> send(MarketHttpRequest request);
}

final class MarketHttpTimeoutException implements Exception {
  const MarketHttpTimeoutException();

  @override
  String toString() => 'Market HTTP request timed out';
}

/// Adds deterministic timeout and cancellation semantics around a transport.
final class MarketHttpExecutor {
  const MarketHttpExecutor(this._transport);

  final MarketHttpTransport _transport;

  Future<MarketHttpResponse> send(
    MarketHttpRequest request, {
    required Duration timeout,
    MarketCancellationToken? cancellationToken,
  }) async {
    cancellationToken?.throwIfCancelled();

    final abort = Completer<void>();
    final interrupted = Completer<MarketHttpResponse>();
    final timer = Timer(timeout, () {
      if (!interrupted.isCompleted) {
        interrupted.completeError(const MarketHttpTimeoutException());
      }
      if (!abort.isCompleted) {
        abort.complete();
      }
    });

    if (cancellationToken != null) {
      unawaited(
        cancellationToken.whenCancelled.then<void>((_) {
          if (!interrupted.isCompleted) {
            interrupted.completeError(const MarketFetchCancelledException());
          }
          if (!abort.isCompleted) {
            abort.complete();
          }
        }),
      );
    }

    try {
      return await Future.any<MarketHttpResponse>([
        _transport.send(request.withAbortTrigger(abort.future)),
        interrupted.future,
      ]);
    } finally {
      timer.cancel();
    }
  }
}
