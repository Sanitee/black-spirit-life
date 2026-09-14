import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../domain/market/market_cancellation.dart';
import '../../domain/market/market_price_models.dart';
import '../../domain/market/market_request_pause.dart';
import '../../domain/opportunities/opportunity_market_models.dart';
import '../market/market_request_pacer.dart';
import '../market/market_response_guard.dart';
import '../market/market_session_cookies.dart';
import 'opportunity_market_bulk_codec.dart';
import 'opportunity_market_codec.dart';

export '../../domain/market/market_cancellation.dart';
export '../../domain/market/market_request_pause.dart';

typedef OpportunityMarketProgress = void Function(int completed, int total);
typedef OpportunityMarketItemReceived =
    void Function(OpportunityMarketItem item);

/// A denial's headers stop dispatch immediately. Only this bounded interval is
/// used to check its body for stronger access-protection evidence.
const marketProtectionProbeTimeout = Duration(milliseconds: 250);

final class OpportunityMarketBatch {
  OpportunityMarketBatch({
    required Map<String, OpportunityMarketItem> items,
    required Map<String, String> failures,
    this.rateLimited = false,
    this.pause,
    Set<String> retryableQuoteFailures = const {},
    Set<String> retryableBookFailures = const {},
  }) : items = Map.unmodifiable(items),
       failures = Map.unmodifiable(failures),
       retryableQuoteFailures = Set.unmodifiable(retryableQuoteFailures),
       retryableBookFailures = Set.unmodifiable(retryableBookFailures);
  final Map<String, OpportunityMarketItem> items;
  final Map<String, String> failures;

  /// A 429 stops dispatch, but already received items remain usable.
  final bool rateLimited;
  final MarketRequestPause? pause;
  final Set<String> retryableQuoteFailures;
  final Set<String> retryableBookFailures;
}

final class OpportunityHttpResponse {
  const OpportunityHttpResponse({
    required this.statusCode,
    required this.bytes,
    this.headers = const {},
    this.protectionBytes,
  });
  final int statusCode;
  final Uint8List bytes;
  final Map<String, String> headers;

  /// Optional bounded body prefix after an immediate 429/timed-503 response.
  /// Consumers must latch the header pause before awaiting this evidence.
  final Future<Uint8List>? protectionBytes;
}

abstract interface class OpportunityMarketTransport {
  Future<OpportunityHttpResponse> post(
    Uri uri, {
    required Map<String, String> headers,
    required String body,
    Future<void>? abortTrigger,
  });
  void close();
}

