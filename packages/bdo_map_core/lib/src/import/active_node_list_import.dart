import '../model/resource_map_data.dart';

/// One OCR text row read from a sampled frame of BDO's Production Node Status
/// list.
///
/// The native Windows bridge supplies these records. Keeping the matching
/// layer independent from the video decoder makes it deterministic and fully
/// testable without shipping video fixtures or a second OCR runtime.
final class BdoActiveNodeOcrLine {
  const BdoActiveNodeOcrLine({
    required this.text,
    required this.frameIndex,
    required this.timestampMilliseconds,
    required this.frameSharpness,
    this.left = 0,
    this.top = 0,
    this.width = 0,
    this.height = 0,
  });

  final String text;
  final int frameIndex;
  final int timestampMilliseconds;
  final double frameSharpness;
  final double left;
  final double top;
  final double width;
  final double height;
}

/// A sharp video frame selected by the native Media Foundation sampler.
final class BdoActiveNodeOcrFrame {
  BdoActiveNodeOcrFrame({
    required this.frameIndex,
    required this.timestampMilliseconds,
    required this.sharpness,
    required Iterable<BdoActiveNodeOcrLine> lines,
  }) : lines = List<BdoActiveNodeOcrLine>.unmodifiable(lines);

  final int frameIndex;
  final int timestampMilliseconds;
  final double sharpness;
  final List<BdoActiveNodeOcrLine> lines;
}

/// Offline OCR output returned by the Windows bridge before any node state is
/// changed.
final class BdoActiveNodeVideoOcrResult {
  BdoActiveNodeVideoOcrResult({
    required this.sourcePath,
    required this.ocrLanguage,
    required this.sourceWidth,
    required this.sourceHeight,
    required this.durationMilliseconds,
    required Iterable<BdoActiveNodeOcrFrame> frames,
    Iterable<String> diagnostics = const <String>[],
  }) : frames = List<BdoActiveNodeOcrFrame>.unmodifiable(frames),
       diagnostics = List<String>.unmodifiable(diagnostics);

  final String sourcePath;
  final String ocrLanguage;
  final int sourceWidth;
  final int sourceHeight;
  final int durationMilliseconds;
  final List<BdoActiveNodeOcrFrame> frames;
  final List<String> diagnostics;
}

enum BdoActiveNodeMatchDisposition { accepted, review, rejected }

enum BdoActiveNodeReviewReason {
  fuzzyText,
  truncatedText,
  closeAlternative,
  ambiguousNodeIds,
  missingOrUnclearActivity,
  weakFrame,
  noProductionNodeMatch,
}

/// One deduplicated row from the recorded Activated list.
///
/// [candidateNodeIds] can contain more than one ID because BDO displays some
/// distinct production children with the same site and activity label. Such a
/// row always requires review; text alone is not allowed to guess which child
/// the player invested in.
final class BdoActiveNodeImportMatch {
  BdoActiveNodeImportMatch({
    required this.disposition,
    required this.observedText,
    required this.confidence,
    required this.sightingCount,
    required this.firstTimestampMilliseconds,
    required this.lastTimestampMilliseconds,
    required this.sourceFrameIndex,
    required this.canonicalName,
    required this.canonicalActivity,
    required Iterable<String> candidateNodeIds,
    required Iterable<BdoActiveNodeReviewReason> reviewReasons,
  }) : candidateNodeIds = List<String>.unmodifiable(candidateNodeIds),
       reviewReasons = Set<BdoActiveNodeReviewReason>.unmodifiable(
         reviewReasons,
       );

  final BdoActiveNodeMatchDisposition disposition;
  final String observedText;
  final double confidence;
  final int sightingCount;
  final int firstTimestampMilliseconds;
  final int lastTimestampMilliseconds;
  final int sourceFrameIndex;
  final String? canonicalName;
  final String? canonicalActivity;
  final List<String> candidateNodeIds;
  final Set<BdoActiveNodeReviewReason> reviewReasons;

  bool get canApplyWithoutChoice =>
      disposition == BdoActiveNodeMatchDisposition.accepted &&
      candidateNodeIds.length == 1 &&
      reviewReasons.isEmpty;
}

final class BdoActiveNodeListImportResult {
  BdoActiveNodeListImportResult({
    required Iterable<BdoActiveNodeImportMatch> matches,
    required Iterable<BdoActiveNodeImportMatch> rejected,
  }) : matches = List<BdoActiveNodeImportMatch>.unmodifiable(matches),
       rejected = List<BdoActiveNodeImportMatch>.unmodifiable(rejected);

