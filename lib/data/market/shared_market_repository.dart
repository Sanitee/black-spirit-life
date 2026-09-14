import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../domain/catalog/temporarily_archived_items.dart';
import '../../domain/market/shared_market_models.dart';
import '../../domain/market/shared_market_request_scope.dart';
import '../../domain/opportunities/opportunity_market_models.dart';
import '../opportunities/opportunity_market_bulk_codec.dart';
import '../opportunities/opportunity_market_cache_store.dart';
import '../opportunities/opportunity_market_codec.dart';
import '../opportunities/opportunity_market_service.dart';
import 'market_dispatch_policy.dart';
import 'market_pause_store.dart';
import 'market_request_pacer.dart';
import 'market_request_window.dart';
import 'market_response_guard.dart';

export '../../domain/market/market_cancellation.dart';
export '../../domain/market/shared_market_models.dart';
export '../../domain/market/shared_market_request_scope.dart';
export '../../domain/opportunities/opportunity_market_models.dart';

/// Verified EU Search boundary: a 999-character decimal/comma list succeeds;
/// 1,000 characters returns result code 21, even with fewer than 200 IDs.
/// This is independent of the per-batch item count and request-rate allowance.
const sharedMarketSearchCharacterLimit = 999;

/// One app-owned raw-data cache, client and rolling request pool. Each caller
/// owns only its subscription, not other features' overlapping network work.
final class SharedMarketRepository {
  /// The live app and its native workflow tests share one request policy.
  /// Books keep their single-item identity and normal server-issued session.
  /// Starts remain paced and concurrency bounded. The rolling allowance is an
  /// app safeguard, not a published API quota. A bounded 98-request fresh
  /// workload passed; larger earlier runs received protective HTML. Keep
  /// the shared ledger and server pause handling, including across restarts.
  factory SharedMarketRepository.application({
    OpportunityMarketCacheStore? cacheStore,
    MarketPauseStore? pauseStore,
    OpportunityMarketTransport? transport,
    DateTime Function()? utcNow,
  }) => SharedMarketRepository(
    cacheStore: cacheStore,
    pauseStore: pauseStore,
    transport: transport,
    utcNow: utcNow,
    concurrency: 20,
    primeSession: true,
    quoteBatchSize: 200,
    requestWindowLimit: 98,
    requestWindowDuration: const Duration(seconds: 60, milliseconds: 20),
    requestSpacing: const Duration(milliseconds: 40),
    orderBookRequestSpacing: const Duration(milliseconds: 40),
    recoveryRequestSpacing: const Duration(seconds: 1),
    requestTimeout: const Duration(seconds: 6),
    cacheMaxAge: sharedMarketFreshness,
    minimumQuoteRefreshAge: const Duration(minutes: 1),
    minimumBookRefreshAge: const Duration(minutes: 1),
  );

  SharedMarketRepository({
    this.cacheStore,
    MarketPauseStore? pauseStore,
    OpportunityMarketTransport? transport,
    DateTime Function()? utcNow,
    this.concurrency = 20,
    this.primeSession = false,
    this.quoteBatchSize = 40,
    this.requestTimeout = const Duration(seconds: 6),
    this.requestSpacing = const Duration(milliseconds: 40),
    Duration? orderBookRequestSpacing,
    this.recoveryRequestSpacing = const Duration(seconds: 1),
    this.cacheMaxAge = const Duration(hours: 3),
    this.minimumQuoteRefreshAge = Duration.zero,
    this.minimumBookRefreshAge = Duration.zero,
    this.requestWindowLimit,
    this.requestWindowDuration = const Duration(minutes: 1),
  }) : orderBookRequestSpacing =
           orderBookRequestSpacing ??
           (requestSpacing == Duration.zero
               ? Duration.zero
               : const Duration(milliseconds: 250)),
       pauseStore =
           pauseStore ??
           (cacheStore == null
               ? null
               : MarketPauseStore(
                   directory: File(cacheStore.path).parent,
                   utcNow: utcNow,
                 )),
       _transport = transport ?? HttpOpportunityMarketTransport(),
       _clock = utcNow ?? (() => DateTime.now().toUtc()) {
    if (concurrency < 1 ||
        concurrency > 40 ||
        quoteBatchSize < 1 ||
        quoteBatchSize > 200 ||
        requestTimeout <= Duration.zero ||
        requestSpacing.isNegative ||
        this.orderBookRequestSpacing.isNegative ||
        recoveryRequestSpacing.isNegative ||
        cacheMaxAge.isNegative ||
        minimumQuoteRefreshAge.isNegative ||
        minimumBookRefreshAge.isNegative) {
      throw ArgumentError('Invalid shared market configuration');
    }
    if (requestWindowLimit != null) {
      _requestWindow = MarketRequestWindow(
        limit: requestWindowLimit!,
        window: requestWindowDuration,
        utcNow: _clock,
      );
      if (cacheStore != null) {
        _requestWindowStore = MarketRequestWindowStore(
          directory: File(cacheStore!.path).parent,
        );
      }
    }
    _pacer = MarketRequestPacer(
      requestSpacing,
      onReady: _schedulePump,
      requestWindowDelay: () => _requestWindow?.remainingDelay ?? Duration.zero,
    );
    ready = _hydrate();
  }

