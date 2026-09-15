import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart';

import '../assets.dart';

final class LootScanRow {
  const LootScanRow({
    this.itemId,
    required this.name,
    this.quantity,
    this.isApproximate = false,
    this.iconAsset,
    required this.needsReview,
    this.note,
  });

  final int? itemId;
  final String name;
  final int? quantity;

  /// The game abbreviates this amount; hidden digits are not recovered.
  final bool isApproximate;
  final String? iconAsset;
  final bool needsReview;
  final String? note;
}

final class LootScanResult {
  const LootScanResult({required this.rows, this.warnings = const []});

  final List<LootScanRow> rows;
  final List<String> warnings;
}

/// Reads the existing local inventory recognizer, without persisting images.
/// This adapter retains unknown slots so the review UI can correct them.
final class LootRecognizer {
  LootRecognizer({this.timeout = const Duration(seconds: 95), this.helperPath});

  static const maximumScreenshotBytes = 16 * 1024 * 1024;
  static const _maximumResponseBytes = 8 * 1024 * 1024;
  static const _maximumQuantity = 999999999999;
  final Duration timeout;
  final String? helperPath;
  Process? _process;
  bool _busy = false;
  bool _disposed = false;
  Map<String, List<_KnownItem>>? _itemsByArtwork;

  Future<LootScanResult> scanPath(String path) async {
    if (_disposed) {
      throw const FormatException('Screenshot recognition is closed.');
    }
    final file = File(path);
    final stat = await file.stat();
    if (stat.type != FileSystemEntityType.file || stat.size <= 0) {
      throw const FormatException('That screenshot could not be found.');
    }
    if (stat.size > maximumScreenshotBytes) {
      throw const FormatException('Choose a screenshot smaller than 16 MB.');
    }
    return scanBytes(
      await file.readAsBytes(),
      fileName: path.split(RegExp(r'[/\\]')).last,
    );
  }

  Future<LootScanResult> scanBytes(
    Uint8List bytes, {
    String fileName = 'screenshot.png',
  }) async {
    if (_disposed) {
      throw const FormatException('Screenshot recognition is closed.');
    }
    if (_busy) {
      throw const FormatException('A screenshot is already being read.');
    }
    if (bytes.isEmpty || bytes.length > maximumScreenshotBytes) {
      throw const FormatException('Choose a screenshot smaller than 16 MB.');
    }
    final mime = _imageMime(bytes);
    if (mime == null) {
      throw const FormatException('Choose a PNG, JPEG, or BMP screenshot.');
    }
    _busy = true;
    Process? process;
    try {
      final helper = await _resolveHelper();
      final catalog = await _catalog(helper);
      _ensureOpen();
      process = await Process.start(
        helper.path,
        const [],
        workingDirectory: helper.parent.path,
        runInShell: false,
        mode: ProcessStartMode.normal,
      );
      _process = process;
      _ensureOpen();
      final child = process;
      final request = jsonEncode({
        'fileName': fileName.split(RegExp(r'[/\\]')).last,
        'mimeType': mime,
        'dataBase64': base64Encode(bytes),
      });
      // Subscribe to both pipes immediately so neither can block the helper.
      final output = await Future.wait<Object>([
        _readBounded(child.stdout, _maximumResponseBytes),
        _readBounded(child.stderr, 8192),
        child.exitCode,
        (() async {
          child.stdin.write(request);
          await child.stdin.flush();
          await child.stdin.close();
          return true;
        })(),
      ], eagerError: true).timeout(timeout);
      _ensureOpen();
      if (output[2] != 0) {
        final message = (output[1] as String).trim();
        throw FormatException(
          message.isEmpty
              ? 'Screenshot recognition failed. Try a clearer inventory crop.'
              : message.substring(0, message.length.clamp(0, 512)),
        );
      }
      final raw = jsonDecode(output[0] as String);
      if (raw is! Map<String, dynamic> || raw['slots'] is! List) {
        throw const FormatException(
          'Screenshot recognition returned an invalid result.',
        );
      }
      return _convert(raw, catalog);
    } on TimeoutException {
      throw TimeoutException(
        'Reading the screenshot took too long. Try a smaller inventory crop.',
      );
    } on ProcessException catch (error) {
      throw FormatException(
        'The local recognizer could not start: ${error.message}',
      );
    } finally {
      process?.kill();
      if (identical(_process, process)) _process = null;
      _busy = false;
    }
  }

  void dispose() {
    _disposed = true;
    _process?.kill();
    _process = null;
    _itemsByArtwork = null;
  }

  void _ensureOpen() {
    if (_disposed) {
      throw const FormatException('Screenshot recognition is closed.');
    }
  }

