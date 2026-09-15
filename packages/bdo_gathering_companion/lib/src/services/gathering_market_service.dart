import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// A successfully fetched Pearl Abyss market quote for one base item.
final class GatheringMarketQuote {
  const GatheringMarketQuote({
    required this.itemId,
    required this.price,
    required this.stock,
    required this.fetchedAt,
    this.preorders,
  });

  final int itemId;
  final int price;

  /// Current listings reported by Pearl Abyss.
  ///
  /// Zero is a known, meaningful value. `null` means the response supplied a
  /// usable price without a usable stock field.
  final int? stock;

  /// Current buy orders reported by Pearl Abyss's price-level order book.
  ///
  /// Zero is a known, meaningful value. `null` means the order book was not
  /// requested or could not be decoded; it must never be presented as zero.
  final int? preorders;
  final DateTime fetchedAt;

  bool get hasKnownStock => stock != null;
  bool get hasKnownPreorders => preorders != null;
}

/// One best-effort base-market pass, keeping a real unavailable item distinct
/// from a request that failed before Pearl Abyss supplied a usable answer.
final class GatheringMarketBaseBatch {
  const GatheringMarketBaseBatch({
    required this.quotes,
    required this.unavailableItemIds,
    required this.failedItemIds,
  });

  final Map<int, GatheringMarketQuote> quotes;
  final Set<int> unavailableItemIds;
  final Set<int> failedItemIds;
}

/// A paced order-book pass. Deferred IDs were not contacted because the
/// bounded failure circuit opened; they remain unknown, never zero.
final class GatheringPreorderBatch {
  const GatheringPreorderBatch({
    required this.counts,
    required this.failedItemIds,
    required this.deferredItemIds,
  });

  final Map<int, int> counts;
  final Set<int> failedItemIds;
  final Set<int> deferredItemIds;
}

/// The transport-level request exposed for deterministic tests.
final class GatheringMarketHttpRequest {
  GatheringMarketHttpRequest({
    required this.uri,
    required Map<String, String> headers,
    required this.body,
  }) : headers = Map.unmodifiable(headers);

  final Uri uri;
  final Map<String, String> headers;
  final String body;
}

/// The minimum HTTP response surface needed by [GatheringMarketService].
final class GatheringMarketHttpResponse {
  const GatheringMarketHttpResponse({
    required this.statusCode,
    required this.body,
    this.bodyBytes,
  });

  final int statusCode;
  final String body;
  final Uint8List? bodyBytes;
}

typedef GatheringMarketTransport =
    Future<GatheringMarketHttpResponse> Function(
      GatheringMarketHttpRequest request,
    );

/// UI-friendly loader signature for item catalogs keyed by their BDO IDs.
typedef GatheringMarketLoader =
    Future<Map<String, GatheringMarketQuote>> Function(
      Map<String, String> itemsById,
    );

/// Fetches current EU market prices and stock from Pearl Abyss.
///
/// A batch is intentionally best-effort: a failed or malformed item is omitted
/// while the remaining quotes are still returned.
final class GatheringMarketService {
  GatheringMarketService({
    GatheringMarketTransport? transport,
    HttpClient? httpClient,
    DateTime Function()? now,
    Future<void> Function(Duration)? delay,
    this.requestTimeout = const Duration(seconds: 12),
    this.baseRetrySpacing = const Duration(milliseconds: 110),
    this.baseRetryBaseDelay = const Duration(milliseconds: 300),
    this.maximumBaseAttempts = 2,
    this.preorderRequestSpacing = const Duration(milliseconds: 140),
    this.preorderRetryBaseDelay = const Duration(milliseconds: 350),
    this.maximumPreorderAttempts = 2,
    this.maximumConsecutivePreorderFailures = 3,
  }) : _transport = transport,
       _httpClient = transport == null ? (httpClient ?? HttpClient()) : null,
       _ownsHttpClient = transport == null && httpClient == null,
       _now = now ?? DateTime.now,
       _delay = delay ?? Future<void>.delayed,
       assert(maximumBaseAttempts > 0),
       assert(maximumPreorderAttempts > 0),
       assert(maximumConsecutivePreorderFailures > 0);

  static final Uri endpoint = Uri.parse(
    'https://eu-trade.naeu.playblackdesert.com/'
    'Trademarket/GetWorldMarketSubList',
  );
  static final Uri orderBookEndpoint = Uri.parse(
    'https://eu-trade.naeu.playblackdesert.com/'
    'Trademarket/GetBiddingInfoList',
  );
  static const int maximumConcurrency = 4;
  static const int _maximumItemId = 0x7fffffff;
  static const int _maximumOrderBookBytes = 1024 * 1024;