  final OpportunityMarketCacheStore? cacheStore;
  final MarketPauseStore? pauseStore;
  final OpportunityMarketTransport _transport;
  final DateTime Function() _clock;
  final int concurrency;
  final bool primeSession;
  final int quoteBatchSize;
  final Duration requestTimeout;
  final Duration requestSpacing;
  final Duration orderBookRequestSpacing;
  final Duration recoveryRequestSpacing;
  late final MarketRequestPacer _pacer;
  final Duration cacheMaxAge;

  /// A forced refresh may reuse younger, valid quotes without relabeling their
  /// observation time. Zero retains unconditional forced-refresh behavior.
  final Duration minimumQuoteRefreshAge;

  /// A forced refresh may reuse younger, valid orderbooks without relabeling
  /// their observation time. Zero retains unconditional forced-refresh behavior.
  /// Ordinary reads still use [cacheMaxAge] or their explicit maximum age.
  final Duration minimumBookRefreshAge;
  final int? requestWindowLimit;
  final Duration requestWindowDuration;
  MarketRequestWindow? _requestWindow;
  MarketRequestWindowStore? _requestWindowStore;
  late final Future<void> ready;

  final _regions = <String, Map<String, OpportunityMarketItem>>{};
  final _sessionReadyRegions = <String>{};
  final _probingPauseRegions = <String>{};
  final _policies = <String, MarketDispatchPolicy>{};
  final _pauses = <String, MarketRequestPause>{};
  MarketRequestPause? pauseFor(String region) => _pauses[_region(region)];
  final _parts = <SharedMarketPartKey, _PendingPart>{};
  final _queue = <SharedMarketPartKey, _PendingPart>{};
  final _recentFailures =
      <
        SharedMarketPartKey,
        ({DateTime until, String reason, bool retryable})
      >{};
  final _calls = <_FetchCall>{};
  final _jobs = <_HttpJob>{};
  final _receipts = StreamController<SharedMarketReceipt>.broadcast();
  Stream<SharedMarketReceipt> get receipts => _receipts.stream;
  final _activity = StreamController<void>.broadcast();
  Stream<void> get activityChanges => _activity.stream;
  bool _hydrated = false;

  void _activityChanged() {
    if (!_closed && !_activity.isClosed) _activity.add(null);
  }

  bool _closed = false;
  bool _pumpScheduled = false;
  Future<void>? _closeFuture;
  Timer? _saveTimer;
  Future<void>? _saving;
  int _revision = 0;
  int _savedRevision = 0;
  Object? persistenceError;
  Object? pauseReadError;
  final _pauseReadAcknowledgedRegions = <String>{};
  int _started = 0, _completed = 0, _failed = 0;
  int _cacheHits = 0, _coalesced = 0, _peak = 0;

  SharedMarketDiagnostics get diagnostics => SharedMarketDiagnostics(
    startedRequests: _started,
    completedRequests: _completed,
    failedRequests: _failed,
    cacheHits: _cacheHits,
    coalescedParts: _coalesced,
    activeRequests: _jobs.length,
    queuedParts: _queue.length,
    peakActiveRequests: _peak,
    effectiveConcurrencyByRegion: Map.unmodifiable({
      for (final entry in _policies.entries)
        entry.key: entry.value.effectiveConcurrency,
    }),
  );

  OpportunityMarketSnapshot snapshot(String region) =>
      OpportunityMarketSnapshot(
        region: _region(region),
        items: _regions[_region(region)] ?? const {},
      );

  bool _quoteBatchCanAppend(int count, int characters, String id) =>
      count < quoteBatchSize &&
      characters + (count == 0 ? 0 : 1) + id.length <=
          sharedMarketSearchCharacterLimit;

  /// Timed wait for the next queued part in this caller's active scan, not
  /// admission for a new full refresh. Cache ages never contribute. This does
  /// not predict response time or concurrency/queue-order delays.
  Duration activeDispatchWait({
    required String region,
    Iterable<SharedMarketPartKey>? parts,
  }) {
    final selectedRegion = _region(region);
    if (_closed || !_hydrated) return Duration.zero;
    final selectedParts = parts?.toSet();
    Duration? earliest;
    final now = _clock();
    final pauseUntil =
        _policies[selectedRegion]?.blockedUntil ??
        _pauses[selectedRegion]?.retryAt;
    final pauseWait = pauseUntil?.difference(now) ?? Duration.zero;
    for (final part in _queue.values) {
      if (part.key.key.region != selectedRegion ||
          part.callers.isEmpty ||
          (selectedParts != null && !selectedParts.contains(part.key))) {
        continue;
      }
      var gap = part.key.part == SharedMarketPart.orderBook
          ? orderBookRequestSpacing
          : requestSpacing;
      if (part.callers.any((call) => call.recovery) &&
          gap < recoveryRequestSpacing) {
        gap = recoveryRequestSpacing;
      }
      var wait = _pacer.remainingDelayFor(gap);
      if (pauseWait > wait) wait = pauseWait;
      if (earliest == null || wait < earliest) earliest = wait;
    }
    return earliest ?? Duration.zero;
  }