/// Byte-preserving HTTP is necessary: official books are Huffman-compressed.
final class HttpOpportunityMarketTransport
    implements OpportunityMarketTransport {
  HttpOpportunityMarketTransport({http.Client? client})
    : _client = client ?? http.Client();
  final http.Client _client;
  final _sessionCookies = MarketSessionCookies();
  int _requestsWithSessionCookies = 0;

  /// Count only; session identifiers must never enter market logs or storage.
  int get requestsWithSessionCookies => _requestsWithSessionCookies;

  @override
  Future<OpportunityHttpResponse> post(
    Uri uri, {
    required Map<String, String> headers,
    required String body,
    Future<void>? abortTrigger,
  }) async {
    final request =
        http.AbortableRequest('POST', uri, abortTrigger: abortTrigger)
          // These fixed API calls never need redirect navigation. Automatic
          // redirects could forward a session beyond its exact origin and
          // attribute the destination's cookies to the original request.
          ..followRedirects = false
          ..headers.addAll(headers)
          ..body = body;
    final cookies = _sessionCookies.cookieHeader(uri);
    if (cookies != null && !request.headers.containsKey('cookie')) {
      request.headers['Cookie'] = cookies;
      _requestsWithSessionCookies++;
    }
    final response = await _client.send(request);
    // A throttle is actionable as soon as its headers arrive. Waiting for an
    // irrelevant error body can turn a real Retry-After into a timeout while
    // other callers continue sending work to the same server.
    if (response.statusCode == 429 ||
        (response.statusCode == 503 &&
            marketRetryAfter(response.headers, DateTime.now().toUtc()) !=
                null)) {
      return OpportunityHttpResponse(
        statusCode: response.statusCode,
        bytes: Uint8List(0),
        headers: response.headers,
        protectionBytes: _readProtectionPrefix(
          response.stream,
          response.headers,
        ),
      );
    }
    final bytes = BytesBuilder(copy: false);
    final prefix = BytesBuilder(copy: false);
    final reader = StreamIterator(response.stream);
    try {
      while (await reader.moveNext()) {
        final chunk = reader.current;
        bytes.add(chunk);
        // Recognize a protective document before waiting on its remaining
        // body. Preserve the real bytes for the shared response guard.
        if (prefix.length < 65536) {
          final remaining = 65536 - prefix.length;
          prefix.add(
            chunk.length <= remaining ? chunk : chunk.sublist(0, remaining),
          );
          if (isProtectedMarketResponse(
            bytes: prefix.toBytes(),
            headers: response.headers,
          )) {
            break;
          }
        }
        if (bytes.length > 1024 * 1024) {
          throw const FormatException('Market response too large');
        }
      }
    } finally {
      // Reporting a known refusal must not wait for stream cancellation either.
      unawaited(reader.cancel().catchError((Object _) {}));
    }
    final result = OpportunityHttpResponse(
      statusCode: response.statusCode,
      bytes: bytes.takeBytes(),
      headers: response.headers,
    );
    if (result.statusCode >= 200 &&
        result.statusCode < 300 &&
        !isProtectedMarketResponse(
          bytes: result.bytes,
          headers: result.headers,
        )) {
      // Keep only the ordinary session supplied by a successful response.
      // Never import browser cookies, solve challenges or retain a denial's
      // cookies. The shared repository still owns every provider pause.
      _sessionCookies.store(uri, result.headers);
    }
    return result;
  }

  @override
  void close() {
    _sessionCookies.clear();
    _client.close();
  }
}

Future<Uint8List> _readProtectionPrefix(
  Stream<List<int>> stream,
  Map<String, String> headers,
) async {
  final prefix = BytesBuilder(copy: false);
  final elapsed = Stopwatch()..start();
  final reader = StreamIterator(stream);
  try {
    while (prefix.length < 65536) {
      final remaining = marketProtectionProbeTimeout - elapsed.elapsed;
      if (remaining <= Duration.zero ||
          !await reader.moveNext().timeout(remaining)) {
        break;
      }
      final chunk = reader.current;
      final capacity = 65536 - prefix.length;
      prefix.add(chunk.length <= capacity ? chunk : chunk.sublist(0, capacity));
      if (isProtectedMarketResponse(
        bytes: prefix.toBytes(),
        headers: headers,
      )) {
        break;
      }
    }
  } on Object {
    // The refusal is already authoritative. A timeout, aborted body or stream
    // error cannot erase it; only positive body evidence strengthens its type.
  } finally {
    elapsed.stop();
    unawaited(reader.cancel().catchError((Object _) {}));
  }
  return prefix.takeBytes();
}

/// Read-only Opportunities adapter. It neither reads nor writes planner state.
/// Quotes and books retain separate timestamps, even when fetched together.
final class OpportunityMarketService {
  OpportunityMarketService({
    String region = 'eu',
    OpportunityMarketTransport? transport,
    DateTime Function()? utcNow,
    this.concurrency = 20,
    this.quoteBatchSize = 40,
    this.requestTimeout = const Duration(seconds: 6),
    this.requestSpacing = const Duration(milliseconds: 40),
    Duration? orderBookRequestSpacing,
    this.recoveryRequestSpacing = const Duration(seconds: 1),
  }) : region = region.toLowerCase(),
       orderBookRequestSpacing =
           orderBookRequestSpacing ??
           (requestSpacing == Duration.zero
               ? Duration.zero
               : const Duration(milliseconds: 250)),
       _effectiveConcurrency = concurrency,
       _transport = transport ?? HttpOpportunityMarketTransport(),
       _utcNow = utcNow ?? (() => DateTime.now().toUtc()) {
    if (!{'eu', 'na'}.contains(this.region)) {
      throw ArgumentError.value(region, 'region', 'Unsupported market region');
    }
    if (concurrency < 1 || concurrency > 40) {
      throw ArgumentError.value(concurrency, 'concurrency', 'Use 1 to 40');
    }
    if (quoteBatchSize < 1 || quoteBatchSize > 100) {
      throw ArgumentError.value(
        quoteBatchSize,
        'quoteBatchSize',
        'Use 1 to 100',
      );
    }
    if (requestTimeout <= Duration.zero ||
        requestSpacing.isNegative ||
        this.orderBookRequestSpacing.isNegative ||
        recoveryRequestSpacing.isNegative) {
      throw ArgumentError('Invalid market request timing');
    }
    _pacer = MarketRequestPacer(requestSpacing);
  }

