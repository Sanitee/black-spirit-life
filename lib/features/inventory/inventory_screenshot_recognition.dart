import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as image;

import '../../app/window/native_still_image_ocr_service.dart';
import '../../domain/models/catalog_models.dart';
import '../../domain/models/craft_mode.dart';

final class InventoryScreenshotRect {
  const InventoryScreenshotRect({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  final int left;
  final int top;
  final int width;
  final int height;
}

final class InventoryItemMatch {
  const InventoryItemMatch({
    required this.name,
    required this.confidence,
    required this.sharedArtwork,
  });

  final String name;
  final double confidence;
  final bool sharedArtwork;
}

final class InventoryScreenshotRow {
  const InventoryScreenshotRow({
    required this.slot,
    required this.crop,
    required this.quantityText,
    required this.quantity,
    required this.matches,
    required this.previewPng,
  });

  final int slot;
  final InventoryScreenshotRect crop;
  final String quantityText;
  final int quantity;
  final List<InventoryItemMatch> matches;
  final Uint8List previewPng;

  bool get needsReview =>
      matches.isEmpty ||
      matches.first.sharedArtwork ||
      matches.first.confidence < .82;
}

final class InventoryScreenshotDraft {
  const InventoryScreenshotDraft({
    required this.suggestedLocationName,
    required this.sourceWidth,
    required this.sourceHeight,
    required this.rows,
  });

  final String? suggestedLocationName;
  final int sourceWidth;
  final int sourceHeight;
  final List<InventoryScreenshotRow> rows;
}

final class InventoryScreenshotAnalysis {
  const InventoryScreenshotAnalysis({
    required this.screenshotPng,
    required this.draft,
  });

  final Uint8List screenshotPng;
  final InventoryScreenshotDraft draft;
}

/// Screenshot recognizer with an explicit review boundary.
///
/// OCR locates the visible amount labels and derives the item-cell grid. Icon
/// matching only suggests candidates; exact shared artwork and weak matches
/// remain visibly unresolved until the user chooses an item.
final class InventoryScreenshotRecognizer {
  InventoryScreenshotRecognizer._(this._artworks);

  factory InventoryScreenshotRecognizer.fromCatalog(CatalogSnapshot catalog) {
    final namesByArtwork = <String, Set<String>>{};
    for (final mode in CraftMode.values) {
      final modeCatalog = catalog.forMode(mode);
      for (final name in modeCatalog.items.keys) {
        final dataUri = _foldedValue(modeCatalog.iconDataUris, name);
        if (dataUri == null || !dataUri.startsWith('data:image/')) continue;
        namesByArtwork.putIfAbsent(dataUri, () => <String>{}).add(name);
      }
    }
    final artworks = <_InventoryArtwork>[];
    for (final entry in namesByArtwork.entries) {
      try {
        final decoded = image.decodeImage(
          UriData.parse(entry.key).contentAsBytes(),
        );
        if (decoded == null || decoded.width < 2 || decoded.height < 2) {
          continue;
        }
        final names = entry.value.toList()..sort(_compareNames);
        artworks.add(
          _InventoryArtwork(
            names: List<String>.unmodifiable(names),
            fingerprint: _fingerprint(decoded, transparentBackground: true),
          ),
        );
      } on FormatException {
        // A malformed optional icon must not block inventory review.
      }
    }
    return InventoryScreenshotRecognizer._(
      List<_InventoryArtwork>.unmodifiable(artworks),
    );
  }

  final List<_InventoryArtwork> _artworks;

  InventoryScreenshotDraft recognize({
    required Uint8List screenshotPng,
    required StillImageOcrResult ocr,
  }) {
    final screenshot = image.decodeImage(screenshotPng);
    if (screenshot == null) {
      throw const FormatException('The screenshot image could not be decoded.');
    }
    final normalizedWords = _normalizedOcrWords(ocr.lines);
    final quantityWords = <_QuantityWord>[];
    for (final line in _mergeQuantityFragments(normalizedWords)) {
      final quantity = parseVisibleInventoryAmount(line.text);
      if (quantity == null || line.text.trimLeft().startsWith('+')) continue;
      if (line.top < screenshot.height * .08 ||
          line.width <= 0 ||
          line.height <= 0) {
        continue;
      }
      quantityWords.add(_QuantityWord(line: line, quantity: quantity));
    }
    final rows = _quantityRows(quantityWords);
    if (rows.isEmpty) {
      return InventoryScreenshotDraft(
        suggestedLocationName: _suggestLocationName(
          normalizedWords,
          screenshot.height,
        ),
        sourceWidth: screenshot.width,
        sourceHeight: screenshot.height,
        rows: const <InventoryScreenshotRow>[],
      );
    }
    final cellSize = _estimatedCellSize(rows).clamp(34.0, 96.0);
    final ordered = rows.expand((row) => row).toList()
      ..sort((left, right) {
        final vertical = left.line.top.compareTo(right.line.top);
        return vertical != 0
            ? vertical
            : left.line.left.compareTo(right.line.left);
      });
    final results = <InventoryScreenshotRow>[];
    for (var index = 0; index < ordered.length; index += 1) {
      final word = ordered[index];
      // BDO right-aligns the amount at the bottom of each slot. Centering the
      // crop on a short label such as `1` therefore shifts almost a full icon
      // to the right and can include the neighbouring item. Anchor the crop
      // to the amount's right edge instead, which stays stable for 1, 54.260,
      // and abbreviated K/M values alike.
      final right = word.line.left + word.line.width + cellSize * .08;
      final bottom = word.line.top + word.line.height + cellSize * .08;
      final left = (right - cellSize).round().clamp(
        0,
        screenshot.width - 1,
      );
      final top = (bottom - cellSize).round().clamp(0, screenshot.height - 1);
      final width = math.min(cellSize.round(), screenshot.width - left);
      final height = math.min(cellSize.round(), screenshot.height - top);
      if (width < 20 || height < 20) continue;
      final crop = image.copyCrop(
        screenshot,
        x: left,
        y: top,
        width: width,
        height: height,
      );
      results.add(
        InventoryScreenshotRow(
          slot: index + 1,
          crop: InventoryScreenshotRect(
            left: left,
            top: top,
            width: width,
            height: height,
          ),
          quantityText: word.line.text,
          quantity: word.quantity,
          matches: _matchesFor(crop),
          previewPng: Uint8List.fromList(image.encodePng(crop)),
        ),
      );
    }
    return InventoryScreenshotDraft(
      suggestedLocationName: _suggestLocationName(
        normalizedWords,
        screenshot.height,
      ),
      sourceWidth: screenshot.width,
      sourceHeight: screenshot.height,
      rows: List<InventoryScreenshotRow>.unmodifiable(results),
    );
  }

  List<InventoryItemMatch> _matchesFor(image.Image crop) {
    if (_artworks.isEmpty) return const <InventoryItemMatch>[];
    final fingerprint = _fingerprint(crop, transparentBackground: false);
    final ranked = <({double distance, _InventoryArtwork artwork})>[
      for (final artwork in _artworks)
        (
          distance: _distance(fingerprint, artwork.fingerprint),
          artwork: artwork,
        ),
    ]..sort((left, right) => left.distance.compareTo(right.distance));
    final result = <InventoryItemMatch>[];
    for (final rankedArtwork in ranked.take(5)) {
      final confidence = (1 - rankedArtwork.distance * 3.2).clamp(0.0, 1.0);
      final shared = rankedArtwork.artwork.names.length > 1;
      for (final name in rankedArtwork.artwork.names) {
        result.add(
          InventoryItemMatch(
            name: name,
            confidence: confidence,
            sharedArtwork: shared,
          ),
        );
        if (result.length >= 8) return List.unmodifiable(result);
      }
    }
    return List<InventoryItemMatch>.unmodifiable(result);
  }
}

/// Converts the abbreviated value shown by BDO into the smallest exact amount
/// that the label guarantees. `139.9K` therefore becomes `139900` and `1.8M`
/// becomes `1800000`.
int? parseVisibleInventoryAmount(String source) {
  var value = _normalizedInventoryAmountText(source);
  if (value == null || !RegExp(r'\d').hasMatch(value)) return null;
  var multiplier = 1;
  if (value.endsWith('K')) {
    multiplier = 1000;
    value = value.substring(0, value.length - 1);
  } else if (value.endsWith('M')) {
    multiplier = 1000000;
    value = value.substring(0, value.length - 1);
  } else if (value.endsWith('B')) {
    multiplier = 1000000000;
    value = value.substring(0, value.length - 1);
  }
  if (value.isEmpty || !RegExp(r'^\d[\d.,]*$').hasMatch(value)) return null;
  if (multiplier == 1) {
    final digits = value.replaceAll(RegExp(r'[.,]'), '');
    return int.tryParse(digits);
  }
  final separator = math.max(value.lastIndexOf('.'), value.lastIndexOf(','));
  final normalized = separator < 0
      ? value
      : '${value.substring(0, separator).replaceAll(RegExp(r'[.,]'), '')}.'
            '${value.substring(separator + 1)}';
  final parsed = double.tryParse(normalized);
  if (parsed == null || !parsed.isFinite || parsed < 0) return null;
  return (parsed * multiplier).floor();
}

String? _normalizedInventoryAmountText(String source) {
  var value = source.trim().toUpperCase().replaceAll(' ', '');
  if (value.isEmpty || value.startsWith('+') || value.contains('/')) {
    return null;
  }
  // A dark item-slot border is occasionally read as a leading minus. Storage
  // quantities cannot be negative, so this one leading OCR artifact is safe
  // to discard. A real enhancement marker uses `+` and remains excluded.
  value = value.replaceFirst(RegExp(r'^[-_\u2013\u2014](?=[0-9OIL])'), '');
  if (!RegExp(r'^[0-9OIL.,KMB]+$').hasMatch(value)) return null;
  if (RegExp(r'\d').hasMatch(value)) {
    value = value
        .replaceAll('O', '0')
        .replaceAll('I', '1')
        .replaceAll('L', '1');
  }
  return value;
}

final class _InventoryArtwork {
  const _InventoryArtwork({required this.names, required this.fingerprint});

  final List<String> names;
  final List<double> fingerprint;
}

final class _QuantityWord {
  const _QuantityWord({required this.line, required this.quantity});

  final StillImageOcrLine line;
  final int quantity;
}

List<StillImageOcrLine> _normalizedOcrWords(List<StillImageOcrLine> source) {
  final retained = <StillImageOcrLine>[];
  for (final candidate in source) {
    if (candidate.text.trim().isEmpty ||
        candidate.width <= 0 ||
        candidate.height <= 0) {
      continue;
    }
    final match = retained.indexWhere(
      (existing) => _sameOcrRegion(existing, candidate),
    );
    if (match < 0) {
      retained.add(candidate);
      continue;
    }
    final existingAmount = parseVisibleInventoryAmount(retained[match].text);
    final candidateAmount = parseVisibleInventoryAmount(candidate.text);
    // A later enlarged pass may disagree with an already valid primary-pass
    // amount. Keep the first readable value and let the crop remain editable
    // in review instead of silently replacing one plausible number with
    // another. A numeric supplemental result may still replace OCR noise.
    if (existingAmount != null && candidateAmount != null) continue;
    if (_ocrWordQuality(candidate.text) >
        _ocrWordQuality(retained[match].text)) {
      retained[match] = candidate;
    }
  }
  return List<StillImageOcrLine>.unmodifiable(retained);
}

bool _sameOcrRegion(StillImageOcrLine left, StillImageOcrLine right) {
  final intersectionLeft = math.max(left.left, right.left);
  final intersectionTop = math.max(left.top, right.top);
  final intersectionRight = math.min(
    left.left + left.width,
    right.left + right.width,
  );
  final intersectionBottom = math.min(
    left.top + left.height,
    right.top + right.height,
  );
  final intersectionWidth = math.max(0.0, intersectionRight - intersectionLeft);
  final intersectionHeight = math.max(
    0.0,
    intersectionBottom - intersectionTop,
  );
  final intersection = intersectionWidth * intersectionHeight;
  final smallerArea = math.min(
    left.width * left.height,
    right.width * right.height,
  );
  if (smallerArea > 0 && intersection / smallerArea >= .62) return true;
  final horizontalCenterDifference =
      ((left.left + left.width / 2) - (right.left + right.width / 2)).abs();
  final verticalCenterDifference =
      ((left.top + left.height / 2) - (right.top + right.height / 2)).abs();
  return horizontalCenterDifference <=
          math.min(left.width, right.width) * .22 &&
      verticalCenterDifference <= math.min(left.height, right.height) * .45;
}

int _ocrWordQuality(String source) {
  final normalized = _normalizedInventoryAmountText(source);
  if (normalized != null && parseVisibleInventoryAmount(source) != null) {
    return 1000 + normalized.length;
  }
  final trimmed = source.trim();
  final useful = RegExp(r'[A-Za-z0-9]').allMatches(trimmed).length;
  final noise = RegExp(
    r"[^A-Za-z0-9\-'. ,]",
  ).allMatches(trimmed.replaceAll(' ', '')).length;
  return useful * 4 - noise * 3 + trimmed.length;
}

List<StillImageOcrLine> _mergeQuantityFragments(List<StillImageOcrLine> words) {
  final fragments =
      words.where((word) {
        final normalized = _normalizedInventoryAmountText(word.text);
        return normalized != null && RegExp(r'\d').hasMatch(normalized);
      }).toList()..sort((left, right) {
        final vertical = left.top.compareTo(right.top);
        return vertical != 0 ? vertical : left.left.compareTo(right.left);
      });
  final rows = <List<StillImageOcrLine>>[];
  for (final fragment in fragments) {
    final center = fragment.top + fragment.height / 2;
    List<StillImageOcrLine>? target;
    for (final row in rows) {
      final anchor = row.first.top + row.first.height / 2;
      if ((anchor - center).abs() <=
          math.max(3.0, math.min(row.first.height, fragment.height) * .65)) {
        target = row;
        break;
      }
    }
    (target ?? (rows..add(<StillImageOcrLine>[])).last).add(fragment);
  }

  final merged = <StillImageOcrLine>[];
  for (final row in rows) {
    row.sort((left, right) => left.left.compareTo(right.left));
    var index = 0;
    while (index < row.length) {
      var current = row[index];
      var nextIndex = index + 1;
      while (nextIndex < row.length) {
        final next = row[nextIndex];
        final gap = next.left - (current.left + current.width);
        final maximumGap = math.max(
          2.5,
          math.min(current.height, next.height) * .65,
        );
        if (gap < -math.min(current.width, next.width) * .35 ||
            gap > maximumGap) {
          break;
        }
        final combinedText = '${current.text.trim()}${next.text.trim()}';
        if (parseVisibleInventoryAmount(combinedText) == null) break;
        final left = math.min(current.left, next.left);
        final top = math.min(current.top, next.top);
        final right = math.max(
          current.left + current.width,
          next.left + next.width,
        );
        final bottom = math.max(
          current.top + current.height,
          next.top + next.height,
        );
        current = StillImageOcrLine(
          text: combinedText,
          left: left,
          top: top,
          width: right - left,
          height: bottom - top,
        );
        nextIndex += 1;
      }
      merged.add(current);
      index = nextIndex;
    }
  }
  return List<StillImageOcrLine>.unmodifiable(merged);
}

List<List<_QuantityWord>> _quantityRows(List<_QuantityWord> words) {
  if (words.isEmpty) return const <List<_QuantityWord>>[];
  final sorted = List<_QuantityWord>.of(words)
    ..sort((left, right) => left.line.top.compareTo(right.line.top));
  final rows = <List<_QuantityWord>>[];
  for (final word in sorted) {
    final center = word.line.top + word.line.height / 2;
    List<_QuantityWord>? target;
    for (final row in rows) {
      final anchor = row.first.line.top + row.first.line.height / 2;
      final tolerance = math.max(5.0, row.first.line.height * .85);
      if ((anchor - center).abs() <= tolerance) {
        target = row;
        break;
      }
    }
    (target ?? (rows..add(<_QuantityWord>[])).last).add(word);
  }
  final retained = rows.where((row) => row.length >= 3).toList();
  for (final row in retained) {
    row.sort((left, right) => left.line.left.compareTo(right.line.left));
  }
  return retained;
}

double _estimatedCellSize(List<List<_QuantityWord>> rows) {
  final samples = <double>[];
  for (final row in rows) {
    for (var index = 1; index < row.length; index += 1) {
      final previous = row[index - 1].line;
      final current = row[index].line;
      final gap =
          (current.left + current.width / 2) -
          (previous.left + previous.width / 2);
      if (gap >= 30 && gap <= 110) samples.add(gap);
    }
  }
  final centers =
      rows.map((row) => row.first.line.top + row.first.line.height / 2).toList()
        ..sort();
  for (var index = 1; index < centers.length; index += 1) {
    final gap = centers[index] - centers[index - 1];
    if (gap >= 30 && gap <= 110) samples.add(gap);
  }
  if (samples.isEmpty) return 50;
  samples.sort();
  return samples[samples.length ~/ 2];
}

String? _suggestLocationName(List<StillImageOcrLine> words, int height) {
  final candidates =
      words
          .where(
            (word) => word.top < height * .16 && word.text.trim().isNotEmpty,
          )
          .toList()
        ..sort((left, right) {
          final vertical = left.top.compareTo(right.top);
          return vertical != 0 ? vertical : left.left.compareTo(right.left);
        });
  final lines = <List<StillImageOcrLine>>[];
  for (final word in candidates) {
    final center = word.top + word.height / 2;
    List<StillImageOcrLine>? target;
    for (final line in lines) {
      final anchor = line.first.top + line.first.height / 2;
      if ((anchor - center).abs() <= math.max(5, line.first.height * .8)) {
        target = line;
        break;
      }
    }
    (target ?? (lines..add(<StillImageOcrLine>[])).last).add(word);
  }
  for (final line in lines) {
    line.sort((left, right) => left.left.compareTo(right.left));
    final text = line.map((word) => word.text.trim()).join(' ').trim();
    if (RegExp(
      r'\b(storage|inventory)\b',
      caseSensitive: false,
    ).hasMatch(text)) {
      return text.replaceAll(RegExp(r'\s+'), ' ');
    }
  }
  return null;
}

List<double> _fingerprint(
  image.Image source, {
  required bool transparentBackground,
}) {
  final insetX = math.max(1, (source.width * .07).round());
  final insetY = math.max(1, (source.height * .07).round());
  final usableWidth = math.max(1, source.width - insetX * 2);
  final usableHeight = math.max(1, (source.height * .72).round() - insetY);
  final cropped = image.copyCrop(
    source,
    x: insetX,
    y: insetY,
    width: usableWidth,
    height: math.min(usableHeight, source.height - insetY),
  );
  final resized = image.copyResize(
    cropped,
    width: 8,
    height: 6,
    interpolation: image.Interpolation.average,
  );
  final values = <double>[];
  for (var y = 0; y < resized.height; y += 1) {
    for (var x = 0; x < resized.width; x += 1) {
      final pixel = resized.getPixel(x, y);
      final alpha = transparentBackground ? pixel.a / 255.0 : 1.0;
      values
        ..add((pixel.r * alpha + 27 * (1 - alpha)) / 255.0)
        ..add((pixel.g * alpha + 27 * (1 - alpha)) / 255.0)
        ..add((pixel.b * alpha + 27 * (1 - alpha)) / 255.0);
    }
  }
  return List<double>.unmodifiable(values);
}

double _distance(List<double> left, List<double> right) {
  if (left.length != right.length || left.isEmpty) return 1;
  var sum = 0.0;
  for (var index = 0; index < left.length; index += 1) {
    final difference = left[index] - right[index];
    sum += difference * difference;
  }
  return math.sqrt(sum / left.length);
}

T? _foldedValue<T>(Map<String, T> values, String name) {
  final folded = name.trim().toLowerCase();
  for (final entry in values.entries) {
    if (entry.key.trim().toLowerCase() == folded) return entry.value;
  }
  return null;
}

int _compareNames(String left, String right) {
  final folded = left.toLowerCase().compareTo(right.toLowerCase());
  return folded != 0 ? folded : left.compareTo(right);
}