  final GatheringMarketTransport? _transport;
  final HttpClient? _httpClient;
  final bool _ownsHttpClient;
  final DateTime Function() _now;
  final Future<void> Function(Duration) _delay;
  final Duration requestTimeout;
  final Duration baseRetrySpacing;
  final Duration baseRetryBaseDelay;
  final int maximumBaseAttempts;
  final Duration preorderRequestSpacing;
  final Duration preorderRetryBaseDelay;
  final int maximumPreorderAttempts;
  final int maximumConsecutivePreorderFailures;
  Future<void> _preorderTail = Future<void>.value();
  bool _hasSentPreorderRequest = false;

  /// Fetches quotes for a UI item map and returns canonical string ID keys.
  ///
  /// The map values are descriptive item names owned by the caller; the market
  /// endpoint needs only the numeric keys.
  Future<Map<String, GatheringMarketQuote>> fetch(
    Map<String, String> itemsById, {
    bool includePreorders = false,
  }) async {
    final quotes = await fetchQuotes(
      itemsById.keys,
      includePreorders: includePreorders,
    );
    return Map.unmodifiable({
      for (final entry in quotes.entries) entry.key.toString(): entry.value,
    });
  }

  /// Returns an immutable, de-duplicated map keyed by numeric item ID.
  ///
  /// Positive integer IDs and their decimal string equivalents are accepted.
  /// Invalid, non-integral, and out-of-range values are ignored.
  Future<Map<int, GatheringMarketQuote>> fetchQuotes(
    Iterable<Object?> itemIds, {
    bool includePreorders = false,
  }) async {
    final base = await fetchBaseQuotes(itemIds);
    if (!includePreorders || base.quotes.isEmpty) return base.quotes;
    final orderBooks = await fetchPreorderCounts(base.quotes.keys);
    return Map.unmodifiable({
      for (final entry in base.quotes.entries)
        entry.key: GatheringMarketQuote(
          itemId: entry.value.itemId,
          price: entry.value.price,
          stock: entry.value.stock,
          fetchedAt: entry.value.fetchedAt,
          preorders: orderBooks.counts[entry.key],
        ),
    });
  }

  /// Fetches only price and seller stock. Optional order books never delay or
  /// invalidate this result.
  Future<GatheringMarketBaseBatch> fetchBaseQuotes(
    Iterable<Object?> itemIds,
  ) async {
    final ids = _normalizedIds(itemIds);
    if (ids.isEmpty) {
      return const GatheringMarketBaseBatch(
        quotes: <int, GatheringMarketQuote>{},
        unavailableItemIds: <int>{},
        failedItemIds: <int>{},
      );
    }

    final fetched = <int, GatheringMarketQuote>{};
    final unavailable = <int>{};
    final failed = <int>{};
    var nextIndex = 0;

    Future<void> worker() async {
      while (nextIndex < ids.length) {
        final id = ids[nextIndex++];
        try {
          final result = await _fetchBaseQuote(id);
          if (result.quote case final quote?) {
            fetched[id] = quote;
          } else if (result.unavailable) {
            unavailable.add(id);
          } else {
            failed.add(id);
          }
        } on Object {
          failed.add(id);
        }
      }
    }

    final workerCount = ids.length < maximumConcurrency
        ? ids.length
        : maximumConcurrency;
    await Future.wait(List.generate(workerCount, (_) => worker()));

    for (
      var attempt = 1;
      attempt < maximumBaseAttempts && failed.isNotEmpty;
      attempt += 1
    ) {
      if (baseRetryBaseDelay > Duration.zero) {
        await _delay(
          Duration(
            milliseconds:
                baseRetryBaseDelay.inMilliseconds * (1 << (attempt - 1)),
          ),
        );
      }
      final retryIds = <int>[
        for (final id in ids)
          if (failed.contains(id)) id,
      ];
      for (var index = 0; index < retryIds.length; index += 1) {
        if (index > 0 && baseRetrySpacing > Duration.zero) {
          await _delay(baseRetrySpacing);
        }
        final id = retryIds[index];
        try {
          final result = await _fetchBaseQuote(id);
          if (result.quote case final quote?) {
            fetched[id] = quote;
            failed.remove(id);
          } else if (result.unavailable) {
            unavailable.add(id);
            failed.remove(id);
          }
        } on Object {
          // Leave this ID in the final failed set.
        }
      }
    }

    final ordered = <int, GatheringMarketQuote>{};
    for (final id in ids) {
      final quote = fetched[id];
      if (quote != null) ordered[id] = quote;
    }
    return GatheringMarketBaseBatch(
      quotes: Map.unmodifiable(ordered),
      unavailableItemIds: Set.unmodifiable(unavailable),
      failedItemIds: Set.unmodifiable(failed),
    );
  }

