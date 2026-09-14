import 'dart:convert';
import 'dart:typed_data';

import 'package:bdo_craft_planner_flutter/data/opportunities/opportunity_market_codec.dart';
import 'package:flutter_test/flutter_test.dart';

// Actual EU response bodies from the single normal 2026-09-10 catalog read.
// All have length123: their binary length header starts with JSON's `{` byte.
// Numeric reference rows were independently inspected from strict Huffman
// output; original bodies are retained to prevent a generated-fixture blind spot.
const _fixtures = <String, ({String bytes, String levels})>{
  '9276': (
    bytes:
        'ewAAAAAAAAAKAAAACAAAAC0AAAATAAAAMAAAAAQAAAAxAAAABAAAADIAAAAEAAAAMwAAAAIAAAA0AAAAAQAAADUAAAACAAAANwAAAAMAAAA5AAAABAAAAHwAAACTAAAAEwAAADMAAAC6gZq9+49PR4zWVNvmahPf8Zkg',
    levels: '31500-0-149372|27200-0-3001|30900-0-1000|29400-0-0|',
  ),
  '7904': (
    bytes:
        'ewAAAAAAAAAKAAAACAAAAC0AAAAQAAAAMAAAAAUAAAAxAAAAAwAAADIAAAACAAAAMwAAAAQAAAA1AAAAAgAAADYAAAADAAAANwAAAAMAAAA4AAAABAAAAHwAAACXAAAAEwAAADIAAABTfzL/pNHlylZ0mbxQ83OlF+Z0',
    levels: '16200-0-5000|18700-5335-0|18800-17262-0|17500-0-0|',
  ),
  '8523': (
    bytes:
        'ewAAAAAAAAAKAAAACgAAAC0AAAAQAAAAMAAAAAYAAAAyAAAABgAAADMAAAABAAAANAAAAAIAAAA1AAAAAwAAADYAAAACAAAANwAAAAEAAAA5AAAABQAAAHwAAACWAAAAEwAAADQAAAB6eZRa7cTxnblPIduL4p25V5Ds',
    levels: '30500-0-769|32500-3-0|32700-2-0|32600-6-0|32400-2-0|',
  ),
  '9269': (
    bytes:
        'ewAAAAAAAAALAAAABgAAAC0AAAAJAAAAMAAAAAEAAAAxAAAAAQAAADMAAAABAAAANAAAAAEAAAA1AAAAAQAAADYAAAABAAAANwAAAAEAAAA4AAAAAwAAADkAAAADAAAAfAAAAFIAAAALAAAAHAAAAJfdHiNMNtVzJu5A',
    levels: '980-0-504|1060-73-0|990-0-0|',
  ),
  '1189': (
    bytes:
        'ewAAAAAAAAAKAAAACAAAAC0AAAAZAAAAMAAAAAIAAAAxAAAABQAAADIAAAADAAAAMwAAAAIAAAA0AAAAAQAAADUAAAADAAAANgAAAAMAAAA4AAAABAAAAHwAAACVAAAAEwAAADgAAACPoZp+uuXCRm7Fx/jNJf1wZuxY',
    levels: '328000-0-62854|306000-0-1000|322000-0-600|284000-0-1000|',
  ),
  '12144': (
    bytes:
        'ewAAAAAAAAAKAAAACAAAAC0AAAAiAAAAMAAAAAIAAAAxAAAAAgAAADIAAAACAAAAMwAAAAIAAAA0AAAABwAAADUAAAABAAAANwAAAAEAAAA4AAAABAAAAHwAAACRAAAAEwAAAD8AAAAn/VOgN7F5/qnGIf6oTER/qhsA',
    levels: '5500000000-0-8423|5350000000-0-7|5400000000-0-1|5150000000-0-2|',
  ),
  '4703': (
    bytes:
        'ewAAAAAAAAAKAAAACgAAAC0AAAAaAAAAMAAAAAEAAAAxAAAAAgAAADMAAAACAAAANQAAAAEAAAA2AAAAAgAAADcAAAAFAAAAOAAAAAQAAAA5AAAABQAAAHwAAACVAAAAEwAAADoAAACS4+HbS49u2UHy7aB81j2yB7do',
    levels: '885000-1-0|905000-3-0|890000-70-0|900000-796-0|880000-3-0|',
  ),
  '778': (
    bytes:
        'ewAAAAAAAAAKAAAACAAAAC0AAAAWAAAAMAAAAAkAAAAxAAAAAgAAADIAAAACAAAAMwAAAAMAAAA0AAAAAwAAADUAAAABAAAANgAAAAEAAAA4AAAABAAAAHwAAACUAAAAEwAAADcAAADRhV85//s7uFWCd3gq4Tv4VYyQ',
    levels: '151000-0-62448|131000-0-500|132000-0-1000|141000-0-510|',
  ),
};