  /// Uses the dispatch packer's count/character bounds, not one slot per price.
  /// A larger scope may still need staged loading; never wait forever for more
  /// free slots than the window can hold. Pending shared work is shown as busy.
  SharedMarketRefreshReadiness refreshReadiness({
    required String region,
    Iterable<SharedMarketKey> quoteKeys = const [],
    Iterable<SharedMarketKey> bookKeys = const [],
  }) {
    final selectedRegion = _region(region);
    final quotes = quoteKeys
        .where((key) => !isTemporarilyArchivedMarketItemId(key.itemId))
        .toSet();
    final books = bookKeys
        .where((key) => !isTemporarilyArchivedMarketItemId(key.itemId))
        .toSet();
    if ([...quotes, ...books].any((key) => key.region != selectedRegion)) {
      throw ArgumentError('Refresh readiness belongs to one market region');
    }
    if ([...quotes, ...books].any((key) => key.subId != 0)) {
      throw ArgumentError('Shared market currently supports subId 0 only');
    }
    var requests = books.length;
    var count = 0, characters = 0;
    for (final key in quotes) {
      if (!_quoteBatchCanAppend(count, characters, key.itemId)) {
        requests++;
        count = 0;
        characters = 0;
      }
      characters += key.itemId.length + (count == 0 ? 0 : 1);
      count++;
    }
    if (count > 0) requests++;
    final window = _requestWindow;
    final admittedStarts = window == null || requests <= window.limit
        ? requests
        : window.limit;
    var wait = window?.delayForStarts(admittedStarts) ?? Duration.zero;
    final now = _clock();
    void includeReceipt(DateTime? at, Duration minimumAge, bool valid) {
      if (!valid || at == null) return;
      final remaining = minimumAge - now.difference(at);
      if (remaining > wait) wait = remaining;
    }

    for (final key in quotes) {
      final item = _regions[selectedRegion]?[key.itemId];
      includeReceipt(
        item?.quoteFetchedAt,
        minimumQuoteRefreshAge,
        item?.quoteIsFresh(now, cacheMaxAge) ?? false,
      );
    }
    for (final key in books) {
      final item = _regions[selectedRegion]?[key.itemId];
      includeReceipt(
        item?.bookFetchedAt,
        minimumBookRefreshAge,
        item?.bookIsFresh(now, cacheMaxAge) ?? false,
      );
    }
    final pause = _pauses[selectedRegion];
    final pauseWait = pause?.retryAt.difference(now) ?? Duration.zero;
    if (pauseWait > wait) wait = pauseWait;
    return SharedMarketRefreshReadiness(
      wait: wait,
      requestCount: requests,
      windowLimit: requestWindowLimit,
      initializing: !_hydrated || _closed,
      pendingWork: _queue.isNotEmpty || _jobs.isNotEmpty,
      providerPaused: pause?.isActive(now) ?? false,
    );
  }

  Future<void> _hydrate() async {
    if (_requestWindowStore != null) {
      try {
        _requestWindow!.restore(await _requestWindowStore!.load());
      } on Object catch (error) {
        // An unreadable local allowance waits one window, rather than
        // treating all previous requests as if they never happened.
        _requestWindow!.restore(List.filled(requestWindowLimit!, _clock()));
        persistenceError = error;
        try {
          // Preserve the start of this conservative wait immediately. Without
          // repairing a malformed disposable ledger, every restart can begin
          // another full wait even though no additional request was sent.
          await _requestWindowStore!.save(_requestWindow!.snapshot());
        } on Object catch (saveError) {
          // A failed repair never grants fresh allowance or clears a pause.
          persistenceError = saveError;
        }
      }
    }
    try {
      final loaded = await cacheStore?.load();
      if (loaded != null) _regions.addAll(loaded);
    } on Object catch (error) {
      // An unreadable cache is not a reason to disable fresh market reads.
      // Keep the error available; do not label an empty cache as fresh data.
      persistenceError = error;
    }
    try {
      final loaded = await pauseStore?.load();
      if (loaded != null) _pauses.addAll(loaded);
    } on Object catch (error) {
      pauseReadError = error;
      persistenceError = error;
    }
    _hydrated = true;
    _activityChanged();
  }