  /// Fetches buy-order totals in caller priority order with deliberately low
  /// pressure on Pearl Abyss's per-item endpoint.
  Future<GatheringPreorderBatch> fetchPreorderCounts(
    Iterable<Object?> itemIds,
  ) {
    final ids = _normalizedIds(itemIds);
    if (ids.isEmpty) {
      return Future.value(
        const GatheringPreorderBatch(
          counts: <int, int>{},
          failedItemIds: <int>{},
          deferredItemIds: <int>{},
        ),
      );
    }

    final previous = _preorderTail;
    final completer = Completer<GatheringPreorderBatch>();
    _preorderTail = () async {
      await previous;
      try {
        completer.complete(await _fetchPreorderCountsSerial(ids));
      } on Object catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    }();
    return completer.future;
  }

  Future<GatheringPreorderBatch> _fetchPreorderCountsSerial(
    List<int> ids,
  ) async {
    final counts = <int, int>{};
    final failed = <int>{};
    var consecutiveFailedAttempts = 0;
    var attemptedCount = 0;
    var circuitOpen = false;
    for (final id in ids) {
      attemptedCount += 1;
      int? count;
      for (var attempt = 0; attempt < maximumPreorderAttempts; attempt += 1) {
        if (_hasSentPreorderRequest && preorderRequestSpacing > Duration.zero) {
          await _delay(preorderRequestSpacing);
        }
        _hasSentPreorderRequest = true;
        count = await _fetchPreordersOnce(id);
        if (count != null) {
          consecutiveFailedAttempts = 0;
          break;
        }
        consecutiveFailedAttempts += 1;
        if (consecutiveFailedAttempts >= maximumConsecutivePreorderFailures) {
          circuitOpen = true;
          break;
        }
        if (attempt + 1 < maximumPreorderAttempts &&
            preorderRetryBaseDelay > Duration.zero) {
          await _delay(
            Duration(
              milliseconds:
                  preorderRetryBaseDelay.inMilliseconds * (1 << attempt),
            ),
          );
        }
      }
      if (count != null) {
        counts[id] = count;
      } else {
        failed.add(id);
        if (circuitOpen) break;
      }
    }
    final deferred = ids.skip(attemptedCount).toSet();
    return GatheringPreorderBatch(
      counts: Map.unmodifiable(counts),
      failedItemIds: Set.unmodifiable(failed),
      deferredItemIds: Set.unmodifiable(deferred),
    );
  }

  /// Releases the internally-created HTTP client.
  ///
  /// An injected [HttpClient] remains owned by its caller.
  void close() {
    if (_ownsHttpClient) _httpClient?.close();
  }

  Future<_BaseQuoteFetch> _fetchBaseQuote(int itemId) async {
    final body = jsonEncode({'keyType': 0, 'mainKey': itemId});
    final request = GatheringMarketHttpRequest(
      uri: endpoint,
      headers: const {
        HttpHeaders.userAgentHeader: 'BlackDesert',
        HttpHeaders.acceptHeader: 'application/json',
        HttpHeaders.contentTypeHeader: 'application/json',
      },
      body: body,
    );
    final response = await _send(request);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      return const _BaseQuoteFetch.failed();
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException {
      return const _BaseQuoteFetch.failed();
    }
    if (decoded is! Map) return const _BaseQuoteFetch.failed();
    final resultCode = decoded['resultCode'];
    if (resultCode != null && resultCode.toString() != '0') {
      return const _BaseQuoteFetch.failed();
    }
    final resultMessage = decoded['resultMsg'];
    if (resultMessage is! String) return const _BaseQuoteFetch.failed();

    for (final compactRow in resultMessage.split('|')) {
      if (compactRow.isEmpty) continue;
      final fields = compactRow.split('-');
      if (fields.length < 4 || int.tryParse(fields[0]) != itemId) continue;
      final price = int.tryParse(fields[3]);
      if (price == null || price < 0) return const _BaseQuoteFetch.failed();
      final parsedStock = fields.length > 4 ? int.tryParse(fields[4]) : null;
      final stock = parsedStock != null && parsedStock >= 0
          ? parsedStock
          : null;
      return _BaseQuoteFetch.success(
        GatheringMarketQuote(
          itemId: itemId,
          price: price,
          stock: stock,
          fetchedAt: _now().toUtc(),
        ),
      );
    }
    return const _BaseQuoteFetch.unavailable();
  }

