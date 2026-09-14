import 'dart:convert';
import 'dart:typed_data';

import '../../domain/opportunities/opportunity_market_models.dart';

/// The official non-enhanced material quote format, verified 2026-09-08.
OpportunityMarketItem decodeOpportunityQuote({
  required Uint8List bytes,
  required String itemId,
  required DateTime fetchedAt,
}) {
  final payload = _resultMessage(bytes);
  for (final row in payload.split('|').where((row) => row.isNotEmpty)) {
    final fields = row.split('-');
    if (fields.length < 5 || fields[0] != itemId) continue;
    if (fields[1] != '0' || fields[2] != '0') continue;
    final price = _number(fields[3]);
    if (price <= 0) throw const FormatException('No usable market price');
    final stock = _number(fields[4]);
    final trades = fields.length > 5 ? _number(fields[5]) : null;
    final sold = fields.length > 9 ? _number(fields[9]) : null;
    return OpportunityMarketItem(
      itemId: itemId,
      basePrice: price,
      stock: stock,
      totalTrades: trades,
      lastSoldAt: sold == null || sold == 0
          ? null
          : DateTime.fromMillisecondsSinceEpoch(sold * 1000, isUtc: true),
      quoteFetchedAt: fetchedAt.toUtc(),
    );
  }
  throw const FormatException(
    'Requested material missing from market response',
  );
}

OpportunityMarketItem decodeOpportunityOrderBook({
  required Uint8List bytes,
  required String itemId,
  required DateTime fetchedAt,
}) {
  if (bytes.isEmpty || bytes.length > 1024 * 1024) {
    throw const FormatException('Invalid order book size');
  }
  // A binary packet starts with its little-endian byte length. A 123-byte
  // packet therefore also starts with `{`; the first byte cannot identify JSON.
  // Validate the complete binary frame before considering a JSON envelope.
  final text = decodePearlAbyssOrderBook(bytes) ?? _resultMessage(bytes);
  if (text.isEmpty) {
    throw const FormatException('Order book could not be decoded');
  }
  final asks = <OpportunityMarketLevel>[];
  final bids = <OpportunityMarketLevel>[];
  final prices = <int>{};
  for (final row in text.split('|').where((row) => row.isNotEmpty)) {
    final fields = row.split('-');
    if (fields.length != 3) throw const FormatException('Invalid price level');
    final price = _number(fields[0]);
    final sellers = _number(fields[1]);
    final buyers = _number(fields[2]);
    if (price <= 0 || !prices.add(price)) {
      throw const FormatException('Invalid or duplicate price level');
    }
    if (sellers > 0) {
      asks.add(OpportunityMarketLevel(price: price, quantity: sellers));
    }
    if (buyers > 0) {
      bids.add(OpportunityMarketLevel(price: price, quantity: buyers));
    }
  }
  if (prices.isEmpty) throw const FormatException('No price levels');
  asks.sort((a, b) => a.price.compareTo(b.price));
  bids.sort((a, b) => b.price.compareTo(a.price));
  return OpportunityMarketItem(
    itemId: itemId,
    asks: asks,
    bids: bids,
    bookFetchedAt: fetchedAt.toUtc(),
  );
}

String _resultMessage(Uint8List bytes) {
  if (bytes.length > 1024 * 1024) {
    throw const FormatException('Response too large');
  }
  final root = jsonDecode(utf8.decode(bytes));
  if (root is! Map || root['resultCode'] != 0 || root['resultMsg'] is! String) {
    throw const FormatException('Market returned an unsuccessful response');
  }
  return root['resultMsg'] as String;
}

int _number(String value) {
  if (!RegExp(r'^\d+$').hasMatch(value)) {
    throw const FormatException('Invalid market number');
  }
  final result = int.tryParse(value);
  if (result == null || result < 0) {
    throw const FormatException('Invalid market number');
  }
  return result;
}

/// Frequency-only heap ties match the server decoder. Do not add a tie-breaker.
String? decodePearlAbyssOrderBook(Uint8List bytes) {
  if (bytes.length < 24 || bytes.length > 1024 * 1024) return null;

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
  final frequencies = <int, int>{};
  var frequencyTotal = 0;
  for (var index = 0; index < symbolCount; index += 1) {
    final offset = 12 + index * 8;
    final frequency = readUint32(offset);
    final character = bytes[offset + 4];
    if (frequency == 0 ||
        frequencies.containsKey(character) ||
        !(character == 45 ||
            character == 124 ||
            (character >= 48 && character <= 57))) {
      return null;
    }
    frequencies[character] = frequency;
    frequencyTotal += frequency;
    heap.add(_HuffmanNode.leaf(character, frequency));
  }

  final bitCount = readUint32(sizeOffset);
  final compressedByteCount = readUint32(sizeOffset + 4);
  final expectedByteCount = readUint32(sizeOffset + 8);
  final compressedOffset = sizeOffset + 12;
  if (expectedByteCount > 1024 * 1024 ||
      frequencyTotal != expectedByteCount ||
      compressedByteCount != bytes.length - compressedOffset ||
      compressedByteCount != (bitCount + 7) ~/ 8 ||
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
      final remaining = frequencies[current.character!]! - 1;
      if (remaining < 0) return null;
      frequencies[current.character!] = remaining;
      if (output.length > expectedByteCount) return null;
      current = root;
    }
  }
  if (!identical(current, root) ||
      output.length != expectedByteCount ||
      frequencies.values.any((remaining) => remaining != 0)) {
    return null;
  }
  return ascii.decode(output.takeBytes(), allowInvalid: false);
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