  final String region;
  final OpportunityMarketTransport _transport;
  final DateTime Function() _utcNow;
  final int concurrency;
  // A small 12/20/40-worker comparison favoured 20 as a practical default.
  // Neither the default nor the tested ceiling is a published provider limit.
  // Keep a reduced pool for this service's lifetime; never ramp up on errors.
  int _effectiveConcurrency;

  /// Current dispatch ceiling, including any timeout/server-error slowdown.
  int get effectiveConcurrency => _effectiveConcurrency;

  /// Carries a session's regional slowdown into a replacement service. This
  /// can only lower the pool, never increase it or change saved preferences.
  void limitConcurrency(int ceiling) {
    if (ceiling < 1) throw ArgumentError.value(ceiling, 'ceiling');
    if (ceiling < _effectiveConcurrency) _effectiveConcurrency = ceiling;
  }

  /// One hundred IDs returned a complete EU response on 2026-09-10. This is
  /// an application batch bound, not a published provider request-rate limit.
  /// One retains individual detailed quotes for callers that need that format.
  final int quoteBatchSize;
  final Duration requestTimeout;
  final Duration requestSpacing;
  final Duration orderBookRequestSpacing;
  final Duration recoveryRequestSpacing;
  late final MarketRequestPacer _pacer;
  MarketRequestPause? _pause;
  MarketRequestPause? get pause => _pause;

  /// A host replacing this adapter can retain the origin's pause between scans.
  DateTime? get blockedUntil => _pause?.retryAt;
  final MarketCancellationController _closed = MarketCancellationController();
  Future<void> _scanTail = Future<void>.value();

  Future<OpportunityMarketBatch> fetchQuotes(
    Iterable<String> ids, {
    bool recovery = false,
    bool userInitiated = false,
    MarketCancellationToken? cancellationToken,
    OpportunityMarketProgress? onProgress,
    OpportunityMarketItemReceived? onItem,
  }) => fetchMarket(
    quoteIds: ids,
    bookIds: const [],
    recovery: recovery,
    userInitiated: userInitiated,
    cancellationToken: cancellationToken,
    onProgress: onProgress,
    onItem: onItem,
  );

  Future<OpportunityMarketBatch> fetchOrderBooks(
    Iterable<String> ids, {
    bool recovery = false,
    bool userInitiated = false,
    MarketCancellationToken? cancellationToken,
    OpportunityMarketProgress? onProgress,
    OpportunityMarketItemReceived? onItem,
  }) => fetchMarket(
    quoteIds: const [],
    bookIds: ids,
    recovery: recovery,
    userInitiated: userInitiated,
    cancellationToken: cancellationToken,
    onProgress: onProgress,
    onItem: onItem,
  );

  /// One rolling pool for both request types. A slow quote does not prevent
  /// other items' books from loading. Priority is read when a worker is free.
  Future<OpportunityMarketBatch> fetchMarket({
    required Iterable<String> quoteIds,
    required Iterable<String> bookIds,
    bool recovery = false,
    bool userInitiated = false,
    MarketCancellationToken? cancellationToken,
    OpportunityMarketProgress? onProgress,
    OpportunityMarketItemReceived? onItem,
    Iterable<String> Function()? priorityIds,
    void Function()? onRateLimited,
  }) {
    final quotes = quoteIds.toList(growable: false);
    final books = bookIds.toList(growable: false);
    final future = _scanTail.then(
      (_) => _scan(
        quotes,
        books,
        cancellationToken,
        onProgress,
        onItem,
        priorityIds,
        onRateLimited,
        recovery,
        userInitiated,
      ),
    );
    // Concurrent callers share the same bounded pool rather than each opening
    // another pool of connections. A failed/cancelled scan does not poison it.
    _scanTail = future.then<void>(
      (_) => null,
      onError: (Object _, StackTrace _) => null,
    );
    return future;
  }