  final List<BdoActiveNodeImportMatch> matches;
  final List<BdoActiveNodeImportMatch> rejected;

  Iterable<BdoActiveNodeImportMatch> get accepted => matches.where(
    (match) => match.disposition == BdoActiveNodeMatchDisposition.accepted,
  );

  Iterable<BdoActiveNodeImportMatch> get requiringReview => matches.where(
    (match) => match.disposition == BdoActiveNodeMatchDisposition.review,
  );
}

/// Matches native OCR rows to the exact production-node catalog.
///
/// Only an exact, unique site-and-activity label can be accepted directly.
/// Fuzzy, truncated, activity-incomplete, or duplicate catalog labels remain
/// explicit review records. This service never mutates the player's setup.
abstract final class BdoActiveNodeListMatcher {
  static BdoActiveNodeListImportResult match({
    required Iterable<BdoActiveNodeOcrFrame> frames,
    required Iterable<BdoWorkerNode> productionNodes,
  }) {
    final catalog = _buildCatalog(productionNodes);
    final observations = <_MatchedObservation>[];
    final rejected = <BdoActiveNodeImportMatch>[];

    for (final frame in frames) {
      for (final line in frame.lines) {
        final text = line.text.trim();
        final normalized = _normalize(text);
        if (!_looksLikePossibleNodeRow(normalized)) continue;
        final candidate = _bestCandidate(text, normalized, catalog);
        if (candidate == null) {
          rejected.add(
            BdoActiveNodeImportMatch(
              disposition: BdoActiveNodeMatchDisposition.rejected,
              observedText: text,
              confidence: 0,
              sightingCount: 1,
              firstTimestampMilliseconds: line.timestampMilliseconds,
              lastTimestampMilliseconds: line.timestampMilliseconds,
              sourceFrameIndex: line.frameIndex,
              canonicalName: null,
              canonicalActivity: null,
              candidateNodeIds: const <String>[],
              reviewReasons: const <BdoActiveNodeReviewReason>{
                BdoActiveNodeReviewReason.noProductionNodeMatch,
              },
            ),
          );
          continue;
        }
        observations.add(
          _MatchedObservation(
            line: line,
            observedText: text,
            candidate: candidate,
          ),
        );
      }
    }

    final byCanonicalLabel = <String, List<_MatchedObservation>>{};
    for (final observation in observations) {
      (byCanonicalLabel[observation.candidate.entry.normalizedLabel] ??=
              <_MatchedObservation>[])
          .add(observation);
    }

    final matches = <BdoActiveNodeImportMatch>[];
    for (final group in byCanonicalLabel.values) {
      group.sort((left, right) {
        final byConfidence = right.candidate.confidence.compareTo(
          left.candidate.confidence,
        );
        if (byConfidence != 0) return byConfidence;
        return right.line.frameSharpness.compareTo(left.line.frameSharpness);
      });
      final primary = group.first;
      final entry = primary.candidate.entry;
      final reasons = <BdoActiveNodeReviewReason>{
        ...primary.candidate.reviewReasons,
      };
      if (entry.nodeIds.length != 1) {
        reasons.add(BdoActiveNodeReviewReason.ambiguousNodeIds);
      }
      if (primary.line.frameSharpness < 0.035) {
        reasons.add(BdoActiveNodeReviewReason.weakFrame);
      }
      final exactAndUnique =
          primary.candidate.exact && entry.nodeIds.length == 1;
      final disposition = exactAndUnique && reasons.isEmpty
          ? BdoActiveNodeMatchDisposition.accepted
          : BdoActiveNodeMatchDisposition.review;
      final timestamps = group
          .map((observation) => observation.line.timestampMilliseconds)
          .toList(growable: false);
      matches.add(
        BdoActiveNodeImportMatch(
          disposition: disposition,
          observedText: primary.observedText,
          confidence: primary.candidate.confidence,
          sightingCount: group.length,
          firstTimestampMilliseconds: timestamps.reduce(
            (left, right) => left < right ? left : right,
          ),
          lastTimestampMilliseconds: timestamps.reduce(
            (left, right) => left > right ? left : right,
          ),
          sourceFrameIndex: primary.line.frameIndex,
          canonicalName: entry.siteName,
          canonicalActivity: entry.activity,
          candidateNodeIds: entry.nodeIds,
          reviewReasons: reasons,
        ),
      );
    }
    matches.sort((left, right) {
      final byTime = left.firstTimestampMilliseconds.compareTo(
        right.firstTimestampMilliseconds,
      );
      return byTime != 0
          ? byTime
          : (left.canonicalName ?? '').compareTo(right.canonicalName ?? '');
    });
    rejected.sort(
      (left, right) => left.firstTimestampMilliseconds.compareTo(
        right.firstTimestampMilliseconds,
      ),
    );
    return BdoActiveNodeListImportResult(matches: matches, rejected: rejected);
  }