  Future<SharedMarketBatch> fetch({
    Iterable<SharedMarketKey> quoteKeys = const [],
    Iterable<SharedMarketKey> bookKeys = const [],
    bool forceRefresh = false,
    bool recovery = false,
    bool userInitiated = false,
    Duration? maxAge,
    MarketCancellationToken? cancellationToken,
    SharedMarketRequestScope? scope,
    void Function(SharedMarketReceipt)? onItem,
    OpportunityMarketProgress? onProgress,
    Iterable<SharedMarketKey> Function()? priorityKeys,
    void Function()? onRateLimited,
  }) async {
    final requested = <SharedMarketPartKey>{
      for (final key in quoteKeys)
        SharedMarketPartKey(key, SharedMarketPart.quote),
      for (final key in bookKeys)
        SharedMarketPartKey(key, SharedMarketPart.orderBook),
    };
    if (requested.any((part) => part.key.subId != 0)) {
      throw ArgumentError('Shared market currently supports subId 0 only');
    }
    final age = maxAge ?? cacheMaxAge;
    if (age.isNegative) throw ArgumentError.value(age, 'maxAge');
    await ready;
    if (_closed) throw StateError('Shared market is closed');
    cancellationToken?.throwIfCancelled();
    requested.removeWhere((part) => scope?.isReleased(part) ?? false);
    final call = _FetchCall(
      requested,
      onItem,
      onProgress,
      priorityKeys,
      onRateLimited,
      recovery,
    );
    _calls.add(call);
    void release(Set<SharedMarketPartKey> parts) => _release(call, parts);
    scope?.addListener(release);
    if (cancellationToken != null) {
      unawaited(cancellationToken.whenCancelled.then((_) => _cancel(call)));
    }
    try {
      onProgress?.call(0, requested.length);
      final now = _clock();
      _recentFailures.removeWhere((_, failure) => !now.isBefore(failure.until));
      for (final part in requested) {
        if (call.done.isCompleted) break;
        if (!call.pending.contains(part)) continue;
        if (isTemporarilyArchivedMarketItemId(part.key.itemId)) {
          // User-selected temporary archive, not an assertion that PA removed
          // the item. Keep stored receipts untouched but do not replay or fetch.
          _deliver(call, part, null, failure: 'Item temporarily archived');
          continue;
        }
        final item = _regions[part.key.region]?[part.key.itemId];
        final fresh =
            item != null &&
            (part.part == SharedMarketPart.quote
                ? item.quoteIsFresh(now, age)
                : item.bookIsFresh(now, age));
        final recentPart =
            forceRefresh &&
            fresh &&
            (part.part == SharedMarketPart.quote
                ? now.difference(item.quoteFetchedAt!) < minimumQuoteRefreshAge
                : now.difference(item.bookFetchedAt!) < minimumBookRefreshAge);
        if ((!forceRefresh && fresh) || recentPart) {
          _cacheHits++;
          _deliver(call, part, _receipt(part, item, fromCache: true));
          continue;
        }
        if (!userInitiated &&
            pauseReadError != null &&
            !_pauseReadAcknowledgedRegions.contains(part.key.region)) {
          _deliver(call, part, null, failure: 'Market pause could not be read');
          continue;
        }
        final paused = _pauses[part.key.region];
        if (!userInitiated &&
            paused?.reason == MarketRequestPauseReason.protected) {
          _deliver(
            call,
            part,
            null,
            failure: 'Market busy',
            rateLimited: true,
            pause: paused,
          );
          continue;
        }
        if (_policy(part.key.region).isBlocked(now) ||
            _probingPauseRegions.contains(part.key.region)) {
          _deliver(
            call,
            part,
            null,
            failure: 'Market busy',
            rateLimited: true,
            pause: _pauses[part.key.region],
          );
          continue;
        }
        final existing = _parts[part];
        if (existing != null) {
          _coalesced++;
          existing.callers.add(call);
        } else {
          // Briefly avoid repeating an unavailable part on every tab visit.
          // This is not a market receipt or a persisted availability fact.
          final recentFailure = _recentFailures[part];
          if (!forceRefresh && recentFailure != null) {
            _deliver(
              call,
              part,
              null,
              failure: recentFailure.reason,
              retryable: recentFailure.retryable,
            );
            continue;
          }
          final pending = _PendingPart(part)..callers.add(call);
          _parts[part] = pending;
          _queue[part] = pending;
        }
      }
      if (requested.isEmpty) _complete(call);
      _activityChanged();
      _schedulePump();
      return await call.done.future;
    } on Object {
      _detach(call);
      rethrow;
    } finally {
      scope?.removeListener(release);
      _activityChanged();
    }
  }

  MarketDispatchPolicy _policy(String region) => _policies.putIfAbsent(
    region,
    () =>
        MarketDispatchPolicy(maximumConcurrency: concurrency)
          ..blockedUntil = _pauses[region]?.retryAt,
  );

  void _schedulePump() {
    if (_closed || _pumpScheduled) return;
    _pumpScheduled = true;
    scheduleMicrotask(() {
      _pumpScheduled = false;
      _pump();
    });
  }