  Future<File> _resolveHelper() async {
    final explicit =
        helperPath ?? Platform.environment['BDO_GATHERING_OCR_HELPER'];
    final candidates = [
      if (explicit != null && explicit.trim().isNotEmpty) explicit.trim(),
      '${File(Platform.resolvedExecutable).parent.path}/storage_ocr/BlackSpiritStorageOcr.exe',
      '${Directory.current.path}/build/windows/x64/runner/Release/storage_ocr/BlackSpiritStorageOcr.exe',
    ];
    for (final path in candidates) {
      final file = File(path);
      if (await file.exists()) return file;
    }
    throw const FormatException(
      'The screenshot reader is not included in this build. Manual entry still works.',
    );
  }

  Future<Map<String, List<_KnownItem>>> _catalog(File helper) async {
    final existing = _itemsByArtwork;
    if (existing != null) return existing;
    final file = File('${helper.parent.path}/Assets/RecipeBook/recipes.json');
    final size = await file.length();
    if (size <= 0 || size > 20 * 1024 * 1024) {
      throw const FormatException(
        'The local recognizer item catalog is invalid.',
      );
    }
    final data = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    final items = data['items'] as Map<String, dynamic>;
    final focused =
        jsonDecode(
              await rootBundle.loadString(
                gatheringBundleAsset('assets/data/loot_catalog.json'),
              ),
            )
            as Map<String, dynamic>;
    final result = _indexCatalog(items, focused);
    _ensureOpen();
    _itemsByArtwork = result;
    return result;
  }

  static Map<String, List<_KnownItem>> _indexCatalog(
    Map<String, dynamic> items,
    Map<String, dynamic> focused,
  ) {
    final assetById = <int, String>{
      for (final row in focused['items'] as List)
        if (row is Map && row['id'] is int && row['icon'] is String)
          row['id'] as int: row['icon'] as String,
    };
    final result = <String, List<_KnownItem>>{};
    for (final entry in items.entries) {
      if (entry.value is! Map) continue;
      final item = entry.value as Map;
      final id = int.tryParse(entry.key);
      final name = item['name'];
      final icon = item['icon'];
      if (id == null || name is! String || icon is! String) continue;
      final known = _KnownItem(
        id,
        name,
        _integer(item['grade']),
        assetById[id],
      );
      result.putIfAbsent(_artworkKey(icon), () => []).add(known);
    }
    return result;
  }

  /// Uses the real response contract without starting a process in unit tests.
  @visibleForTesting
  static LootScanResult parseNativeResponseForTesting(
    Map<String, dynamic> raw, {
    required Map<String, dynamic> catalogItems,
    Map<String, dynamic> lootCatalog = const {'items': []},
  }) => _convert(raw, _indexCatalog(catalogItems, lootCatalog));