  Future<int?> _fetchPreordersOnce(int itemId) async {
    try {
      final request = GatheringMarketHttpRequest(
        uri: orderBookEndpoint,
        headers: const {
          HttpHeaders.userAgentHeader: 'BlackDesert',
          HttpHeaders.acceptHeader: 'application/octet-stream',
          HttpHeaders.contentTypeHeader: 'application/json',
        },
        body: jsonEncode({'keyType': 0, 'mainKey': itemId, 'subKey': 0}),
      );
      final response = await _send(request);
      if (response.statusCode < 200 || response.statusCode >= 300) return null;
      final resultMessage = _orderBookResultMessage(response);
      if (resultMessage == null) return null;

      var total = 0;
      var sawRow = false;
      for (final compactRow in resultMessage.split('|')) {
        if (compactRow.isEmpty) continue;
        final fields = compactRow.split('-');
        if (fields.length < 3) return null;
        final price = int.tryParse(fields[0]);
        final sellers = int.tryParse(fields[1]);
        final buyers = int.tryParse(fields[2]);
        if (price == null ||
            sellers == null ||
            buyers == null ||
            price < 0 ||
            sellers < 0 ||
            buyers < 0) {
          return null;
        }
        total += buyers;
        sawRow = true;
      }
      return sawRow ? total : null;
    } on Object {
      // The live listing quote remains useful if the optional order book is
      // unavailable or Pearl Abyss changes its compressed response again.
      return null;
    }
  }

  String? _orderBookResultMessage(GatheringMarketHttpResponse response) {
    final bytes = response.bodyBytes;
    if (bytes != null && bytes.isNotEmpty) {
      final decoded = _decodePearlAbyssHuffman(bytes);
      if (decoded != null) return decoded;
    }
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) return null;
      final resultCode = decoded['resultCode'];
      if (resultCode != null && resultCode.toString() != '0') return null;
      return decoded['resultMsg'] is String
          ? decoded['resultMsg'] as String
          : null;
    } on FormatException {
      return null;
    }
  }

  Future<GatheringMarketHttpResponse> _send(
    GatheringMarketHttpRequest requestData,
  ) async {
    final transport = _transport;
    if (transport != null) {
      return transport(requestData).timeout(requestTimeout);
    }

    final request = await _httpClient!
        .postUrl(requestData.uri)
        .timeout(requestTimeout);
    requestData.headers.forEach(request.headers.set);
    request.add(utf8.encode(requestData.body));
    final response = await request.close().timeout(requestTimeout);
    final builder = BytesBuilder(copy: false);
    await for (final chunk in response.timeout(requestTimeout)) {
      builder.add(chunk);
      if (builder.length > _maximumOrderBookBytes) {
        throw const FormatException('Market response is too large.');
      }
    }
    final bodyBytes = builder.takeBytes();
    final body = utf8.decode(bodyBytes, allowMalformed: true);
    return GatheringMarketHttpResponse(
      statusCode: response.statusCode,
      body: body,
      bodyBytes: bodyBytes,
    );
  }

  /// Decodes the compact frequency-table response currently returned by
  /// Pearl Abyss for `GetBiddingInfoList`.
  ///
  /// The heap deliberately compares only frequency. Its equal-frequency
  /// behavior mirrors the endpoint's Java priority-queue decoder; adding a
  /// secondary sort key produces plausible-looking but incorrect order counts.
  static String? _decodePearlAbyssHuffman(Uint8List bytes) {
    if (bytes.length < 24 || bytes.length > _maximumOrderBookBytes) return null;

    final data = ByteData.sublistView(bytes);
    int readUint32(int offset) => data.getUint32(offset, Endian.little);

    final declaredBytes = readUint32(0);
    final resultCode = readUint32(4);
    final symbolCount = readUint32(8);
    if (declaredBytes != bytes.length ||
        resultCode != 0 ||
        symbolCount == 0 ||
        symbolCount > 256) {
      return null;
    }

    final sizeOffset = 12 + symbolCount * 8;
    if (sizeOffset + 12 > bytes.length) return null;
    final heap = _FrequencyHeap();
    var frequencyTotal = 0;
    for (var index = 0; index < symbolCount; index += 1) {
      final offset = 12 + index * 8;
      final frequency = readUint32(offset);
      final character = bytes[offset + 4];
      if (frequency == 0) return null;
      frequencyTotal += frequency;
      heap.add(_HuffmanNode.leaf(character, frequency));
    }

    final bitCount = readUint32(sizeOffset);
    final compressedByteCount = readUint32(sizeOffset + 4);
    final expectedByteCount = readUint32(sizeOffset + 8);
    final compressedOffset = sizeOffset + 12;
    if (frequencyTotal != expectedByteCount ||
        compressedByteCount != bytes.length - compressedOffset ||
        bitCount > compressedByteCount * 8) {
      return null;
    }

    while (heap.length > 1) {
      final left = heap.removeFirst();
      final right = heap.removeFirst();
      heap.add(_HuffmanNode.branch(left, right));
    }
    final root = heap.removeFirst();
    var current = root;
    final output = BytesBuilder(copy: false);
    for (var bitIndex = 0; bitIndex < bitCount; bitIndex += 1) {
      final byte = bytes[compressedOffset + bitIndex ~/ 8];
      final bit = (byte >> (7 - bitIndex % 8)) & 1;
      final next = bit == 0 ? current.left : current.right;
      if (next == null) return null;
      current = next;
      if (current.isLeaf) {
        output.addByte(current.character!);
        if (output.length > expectedByteCount) return null;
        current = root;
      }
    }
    if (!identical(current, root) || output.length != expectedByteCount) {
      return null;
    }
    return ascii.decode(output.takeBytes(), allowInvalid: false);
  }

  static int? _normalizeItemId(Object? value) {
    final int? id;
    if (value is int) {
      id = value;
    } else if (value is num && value.isFinite && value == value.truncate()) {
      id = value.toInt();
    } else if (value is String && RegExp(r'^\d+$').hasMatch(value.trim())) {
      id = int.tryParse(value.trim());
    } else {
      id = null;
    }
    if (id == null || id <= 0 || id > _maximumItemId) return null;
    return id;
  }

  static List<int> _normalizedIds(Iterable<Object?> itemIds) {
    final ids = <int>[];
    final seen = <int>{};
    for (final rawId in itemIds) {
      final id = _normalizeItemId(rawId);
      if (id != null && seen.add(id)) ids.add(id);
    }
    return ids;
  }
}

