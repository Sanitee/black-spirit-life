/// Combines acquisition copy without repeating a vendor fallback. Facts stay
/// in reading order, one per line. Only exact facts (apart from formatting and
/// articles in "Buy from") are merged; quantities and restrictions stay intact.
List<String> composeAcquisitionNotes({
  required Iterable<String?> notes,
  String? vendor,
  String? location,
}) {
  final lines = <String>[];
  final identities = <String>{};
  for (final note in notes) {
    for (final line in _facts(note ?? '')) {
      if (identities.add(_identity(line))) lines.add(line);
    }
  }

  final seller = vendor?.trim() ?? '';
  final place = location?.trim() ?? '';
  if (seller.isNotEmpty) {
    final fallback = 'Buy from $seller${place.isEmpty ? '' : ' in $place'}.';
    final fallbackIdentity = _identity(fallback);
    final richerVendorNote = lines.any(
      (line) =>
          _identity(line) != fallbackIdentity &&
          _coversVendor(line, seller, place),
    );
    if (richerVendorNote) {
      lines.removeWhere((line) => _identity(line) == fallbackIdentity);
    } else if (!lines.any((line) => _coversVendor(line, seller, place)) &&
        identities.add(fallbackIdentity)) {
      lines.add(fallback);
    }
  }
  return List<String>.unmodifiable(lines);
}

Iterable<String> _facts(String text) sync* {
  final listLines = text.trim().split(RegExp(r'[\r\n]+'));
  if (listLines.length > 1 && listLines.first.trimRight().endsWith(':')) {
    // Keep an explicit heading/list together. The reading surfaces render its
    // lines separately while accessibility retains the heading's context.
    yield listLines.map((line) => line.trim()).join('\n');
    return;
  }
  for (final paragraph in text.split(RegExp(r'[\r\n]+'))) {
    var start = 0;
    for (var index = 0; index < paragraph.length; index++) {
      if (!'.!?'.contains(paragraph[index])) continue;
      if (index + 1 < paragraph.length &&
          !RegExp(r'\s').hasMatch(paragraph[index + 1])) {
        continue;
      }
      final fact = paragraph.substring(start, index + 1).trim();
      if (fact.isNotEmpty) yield fact;
      start = index + 1;
    }
    final remainder = paragraph.substring(start).trim();
    if (remainder.isNotEmpty) yield remainder;
  }
}

String _identity(String value) => value
    .trim()
    .toLowerCase()
    .replaceAll(RegExp(r'\s+'), ' ')
    .replaceFirst(RegExp(r'^(buy|purchase) from (a|an|the) '), 'buy from ')
    .replaceFirst(RegExp(r'^purchase from '), 'buy from ')
    .replaceFirst(RegExp(r'[.!?]+$'), '');

bool _coversVendor(String note, String vendor, String location) {
  final text = _words(note);
  // A quest, restriction or map instruction mentioning an NPC does not
  // establish a purchase route.
  if (!RegExp(r'^(buy|purchase|sold by|sold at)\b').hasMatch(text) ||
      RegExp(r'\b(not|cannot|except|no longer|instead)\b').hasMatch(text)) {
    return false;
  }
  final seller = _words(vendor);
  final place = _words(location);
  final sellerMatch = RegExp(
    '(?:^| )${RegExp.escape(seller)}(?= |\$)',
  ).firstMatch(text);
  if (sellerMatch == null) return false;
  if (place.isEmpty) return true;
  final afterSeller = text.substring(sellerMatch.end).trimLeft();
  // Keep the location attached to this seller, not a different NPC later in
  // the same sentence.
  return RegExp(
    '^(?:(?:in|at) )?${RegExp.escape(place)}(?: |\$)',
  ).hasMatch(afterSeller);
}

String _words(String value) => value
    .trim()
    .toLowerCase()
    .replaceAll(RegExp(r'[.,!?():;\[\]]'), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();