  void _pump() {
    if (_closed || !_pacer.canStart) return;
    // Read dynamic feature priorities once per dispatch turn, not per item.
    final priorities = <SharedMarketKey>{};
    for (final call in _calls.toList().reversed) {
      try {
        priorities.addAll(call.priorityKeys?.call() ?? const []);
      } on Object {
        /* An optional UI priority must not fail a data request. */
      }
    }
    while (_jobs.length < concurrency && _queue.isNotEmpty && _pacer.canStart) {
      final activeByRegion = <String, int>{};
      for (final job in _jobs) {
        activeByRegion.update(
          job.region,
          (count) => count + 1,
          ifAbsent: () => 1,
        );
      }
      bool eligible(_PendingPart part) {
        final region = part.key.key.region;
        return !_policy(region).isBlocked(_clock()) &&
            !_probingPauseRegions.contains(region) &&
            (!primeSession ||
                _sessionReadyRegions.contains(region) ||
                (activeByRegion[region] ?? 0) == 0) &&
            (activeByRegion[region] ?? 0) <
                _policy(region).effectiveConcurrency;
      }

      _PendingPart? next;
      // Get inexpensive bulk prices/stock out first. This is dispatch order,
      // not a completion barrier: books can run while quotes are in flight.
      for (final kind in SharedMarketPart.values) {
        for (final key in priorities) {
          final candidate = _queue[SharedMarketPartKey(key, kind)];
          if (candidate != null && eligible(candidate)) {
            next = candidate;
            break;
          }
        }
        next ??= _queue.values
            .where((part) => part.key.part == kind && eligible(part))
            .firstOrNull;
        if (next != null) break;
      }
      if (next == null) break;
      Duration intervalFor(_PendingPart part) {
        var gap = part.key.part == SharedMarketPart.orderBook
            ? orderBookRequestSpacing
            : requestSpacing;
        if (part.callers.any((call) => call.recovery) &&
            gap < recoveryRequestSpacing) {
          gap = recoveryRequestSpacing;
        }
        return gap;
      }

      final selected = <_PendingPart>[next];
      if (next.key.part == SharedMarketPart.quote) {
        var searchCharacters = next.key.key.itemId.length;
        final candidates = <SharedMarketPartKey>{
          for (final key in priorities)
            SharedMarketPartKey(key, SharedMarketPart.quote),
          ..._queue.keys,
        };
        for (final key in candidates) {
          if (selected.length >= quoteBatchSize) break;
          final part = _queue[key];
          if (part == null || identical(part, next)) continue;
          if (part.key.part == SharedMarketPart.quote &&
              part.key.key.region == next.key.key.region) {
            final appendedLength = 1 + part.key.key.itemId.length;
            if (!_quoteBatchCanAppend(
              selected.length,
              searchCharacters,
              part.key.key.itemId,
            )) {
              // Keep this candidate queued for the next batch without changing
              // priority order, losing its subscribers or retrying a rejection.
              break;
            }
            selected.add(part);
            searchCharacters += appendedLength;
          }
        }
      }
      var gap = requestSpacing;
      for (final part in selected) {
        final requiredGap = intervalFor(part);
        if (requiredGap > gap) gap = requiredGap;
      }
      if (!_pacer.canStartFor(gap)) break;
      for (final part in selected) {
        _queue.remove(part.key);
      }
      final job = _HttpJob(selected);
      for (final part in selected) {
        part.job = job;
      }
      _jobs.add(job);
      _pacer.started(minimumInterval: gap);
      if (_requestWindow != null) {
        _requestWindow!.started();
        _revision++;
        _scheduleSave();
      }
      _started++;
      _activityChanged();
      if (_jobs.length > _peak) _peak = _jobs.length;
      job.finished = _execute(job);
    }
  }