final class _BaseQuoteFetch {
  const _BaseQuoteFetch.success(this.quote) : unavailable = false;
  const _BaseQuoteFetch.unavailable() : quote = null, unavailable = true;
  const _BaseQuoteFetch.failed() : quote = null, unavailable = false;

  final GatheringMarketQuote? quote;
  final bool unavailable;
}

final class _HuffmanNode {
  const _HuffmanNode._({
    required this.frequency,
    this.character,
    this.left,
    this.right,
  });

  factory _HuffmanNode.leaf(int character, int frequency) =>
      _HuffmanNode._(frequency: frequency, character: character);

  factory _HuffmanNode.branch(_HuffmanNode left, _HuffmanNode right) =>
      _HuffmanNode._(
        frequency: left.frequency + right.frequency,
        left: left,
        right: right,
      );

  final int frequency;
  final int? character;
  final _HuffmanNode? left;
  final _HuffmanNode? right;

  bool get isLeaf => left == null && right == null;
}

/// Minimal binary heap with the same equal-frequency behavior as Java's
/// `PriorityQueue`: equal values do not sift upward; sift-down prefers the
/// left child when both children compare equally.
final class _FrequencyHeap {
  final List<_HuffmanNode> _nodes = <_HuffmanNode>[];

  int get length => _nodes.length;

  void add(_HuffmanNode node) {
    var index = _nodes.length;
    _nodes.add(node);
    while (index > 0) {
      final parentIndex = (index - 1) >> 1;
      final parent = _nodes[parentIndex];
      if (node.frequency >= parent.frequency) break;
      _nodes[index] = parent;
      index = parentIndex;
    }
    _nodes[index] = node;
  }

  _HuffmanNode removeFirst() {
    final result = _nodes.first;
    final last = _nodes.removeLast();
    if (_nodes.isEmpty) return result;
    var index = 0;
    final half = _nodes.length >> 1;
    while (index < half) {
      var childIndex = (index << 1) + 1;
      var child = _nodes[childIndex];
      final rightIndex = childIndex + 1;
      if (rightIndex < _nodes.length &&
          child.frequency > _nodes[rightIndex].frequency) {
        childIndex = rightIndex;
        child = _nodes[childIndex];
      }
      if (last.frequency <= child.frequency) break;
      _nodes[index] = child;
      index = childIndex;
    }
    _nodes[index] = last;
    return result;
  }
}