  static List<_CatalogEntry> _buildCatalog(
    Iterable<BdoWorkerNode> productionNodes,
  ) {
    final grouped = <String, _MutableCatalogEntry>{};
    for (final node in productionNodes.where(
      (node) => node.isResourceNode && node.isProductionNode,
    )) {
      final site = node.siteName.trim();
      final activity = _activatedListActivity(node).trim();
      if (site.isEmpty || activity.isEmpty) continue;
      final normalizedSite = _normalize(site);
      final normalizedActivity = _normalize(activity);
      final normalizedLabel = '$normalizedSite $normalizedActivity';
      final entry = grouped.putIfAbsent(
        normalizedLabel,
        () => _MutableCatalogEntry(
          siteName: site,
          activity: activity,
          normalizedSite: normalizedSite,
          normalizedActivity: normalizedActivity,
          normalizedLabel: normalizedLabel,
        ),
      );
      entry.nodeIds.add(node.id);
    }
    final result = grouped.values
        .map(
          (entry) => _CatalogEntry(
            siteName: entry.siteName,
            activity: entry.activity,
            normalizedSite: entry.normalizedSite,
            normalizedActivity: entry.normalizedActivity,
            normalizedLabel: entry.normalizedLabel,
            nodeIds: (entry.nodeIds..sort()).toList(growable: false),
          ),
        )
        .toList(growable: false);
    result.sort(
      (left, right) => left.normalizedLabel.compareTo(right.normalizedLabel),
    );
    return result;
  }

  static _Candidate? _bestCandidate(
    String raw,
    String normalized,
    List<_CatalogEntry> catalog,
  ) {
    if (catalog.isEmpty || normalized.isEmpty) return null;
    final truncated = raw.contains('\u2026') || raw.contains('...');
    final scored = <_Candidate>[];
    for (final entry in catalog) {
      final fullScore = _similarity(normalized, entry.normalizedLabel);
      final exact = normalized == entry.normalizedLabel;
      final prefix =
          truncated &&
          normalized.length >= 8 &&
          entry.normalizedLabel.startsWith(normalized);
      var score = exact
          ? 1.0
          : prefix
          ? 0.91
          : fullScore;

      final activityEvidence = _activityEvidence(
        normalized,
        entry.normalizedActivity,
      );
      final siteEvidence = normalized.contains(entry.normalizedSite)
          ? 1.0
          : _similarity(_stripLikelyActivity(normalized), entry.normalizedSite);
      score = (score * 0.64 + siteEvidence * 0.28 + activityEvidence * 0.08)
          .clamp(0, 1);
      if (exact) score = 1;
      scored.add(
        _Candidate(
          entry: entry,
          confidence: score,
          exact: exact,
          truncated: prefix,
          activityEvidence: activityEvidence,
        ),
      );
    }
    scored.sort((left, right) => right.confidence.compareTo(left.confidence));
    final best = scored.first;
    if (best.confidence < 0.68) return null;
    final second = scored.length > 1 ? scored[1] : null;
    final reasons = <BdoActiveNodeReviewReason>{};
    if (!best.exact) reasons.add(BdoActiveNodeReviewReason.fuzzyText);
    if (best.truncated) reasons.add(BdoActiveNodeReviewReason.truncatedText);
    if (best.activityEvidence < 0.78) {
      reasons.add(BdoActiveNodeReviewReason.missingOrUnclearActivity);
    }
    if (second != null &&
        best.confidence - second.confidence < 0.075 &&
        second.entry.normalizedLabel != best.entry.normalizedLabel) {
      reasons.add(BdoActiveNodeReviewReason.closeAlternative);
    }
    return best.withReviewReasons(reasons);
  }
}

String _activatedListActivity(BdoWorkerNode node) {
  final separator = node.name.lastIndexOf(' - ');
  if (separator >= 0 && separator + 3 < node.name.length) {
    final activity = node.name.substring(separator + 3).trim();
    if (activity.isNotEmpty) return activity;
  }
  return node.activityLabel;
}

final class _CatalogEntry {
  const _CatalogEntry({
    required this.siteName,
    required this.activity,
    required this.normalizedSite,
    required this.normalizedActivity,
    required this.normalizedLabel,
    required this.nodeIds,
  });