  Future<void> _execute(_HttpJob job) async {
    final books = job.parts.first.key.part == SharedMarketPart.orderBook;
    final ids = job.parts.map((part) => part.key.key.itemId).toList();
    try {
      final endpoint = books
          ? 'GetBiddingInfoList'
          : ids.length > 1
          ? 'GetWorldMarketSearchList'
          : 'GetWorldMarketSubList';
      final response = await _transport
          .post(
            Uri.https(
              '${job.region}-trade.naeu.playblackdesert.com',
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
                      if (books) 'subKey': 0,
                    },
            ),
            abortTrigger: job.aborted.future,
          )
          .timeout(
            requestTimeout,
            onTimeout: () {
              job.abort();
              throw TimeoutException('Market timed out');
            },
          );
      if (job.cancelled && !_pauses.containsKey(job.region)) return;
      final now = _clock();
      final protected = isProtectedMarketResponse(
        bytes: response.bytes,
        headers: response.headers,
      );
      if (job.cancelled) {
        // A sibling denial can cancel this job after its response arrived.
        // Never publish a late receipt, but do retain stronger refusal evidence.
        if (protected) {
          _protectExistingPause(job.region);
        } else if (response.protectionBytes case final evidence?) {
          try {
            final prefix = await evidence.timeout(marketProtectionProbeTimeout);
            if (isProtectedMarketResponse(
              bytes: prefix,
              headers: response.headers,
            )) {
              _protectExistingPause(job.region);
            }
          } on Object {
            // The existing header pause remains authoritative.
          }
        }
        return;
      }
      final retryAfter = marketRetryAfter(response.headers, now);
      if (protected ||
          response.statusCode == 429 ||
          (response.statusCode == 503 && retryAfter != null)) {
        _failed++;
        await _blockOrigin(
          job,
          retryAfter,
          now,
          reason: protected
              ? MarketRequestPauseReason.protected
              : response.statusCode == 503
              ? MarketRequestPauseReason.serverUnavailable
              : MarketRequestPauseReason.throttled,
          retryable: !protected && response.statusCode == 503,
          protectionBytes: response.protectionBytes,
          headers: response.headers,
        );
        return;
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        _failed++;
        _policy(
          job.region,
        ).record(now, transientFailure: response.statusCode >= 500);
        _failJob(
          job,
          'Market returned ${response.statusCode}',
          retryable: response.statusCode >= 500,
        );
        return;
      }
      if (ids.length > 1) {
        final decoded = decodeOpportunityBulkQuotes(
          bytes: response.bytes,
          requestedIds: ids,
          fetchedAt: now,
        );
        if (decoded.items.isNotEmpty) _clearPauseOnSuccess(job.region);
        for (final part in job.parts) {
          final item = decoded.items[part.key.key.itemId];
          _finishPart(
            part,
            item,
            failure: decoded.failures[part.key.key.itemId],
          );
        }
      } else {
        final item = books
            ? decodeOpportunityOrderBook(
                bytes: response.bytes,
                itemId: ids.single,
                fetchedAt: now,
              )
            : decodeOpportunityQuote(
                bytes: response.bytes,
                itemId: ids.single,
                fetchedAt: now,
              );
        _clearPauseOnSuccess(job.region);
        _finishPart(job.parts.single, item);
      }
      _policy(job.region).record(now, transientFailure: false);
    } on TimeoutException {
      if (!job.cancelled) {
        _failed++;
        _policy(job.region).record(_clock(), transientFailure: true);
        _failJob(job, 'Market timed out', retryable: true);
      }
    } on FormatException {
      if (!job.cancelled) {
        _failed++;
        _failJob(job, books ? 'Order book unavailable' : 'Price unavailable');
      }
    } on Object catch (error) {
      if (!job.cancelled) {
        _failed++;
        final retryable = isRetryableMarketTransportError(error);
        _policy(job.region).record(_clock(), transientFailure: retryable);
        _failJob(job, 'Market unavailable', retryable: retryable);
      }
    } finally {
      _completed++;
      _jobs.remove(job);
      _activityChanged();
      _schedulePump();
    }
  }

  void _clearPauseOnSuccess(String region) {
    // Finish one ordinary response before the initial parallel fan-out. That
    // lets the transport keep the server's session instead of creating several
    // unrelated cookie sets whose responses could overwrite each other.
    _sessionReadyRegions.add(region);
    final removed = _pauses.remove(region) != null;
    final acknowledged =
        pauseReadError != null && _pauseReadAcknowledgedRegions.add(region);
    if (removed || acknowledged) {
      // A healthy explicitly requested EU response proves nothing about NA's
      // unknown pause in a malformed file. Keep the error and other region shut.
      _policy(region).blockedUntil = null;
      _revision++;
      _scheduleSave();
    }
  }

  void _protectExistingPause(String region) {
    final previous = _pauses[region];
    if (previous == null ||
        previous.reason == MarketRequestPauseReason.protected) {
      return;
    }
    _pauses[region] = MarketRequestPause(
      reason: MarketRequestPauseReason.protected,
      retryAt: previous.retryAt,
    );
    _revision++;
    _scheduleSave();
  }

  Future<void> _blockOrigin(
    _HttpJob trigger,
    Duration? retryAfter,
    DateTime now, {
    required MarketRequestPauseReason reason,
    bool retryable = false,
    Future<Uint8List>? protectionBytes,
    Map<String, String> headers = const {},
  }) async {
    // Latch before callbacks: reentrant Refresh/Stop cannot escape the pause.
    _policy(
      trigger.region,
    ).rateLimited(now, retryAfter ?? const Duration(seconds: 60));
    final previous = _pauses[trigger.region];
    var pause = MarketRequestPause(
      reason:
          previous?.isActive(now) == true &&
              previous!.reason == MarketRequestPauseReason.protected
          ? MarketRequestPauseReason.protected
          : reason,
      retryAt: _policy(trigger.region).blockedUntil!,
    );
    _pauses[trigger.region] = pause;
    _activityChanged();
    if (protectionBytes != null) _probingPauseRegions.add(trigger.region);
    _revision++;
    _scheduleSave();
    final stoppedJobs = _jobs
        .where((job) => job.region == trigger.region)
        .toList();
    final stoppedQueue = _queue.values
        .where((part) => part.key.key.region == trigger.region)
        .toList();
    for (final job in stoppedJobs) {
      job.cancelled = true;
      // Other requests stop at the headers. The triggering body may still
      // contain the evidence that requires a manual protection latch.
      if (protectionBytes == null || !identical(job, trigger)) job.abort();
    }
    try {
      if (protectionBytes != null) {
        try {
          final bytes = await protectionBytes.timeout(
            marketProtectionProbeTimeout,
          );
          if (isProtectedMarketResponse(bytes: bytes, headers: headers)) {
            // Classification may only strengthen a pause. Keep the deadline
            // already established from its headers, including Retry-After: 0.
            _protectExistingPause(trigger.region);
          }
        } on Object {
          // A missing or broken body cannot invalidate an HTTP refusal.
        }
      }
    } finally {
      trigger.abort();
      // An already-received sibling denial may have strengthened this pause
      // while the triggering response's bounded body was being inspected.
      if (_pauses[trigger.region]?.reason ==
          MarketRequestPauseReason.protected) {
        pause = _pauses[trigger.region]!;
      }
      for (final job in stoppedJobs) {
        _failJob(
          job,
          'Market busy',
          rateLimited: true,
          pause: pause,
          retryable:
              retryable && pause.reason != MarketRequestPauseReason.protected,
        );
      }
      for (final part in stoppedQueue) {
        _finishPart(
          part,
          null,
          failure: 'Market busy',
          rateLimited: true,
          pause: pause,
          retryable:
              retryable && pause.reason != MarketRequestPauseReason.protected,
        );
      }
      _probingPauseRegions.remove(trigger.region);
    }
  }

  void _failJob(
    _HttpJob job,
    String reason, {
    bool rateLimited = false,
    bool retryable = false,
    MarketRequestPause? pause,
  }) {
    for (final part in job.parts) {
      _finishPart(
        part,
        null,
        failure: reason,
        rateLimited: rateLimited,
        retryable: retryable,
        pause: pause,
      );
    }
  }

  void _finishPart(
    _PendingPart part,
    OpportunityMarketItem? item, {
    String? failure,
    bool rateLimited = false,
    bool retryable = false,
    MarketRequestPause? pause,
  }) {
    if (identical(_parts[part.key], part)) _parts.remove(part.key);
    if (identical(_queue[part.key], part)) _queue.remove(part.key);
    SharedMarketReceipt? receipt;
    if (item != null) {
      _recentFailures.remove(part.key);
      final region = _regions.putIfAbsent(part.key.key.region, () => {});
      region[item.itemId] = region[item.itemId]?.mergeFrom(item) ?? item;
      receipt = _receipt(part.key, item, fromCache: false);
      _revision++;
      _scheduleSave();
      if (!_receipts.isClosed) _receipts.add(receipt);
    } else if (!rateLimited && part.callers.isNotEmpty) {
      _recentFailures[part.key] = (
        until: _clock().add(const Duration(seconds: 30)),
        reason: failure ?? 'Market unavailable',
        retryable: retryable,
      );
    }
    for (final call in part.callers.toList()) {
      _deliver(
        call,
        part.key,
        receipt,
        failure: failure ?? (item == null ? 'Market unavailable' : null),
        rateLimited: rateLimited,
        retryable: retryable,
        pause: pause,
      );
    }
    part.callers.clear();
  }

  SharedMarketReceipt _receipt(
    SharedMarketPartKey part,
    OpportunityMarketItem item, {
    required bool fromCache,
  }) => SharedMarketReceipt(
    key: part.key,
    part: part.part,
    fromCache: fromCache,
    item: part.part == SharedMarketPart.quote
        ? OpportunityMarketItem(
            itemId: item.itemId,
            subId: item.subId,
            basePrice: item.basePrice,
            stock: item.stock,
            aggregateStock: item.aggregateStock,
            quoteFetchedAt: item.quoteFetchedAt,
            totalTrades: item.totalTrades,
            lastSoldAt: item.lastSoldAt,
            unlisted: item.unlisted,
          )
        : OpportunityMarketItem(
            itemId: item.itemId,
            subId: item.subId,
            asks: item.asks,
            bids: item.bids,
            bookFetchedAt: item.bookFetchedAt,
          ),
  );

  void _deliver(
    _FetchCall call,
    SharedMarketPartKey part,
    SharedMarketReceipt? receipt, {
    String? failure,
    bool rateLimited = false,
    bool retryable = false,
    MarketRequestPause? pause,
  }) {
    if (call.done.isCompleted || !call.pending.remove(part)) return;
    try {
      if (pause != null) call.pauses[part.key.region] = pause;
      if (rateLimited && !call.rateLimited) {
        call.rateLimited = true;
        call.onRateLimited?.call();
      }
      if (receipt != null) {
        call.items[part.key] =
            call.items[part.key]?.mergeFrom(receipt.item) ?? receipt.item;
        call.onItem?.call(receipt);
      } else {
        call.failures[part] = failure ?? 'Market unavailable';
        if (retryable) call.retryableFailures.add(part);
      }
      call.onProgress?.call(call.total - call.pending.length, call.total);
      if (call.pending.isEmpty) _complete(call);
    } on Object catch (error, stack) {
      // A broken subscriber must not poison another feature's good receipt.
      _detach(call);
      call.done.completeError(error, stack);
    }
  }

  void _complete(_FetchCall call) {
    _calls.remove(call);
    if (!call.done.isCompleted) {
      call.done.complete(
        SharedMarketBatch(
          items: call.items,
          failures: call.failures,
          rateLimited: call.rateLimited,
          retryableFailures: call.retryableFailures,
          pauses: call.pauses,
        ),
      );
    }
  }

  void _cancel(_FetchCall call) {
    if (call.done.isCompleted) return;
    _detach(call);
    call.done.completeError(const MarketFetchCancelledException());
  }

  void _detach(_FetchCall call) {
    _calls.remove(call);
    _detachParts(call, call.pending);
  }

  void _release(_FetchCall call, Set<SharedMarketPartKey> parts) {
    if (call.done.isCompleted) return;
    final released = call.requested.intersection(parts);
    if (released.isEmpty) return;
    final pending = call.pending.intersection(released);
    call.requested.removeAll(released);
    call.pending.removeAll(released);
    call.failures.removeWhere((part, _) => released.contains(part));
    call.retryableFailures.removeAll(released);
    _detachParts(call, pending);
    try {
      // Released interest is neither a successful receipt nor a failure. Only
      // the still-requested parts contribute to this caller's progress.
      call.onProgress?.call(call.total - call.pending.length, call.total);
      if (call.pending.isEmpty) _complete(call);
    } on Object catch (error, stack) {
      _detach(call);
      if (!call.done.isCompleted) call.done.completeError(error, stack);
    }
    _schedulePump();
  }

  void _detachParts(_FetchCall call, Iterable<SharedMarketPartKey> parts) {
    for (final key in parts) {
      final pending = _parts[key];
      if (pending == null) continue;
      pending.callers.remove(call);
      if (pending.callers.isEmpty && pending.job == null) {
        _parts.remove(key);
        _queue.remove(key);
      }
    }
    for (final job in _jobs.toList()) {
      if (job.parts.every((part) => part.callers.isEmpty)) {
        job.cancelled = true;
        job.abort();
        for (final part in job.parts) {
          if (identical(_parts[part.key], part)) _parts.remove(part.key);
        }
      }
    }
  }

  void _scheduleSave() {
    if (_closed || (cacheStore == null && pauseStore == null)) return;
    // Continuous receipts must not postpone persistence until the full scan
    // ends. At most one checkpoint is scheduled; disk work stays off dispatch.
    if (_saveTimer != null) return;
    _saveTimer = Timer(const Duration(seconds: 2), () {
      _saveTimer = null;
      unawaited(
        flush().catchError((Object error) {
          persistenceError = error;
        }),
      );
    });
  }

  /// Persists current receipts without cancelling or waiting for other callers.
  Future<void> flush() async {
    // Hydrating an unchanged cache creates nothing to save. In particular,
    // closing an unused tab must not wait for an unrelated disk read.
    if (_saving == null &&
        ((cacheStore == null && pauseStore == null) ||
            _savedRevision >= _revision)) {
      return;
    }
    await ready;
    _saveTimer?.cancel();
    _saveTimer = null;
    while (_saving != null) {
      await _saving;
    }
    if ((cacheStore == null && pauseStore == null) ||
        _savedRevision >= _revision) {
      return;
    }
    final revision = _revision;
    final copy = <String, Map<String, OpportunityMarketItem>>{
      for (final region in _regions.entries) region.key: Map.of(region.value),
    };
    final pauseCopy = Map<String, MarketRequestPause>.of(_pauses);
    final write = Future.wait<void>([
      if (_requestWindowStore != null)
        _requestWindowStore!.save(_requestWindow!.snapshot()),
      if (cacheStore != null) cacheStore!.save(copy),
      if (pauseStore != null) pauseStore!.save(pauseCopy),
    ]).then<void>((_) {});
    _saving = write;
    try {
      await write;
      _savedRevision = revision;
      persistenceError = null;
    } on Object catch (error) {
      persistenceError = error;
      rethrow;
    } finally {
      if (identical(_saving, write)) _saving = null;
    }
    if (_savedRevision < _revision) await flush();
  }

  Future<void> close() => _closeFuture ??= _close();
  Future<void> dispose() => close();
  Future<void> _close() async {
    _closed = true;
    _pacer.close();
    _saveTimer?.cancel();
    for (final call in _calls.toList()) {
      _cancel(call);
    }
    _transport.close();
    await Future.wait(_jobs.toList().map((job) => job.finished));
    try {
      await flush();
    } on Object catch (error) {
      // Optional raw market data must never prevent profile saves or shutdown.
      persistenceError = error;
    } finally {
      await _receipts.close();
      await _activity.close();
    }
  }

  static String _region(String region) {
    final value = region.trim().toLowerCase();
    if (!const {'eu', 'na'}.contains(value)) {
      throw ArgumentError.value(region, 'region');
    }
    return value;
  }
}