  void close() {
    _closed.cancel();
    _pacer.close();
    _transport.close();
  }

  Future<OpportunityMarketBatch> _scan(
    List<String> rawQuoteIds,
    List<String> rawBookIds,
    MarketCancellationToken? token,
    OpportunityMarketProgress? progress,
    OpportunityMarketItemReceived? onItem,
    Iterable<String> Function()? priorityIds,
    void Function()? onRateLimited,
    bool recovery,
    bool userInitiated,
  ) async {
    void checkCancelled() {
      _closed.token.throwIfCancelled();
      token?.throwIfCancelled();
    }

    checkCancelled();
    final failures = <String, String>{};
    final retryableQuoteFailures = <String>{};
    final retryableBookFailures = <String>{};
    Set<String> normalize(List<String> rawIds) {
      final ids = <String>{};
      for (final raw in rawIds) {
        final id = normalizeNumericMarketId(raw);
        if (id == null || int.tryParse(id) == null) {
          failures[raw] = 'Invalid item ID';
        } else {
          ids.add(id);
        }
      }
      return ids;
    }

    final quoteIds = normalize(rawQuoteIds);
    final bookIds = normalize(rawBookIds);
    final queue = <String, List<bool>>{
      for (final id in {...quoteIds, ...bookIds})
        id: [if (quoteIds.contains(id)) false, if (bookIds.contains(id)) true],
    };
    final total = quoteIds.length + bookIds.length;
    final items = <String, OpportunityMarketItem>{};
    var completed = 0;
    var rateLimited = false;
    var blockedRetryable = false;
    final blocked = Completer<void>();
    progress?.call(0, total);
    if ((_pause?.isActive(_utcNow()) ?? false) ||
        (!userInitiated &&
            _pause?.reason == MarketRequestPauseReason.protected)) {
      onRateLimited?.call();
      progress?.call(total, total);
      return OpportunityMarketBatch(
        items: items,
        failures: {...failures, for (final id in queue.keys) id: 'Market busy'},
        rateLimited: true,
        pause: _pause,
      );
    }

    void protectScan() {
      if (_pause == null) return;
      _pause = MarketRequestPause(
        reason: MarketRequestPauseReason.protected,
        retryAt: _pause!.retryAt,
      );
      blockedRetryable = false;
      retryableQuoteFailures.clear();
      retryableBookFailures.clear();
    }

    void blockScan(_MarketBlockedException error) {
      if (rateLimited) {
        if (error.reason == MarketRequestPauseReason.protected) protectScan();
        return;
      }
      rateLimited = true;
      final delay = error.retryAfter ?? const Duration(seconds: 60);
      final until = _utcNow().add(delay.isNegative ? Duration.zero : delay);
      _pause = MarketRequestPause(
        reason: error.reason,
        retryAt: blockedUntil?.isAfter(until) == true ? blockedUntil! : until,
      );
      blockedRetryable =
          error.retryable && error.reason != MarketRequestPauseReason.protected;
      for (final entry in queue.entries) {
        failures[entry.key] = 'Market busy';
        if (blockedRetryable) {
          if (entry.value.contains(false)) {
            retryableQuoteFailures.add(entry.key);
          }
          if (entry.value.contains(true)) retryableBookFailures.add(entry.key);
        }
        completed += entry.value.length;
      }
      queue.clear();
      blocked.complete();
      onRateLimited?.call();
      progress?.call(completed, total);
    }

    Future<void> worker(int workerIndex) async {
      while (queue.isNotEmpty &&
          !rateLimited &&
          workerIndex < _effectiveConcurrency) {
        checkCancelled();
        while (!_pacer.canStart && !rateLimited) {
          await Future.any<void>([
            _pacer.whenReady,
            blocked.future,
            _closed.token.whenCancelled,
            if (token != null) token.whenCancelled,
          ]);
          checkCancelled();
        }
        if (rateLimited || queue.isEmpty) return;
        if (workerIndex >= _effectiveConcurrency) return;
        final priorities = priorityIds?.call().toList() ?? const <String>[];
        final quotes = queue.keys
            .where((id) => queue[id]!.contains(false))
            .toSet();
        final candidates = quotes.isEmpty ? queue.keys.toSet() : quotes;
        var id = candidates.first;
        for (final priority in priorities) {
          if (candidates.contains(priority)) {
            id = priority;
            break;
          }
        }
        final requests = queue[id]!;
        final books = requests.first;
        var gap = books && orderBookRequestSpacing > requestSpacing
            ? orderBookRequestSpacing
            : requestSpacing;
        if (recovery && gap < recoveryRequestSpacing) {
          gap = recoveryRequestSpacing;
        }
        if (!_pacer.canStartFor(gap)) {
          await Future.any<void>([
            _pacer.whenReady,
            blocked.future,
            _closed.token.whenCancelled,
            if (token != null) token.whenCancelled,
          ]);
          checkCancelled();
          continue;
        }
        requests.removeAt(0);
        if (requests.isEmpty) queue.remove(id);
        final requestIds = <String>[id];
        if (!books && quoteBatchSize > 1) {
          // Coalesce quotes without taking a second HTTP connection per item.
          // Books remain in this same rolling queue, including this batch's
          // books, so a slow summary cannot stall all executable depth.
          for (final candidate in {...priorities, ...queue.keys}) {
            if (requestIds.length == quoteBatchSize) break;
            final pending = queue[candidate];
            if (pending == null || !pending.remove(false)) continue;
            requestIds.add(candidate);
            if (pending.isEmpty) queue.remove(candidate);
          }
        }
        _pacer.started(minimumInterval: gap);
        try {
          final bytes = await _request(
            requestIds,
            books,
            token,
            blocked.future,
          );
          checkCancelled();
          if (rateLimited) throw const _MarketBlockedException();
          final receivedAt = _utcNow();
          if (requestIds.length > 1) {
            final decoded = decodeOpportunityBulkQuotes(
              bytes: bytes,
              requestedIds: requestIds,
              fetchedAt: receivedAt,
            );
            failures.addAll(decoded.failures);
            if (decoded.items.isNotEmpty) _pause = null;
            for (final item in decoded.items.values) {
              checkCancelled();
              items[item.itemId] = items[item.itemId]?.mergeFrom(item) ?? item;
              onItem?.call(item);
            }
          } else {
            final item = books
                ? decodeOpportunityOrderBook(
                    bytes: bytes,
                    itemId: id,
                    fetchedAt: receivedAt,
                  )
                : decodeOpportunityQuote(
                    bytes: bytes,
                    itemId: id,
                    fetchedAt: receivedAt,
                  );
            _pause = null;
            items[id] = items[id]?.mergeFrom(item) ?? item;
            onItem?.call(item);
          }
        } on MarketFetchCancelledException {
          rethrow;
        } on _MarketBlockedException catch (error) {
          blockScan(error);
          if (error.protectionBytes case final evidence?) {
            try {
              final prefix = await evidence.timeout(
                marketProtectionProbeTimeout,
              );
              if (isProtectedMarketResponse(
                bytes: prefix,
                headers: error.headers,
              )) {
                protectScan();
              }
            } on Object {
              // Keep the header pause when its body stalls or cannot be read.
            }
          }
          for (final id in requestIds) {
            failures[id] = 'Market busy';
            if (blockedRetryable) {
              (books ? retryableBookFailures : retryableQuoteFailures).add(id);
            }
          }
        } on TimeoutException {
          _reduceConcurrency();
          for (final id in requestIds) {
            failures[id] = 'Market timed out';
            (books ? retryableBookFailures : retryableQuoteFailures).add(id);
          }
        } on FormatException {
          for (final id in requestIds) {
            failures[id] = books
                ? 'Order book unavailable'
                : 'Price unavailable';
          }
        } on _MarketHttpException catch (error) {
          if (error.statusCode >= 500) _reduceConcurrency();
          for (final id in requestIds) {
            failures[id] = 'Market returned ${error.statusCode}';
            if (error.statusCode >= 500) {
              (books ? retryableBookFailures : retryableQuoteFailures).add(id);
            }
          }
        } on Exception catch (error) {
          checkCancelled();
          for (final id in requestIds) {
            failures[id] = 'Market unavailable';
            if (isRetryableMarketTransportError(error)) {
              (books ? retryableBookFailures : retryableQuoteFailures).add(id);
            }
          }
        }
        completed += requestIds.length;
        progress?.call(completed, total);
      }
    }

    await Future.wait(List.generate(_effectiveConcurrency, worker));
    checkCancelled();
    return OpportunityMarketBatch(
      items: items,
      failures: failures,
      rateLimited: rateLimited,
      pause: rateLimited ? _pause : null,
      retryableQuoteFailures: retryableQuoteFailures,
      retryableBookFailures: retryableBookFailures,
    );
  }