  static LootScanResult _convert(
    Map<String, dynamic> raw,
    Map<String, List<_KnownItem>> catalog,
  ) {
    final warnings = <String>[
      'Review item names and quantities before adding them. Inventory screenshots are snapshots, not new pickups.',
      if (raw['warnings'] is List)
        ...(raw['warnings'] as List).whereType<String>(),
    ];
    final slots = raw['slots'] as List;
    if (slots.length > 192) {
      throw const FormatException(
        'The screenshot contains too many inventory slots. Crop to one inventory panel.',
      );
    }
    final rows = <LootScanRow>[];
    for (var index = 0; index < slots.length; index++) {
      final value = slots[index];
      if (value is! Map) {
        rows.add(
          LootScanRow(
            name: 'Unknown item ${index + 1}',
            needsReview: true,
            note:
                'This detected slot could not be read. Choose its item and quantity.',
          ),
        );
        continue;
      }
      final slot = Map<String, dynamic>.from(value);
      final candidates = <_ArtworkMatch>[];
      final nativeCandidates = slot['iconCandidates'];
      if (nativeCandidates is List) {
        for (final candidate in nativeCandidates) {
          if (candidate is! Map || candidate['icon'] is! String) continue;
          candidates.add(
            _ArtworkMatch(
              _artworkKey(candidate['icon'] as String),
              _number(candidate['score']),
              candidate['materialEligible'] != false,
            ),
          );
        }
      }
      candidates.sort((a, b) => b.score.compareTo(a.score));
      final best = candidates.isEmpty ? null : candidates.first;
      final alternatives = best == null
          ? <_KnownItem>[]
          : List<_KnownItem>.from(catalog[best.key] ?? const []);
      final grade = _integer(slot['borderGrade']);
      if (grade != null && _number(slot['borderGradeConfidence']) >= .80) {
        final matchingGrade = alternatives
            .where((item) => item.grade == grade)
            .toList();
        if (matchingGrade.isNotEmpty) {
          alternatives
            ..clear()
            ..addAll(matchingGrade);
        }
      }
      // Identical artwork can legitimately represent distinct game items.
      // Never manufacture a definite name by arbitrarily selecting the first.
      final uniqueNames = {for (final item in alternatives) item.name: item};
      final next = candidates
          .where((candidate) => candidate.key != best?.key)
          .firstOrNull;
      final gap = (best?.score ?? 0) - (next?.score ?? 0);
      final credible = best != null && best.score >= .70 && gap >= .025;
      final selected = credible && uniqueNames.length == 1
          ? uniqueNames.values.single
          : null;
      final confident = selected != null && best!.score >= .82 && gap >= .08;
      final quantityValue = _integer(slot['quantityValue']);
      final usableQuantity =
          quantityValue != null &&
          quantityValue > 0 &&
          quantityValue <= _maximumQuantity &&
          _number(slot['quantityConfidence']) >= .60 &&
          slot['quantityAssumedOne'] != true;
      final approximate = usableQuantity && slot['quantityApproximate'] == true;
      final notes = <String>[];
      if (selected == null) {
        final suggestions = <String>{
          for (final candidate in candidates.take(4))
            if (candidate.score >= .60)
              for (final item in catalog[candidate.key] ?? <_KnownItem>[])
                item.name,
        }.take(5).toList();
        notes.add(
          suggestions.isEmpty
              ? 'Item not identified. Choose it manually.'
              : 'Possible items: ${suggestions.join(', ')}. Choose the correct item.',
        );
      } else if (!confident) {
        notes.add('Suggested item; please confirm the icon.');
      }
      if (approximate) {
        final text = slot['quantityText']?.toString().trim() ?? '';
        notes.add(
          'At least $quantityValue; game displays $text, hidden digits unknown.',
        );
      } else if (!usableQuantity) {
        final text = slot['quantityText']?.toString().trim() ?? '';
        notes.add(
          text.isEmpty
              ? 'Quantity was not read reliably. Enter the amount.'
              : 'Quantity text: $text. Enter the exact amount.',
        );
      }
      if (best?.materialEligible == false) {
        notes.add(
          'This may be equipment or another non-loot item; remove it if unrelated.',
        );
      }
      final r = _integer(slot['row']);
      final c = _integer(slot['column']);
      final position = r != null && c != null
          ? 'slot ${r + 1}, ${c + 1}'
          : 'slot ${index + 1}';
      rows.add(
        LootScanRow(
          itemId: selected?.id,
          name: selected?.name ?? 'Unknown item ($position)',
          quantity: usableQuantity ? quantityValue : null,
          isApproximate: approximate,
          iconAsset: selected?.asset,
          needsReview:
              !confident ||
              !usableQuantity ||
              approximate ||
              best.materialEligible == false,
          note: notes.isEmpty ? null : notes.join(' '),
        ),
      );
    }
    if (rows.isEmpty) {
      warnings.add(
        'No inventory items were found. Try a clear crop with item slots and numbers visible.',
      );
    }
    return LootScanResult(
      rows: List.unmodifiable(rows),
      warnings: List.unmodifiable(warnings.toSet()),
    );
  }

  static Future<String> _readBounded(
    Stream<List<int>> stream,
    int limit,
  ) async {
    final builder = BytesBuilder(copy: false);
    await for (final bytes in stream) {
      if (builder.length + bytes.length > limit) {
        throw const FormatException(
          'The screenshot reader returned too much data.',
        );
      }
      builder.add(bytes);
    }
    return utf8.decode(builder.takeBytes(), allowMalformed: true);
  }

  static String? _imageMime(Uint8List bytes) {
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4e &&
        bytes[3] == 0x47 &&
        bytes[4] == 0x0d &&
        bytes[5] == 0x0a &&
        bytes[6] == 0x1a &&
        bytes[7] == 0x0a) {
      return 'image/png';
    }
    if (bytes.length >= 3 &&
        bytes[0] == 0xff &&
        bytes[1] == 0xd8 &&
        bytes[2] == 0xff) {
      return 'image/jpeg';
    }
    if (bytes.length >= 2 && bytes[0] == 0x42 && bytes[1] == 0x4d) {
      return 'image/bmp';
    }
    return null;
  }

  static String _artworkKey(String value) =>
      value.replaceAll('\\', '/').toLowerCase();
  static double _number(Object? value) =>
      value is num && value.isFinite ? value.toDouble() : 0;
  static int? _integer(Object? value) {
    if (value is int) return value;
    if (value is num && value.isFinite && value == value.roundToDouble()) {
      return value.toInt();
    }
    return null;
  }
}

final class _KnownItem {
  const _KnownItem(this.id, this.name, this.grade, this.asset);
  final int id;
  final String name;
  final int? grade;
  final String? asset;
}

final class _ArtworkMatch {
  const _ArtworkMatch(this.key, this.score, this.materialEligible);
  final String key;
  final double score;
  final bool materialEligible;
}