final class _FetchCall {
  _FetchCall(
    Set<SharedMarketPartKey> requested,
    this.onItem,
    this.onProgress,
    this.priorityKeys,
    this.onRateLimited,
    this.recovery,
  ) : requested = Set.of(requested),
      pending = Set.of(requested);
  final Set<SharedMarketPartKey> requested;
  final Set<SharedMarketPartKey> pending;
  int get total => requested.length;
  final void Function(SharedMarketReceipt)? onItem;
  final OpportunityMarketProgress? onProgress;
  final Iterable<SharedMarketKey> Function()? priorityKeys;
  final void Function()? onRateLimited;
  final bool recovery;
  final done = Completer<SharedMarketBatch>();
  final items = <SharedMarketKey, OpportunityMarketItem>{};
  final failures = <SharedMarketPartKey, String>{};
  final retryableFailures = <SharedMarketPartKey>{};
  final pauses = <String, MarketRequestPause>{};
  bool rateLimited = false;
}

final class _PendingPart {
  _PendingPart(this.key);
  final SharedMarketPartKey key;
  final callers = <_FetchCall>{};
  _HttpJob? job;
}

final class _HttpJob {
  _HttpJob(this.parts);
  final List<_PendingPart> parts;
  String get region => parts.first.key.key.region;
  final aborted = Completer<void>();
  bool cancelled = false;
  late final Future<void> finished;
  void abort() {
    if (!aborted.isCompleted) aborted.complete();
  }
}