  void _reduceConcurrency() {
    if (_effectiveConcurrency <= 2) return;
    final halved = _effectiveConcurrency ~/ 2;
    _effectiveConcurrency = halved < 2 ? 2 : halved;
  }

  Future<Uint8List> _request(
    List<String> ids,
    bool book,
    MarketCancellationToken? token,
    Future<void> blocked,
  ) async {
    final aborted = Completer<void>();
    var inspectingDenial = false;
    void abort() {
      if (!aborted.isCompleted) aborted.complete();
    }

    final cancellation = Future.any<void>([
      _closed.token.whenCancelled,
      if (token != null) token.whenCancelled,
    ]);
    final cancelled = cancellation.then<OpportunityHttpResponse>((_) {
      abort();
      throw const MarketFetchCancelledException();
    });
    final accessBlocked = blocked.then<OpportunityHttpResponse>((_) {
      // Preserve only the triggering denial's bounded prefix inspection.
      // Explicit cancellation and close still abort this request normally.
      if (!inspectingDenial) abort();
      throw const _MarketBlockedException();
    });
    final endpoint = book
        ? 'GetBiddingInfoList'
        : ids.length > 1
        ? 'GetWorldMarketSearchList'
        : 'GetWorldMarketSubList';
    final request = _transport.post(
      Uri.https(
        '$region-trade.naeu.playblackdesert.com',
        '/Trademarket/$endpoint',
      ),
      headers: const {
        'User-Agent': 'BlackDesert',
        'Content-Type': 'application/json',
        'Accept': '*/*',
      },
      body: jsonEncode(
        ids.length > 1
            ? {'searchResult': ids.join(',')}
            : {
                'keyType': 0,
                'mainKey': int.parse(ids.single),
                if (book) 'subKey': 0,
              },
      ),
      abortTrigger: aborted.future,
    );
    try {
      final response = await Future.any([
        request,
        cancelled,
        accessBlocked,
      ]).timeout(requestTimeout);
      final protected = isProtectedMarketResponse(
        bytes: response.bytes,
        headers: response.headers,
      );
      final retryAfter = marketRetryAfter(response.headers, _utcNow());
      if (protected ||
          response.statusCode == 429 ||
          (response.statusCode == 503 && retryAfter != null)) {
        inspectingDenial = response.protectionBytes != null;
        throw _MarketBlockedException(
          retryAfter: retryAfter,
          reason: protected
              ? MarketRequestPauseReason.protected
              : response.statusCode == 503
              ? MarketRequestPauseReason.serverUnavailable
              : MarketRequestPauseReason.throttled,
          retryable: !protected && response.statusCode == 503,
          protectionBytes: response.protectionBytes,
          headers: response.headers,
        );
      }
      if (response.statusCode != 200) {
        throw _MarketHttpException(response.statusCode);
      }
      return response.bytes;
    } on TimeoutException {
      abort();
      rethrow;
    }
  }
}

final class _MarketBlockedException implements Exception {
  const _MarketBlockedException({
    this.retryAfter,
    this.reason = MarketRequestPauseReason.throttled,
    this.retryable = false,
    this.protectionBytes,
    this.headers = const {},
  });
  final Duration? retryAfter;
  final MarketRequestPauseReason reason;
  final bool retryable;
  final Future<Uint8List>? protectionBytes;
  final Map<String, String> headers;
}

final class _MarketHttpException implements Exception {
  const _MarketHttpException(this.statusCode);
  final int statusCode;
}