  final String siteName;
  final String activity;
  final String normalizedSite;
  final String normalizedActivity;
  final String normalizedLabel;
  final List<String> nodeIds;
}

final class _MutableCatalogEntry {
  _MutableCatalogEntry({
    required this.siteName,
    required this.activity,
    required this.normalizedSite,
    required this.normalizedActivity,
    required this.normalizedLabel,
  });

  final String siteName;
  final String activity;
  final String normalizedSite;
  final String normalizedActivity;
  final String normalizedLabel;
  final List<String> nodeIds = <String>[];
}

final class _Candidate {
  const _Candidate({
    required this.entry,
    required this.confidence,
    required this.exact,
    required this.truncated,
    required this.activityEvidence,
    this.reviewReasons = const <BdoActiveNodeReviewReason>{},
  });

  final _CatalogEntry entry;
  final double confidence;
  final bool exact;
  final bool truncated;
  final double activityEvidence;
  final Set<BdoActiveNodeReviewReason> reviewReasons;

  _Candidate withReviewReasons(Set<BdoActiveNodeReviewReason> reasons) =>
      _Candidate(
        entry: entry,
        confidence: confidence,
        exact: exact,
        truncated: truncated,
        activityEvidence: activityEvidence,
        reviewReasons: Set<BdoActiveNodeReviewReason>.unmodifiable(reasons),
      );
}

final class _MatchedObservation {
  const _MatchedObservation({
    required this.line,
    required this.observedText,
    required this.candidate,
  });

  final BdoActiveNodeOcrLine line;
  final String observedText;
  final _Candidate candidate;
}

bool _looksLikePossibleNodeRow(String normalized) {
  if (normalized.length < 4 || !RegExp(r'[a-z]').hasMatch(normalized)) {
    return false;
  }
  const chrome = <String>{
    'production node status',
    'activated',
    'deactivated',
    'active',
    'inactive',
    'close',
  };
  if (chrome.contains(normalized)) return false;
  if (normalized.startsWith('activated ') ||
      normalized.startsWith('deactivated ')) {
    return false;
  }
  return true;
}

double _activityEvidence(String text, String activity) {
  if (text.endsWith(activity) || text.contains(' $activity')) return 1;
  final words = text.split(' ');
  for (var take = 1; take <= 3 && take <= words.length; take++) {
    final suffix = words.sublist(words.length - take).join(' ');
    if (activity.startsWith(suffix) && suffix.length >= 2) return 0.82;
  }
  return _similarity(words.isEmpty ? text : words.last, activity);
}

String _stripLikelyActivity(String value) {
  const activities = <String>[
    'excavation',
    'gathering',
    'lumbering',
    'farming',
    'fishing',
    'mining',
  ];
  for (final activity in activities) {
    if (value.endsWith(' $activity')) {
      return value.substring(0, value.length - activity.length).trim();
    }
    final words = value.split(' ');
    if (words.isNotEmpty &&
        activity.startsWith(words.last) &&
        words.last.length >= 2) {
      return words.sublist(0, words.length - 1).join(' ');
    }
  }
  return value;
}

double _similarity(String left, String right) {
  if (left == right) return 1;
  if (left.isEmpty || right.isEmpty) return 0;
  final distance = _levenshtein(left, right);
  return (1 -
          distance / (left.length > right.length ? left.length : right.length))
      .clamp(0, 1);
}

int _levenshtein(String left, String right) {
  var previous = List<int>.generate(right.length + 1, (index) => index);
  for (var leftIndex = 0; leftIndex < left.length; leftIndex++) {
    final current = List<int>.filled(right.length + 1, 0);
    current[0] = leftIndex + 1;
    for (var rightIndex = 0; rightIndex < right.length; rightIndex++) {
      final substitution =
          previous[rightIndex] +
          (left.codeUnitAt(leftIndex) == right.codeUnitAt(rightIndex) ? 0 : 1);
      final insertion = current[rightIndex] + 1;
      final deletion = previous[rightIndex + 1] + 1;
      current[rightIndex + 1] = insertion < deletion
          ? (insertion < substitution ? insertion : substitution)
          : (deletion < substitution ? deletion : substitution);
    }
    previous = current;
  }
  return previous.last;
}

String _normalize(String value) => value
    .toLowerCase()
    .replaceAll('\u2019', "'")
    .replaceAll('\u2018', "'")
    .replaceAll('\u2026', ' ')
    .replaceAll(RegExp(r'\.{2,}'), ' ')
    .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();