void main() {
  final checkedAt = DateTime.utc(2026, 9, 10, 8);
  for (final entry in _fixtures.entries) {
    test('123-byte binary book ${entry.key} is not mistaken for JSON', () {
      final bytes = base64Decode(entry.value.bytes);
      expect(bytes.length, 123);
      expect(bytes.first, '{'.codeUnitAt(0));
      expect(decodePearlAbyssOrderBook(bytes), entry.value.levels);
      final book = decodeOpportunityOrderBook(
        bytes: bytes,
        itemId: entry.key,
        fetchedAt: checkedAt,
      );
      final rows = entry.value.levels
          .split('|')
          .where((row) => row.isNotEmpty)
          .map((row) => row.split('-').map(int.parse).toList())
          .toList();
      final asks = rows.where((row) => row[1] > 0).toList()
        ..sort((a, b) => a[0].compareTo(b[0]));
      final bids = rows.where((row) => row[2] > 0).toList()
        ..sort((a, b) => b[0].compareTo(a[0]));
      expect(
        book.asks!.map((level) => (level.price, level.quantity)).toList(),
        asks.map((row) => (row[0], row[1])).toList(),
      );
      expect(
        book.bids!.map((level) => (level.price, level.quantity)).toList(),
        bids.map((row) => (row[0], row[2])).toList(),
      );
      expect(book.bookFetchedAt, checkedAt);
      expect(book.quoteFetchedAt, isNull);
      expect(book.basePrice, isNull);
      expect(book.stock, isNull);
    });
  }

  test('valid JSON envelope, including leading whitespace, still decodes', () {
    final book = decodeOpportunityOrderBook(
      bytes: Uint8List.fromList(
        utf8.encode(' \n {"resultCode":0,"resultMsg":"100-2-0|90-0-7"}'),
      ),
      itemId: '1',
      fetchedAt: checkedAt,
    );
    expect(book.asks!.single.price, 100);
    expect(book.asks!.single.quantity, 2);
    expect(book.bids!.single.quantity, 7);
  });

  test(
    'corrupt binary header is rejected rather than accepted as empty JSON',
    () {
      final bytes = base64Decode(_fixtures['9276']!.bytes)..[4] = 1;
      expect(
        () => decodeOpportunityOrderBook(
          bytes: bytes,
          itemId: '9276',
          fetchedAt: checkedAt,
        ),
        throwsFormatException,
      );
    },
  );

  test(
    'unsuccessful JSON response remains unknown, not an empty order book',
    () {
      expect(
        () => decodeOpportunityOrderBook(
          bytes: Uint8List.fromList(
            utf8.encode('{"resultCode":1,"resultMsg":""}'),
          ),
          itemId: '1',
          fetchedAt: checkedAt,
        ),
        throwsFormatException,
      );
    },
  );
  test('provider zero sentinel has no price and is not a free item', () {
    // Exact detailed response for the eight absent bulk rows, verified once
    // on 2026-09-10. This is not a numeric price or known empty stock.
    expect(
      () => decodeOpportunityQuote(
        bytes: Uint8List.fromList(
          utf8.encode('{"resultCode":0,"resultMsg":"0"}'),
        ),
        itemId: '15215',
        fetchedAt: checkedAt,
      ),
      throwsFormatException,
    );
  });
}
