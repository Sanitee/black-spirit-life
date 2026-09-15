import 'dart:convert';
import 'package:flutter/services.dart';
import '../assets.dart';
import 'bairog_calculator.dart';
import 'world_map.dart';
import 'session_import.dart';

export 'session_import.dart' show SessionImportMetadata, SessionImportItem;

Map<String, dynamic> objectMap(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};
List<Map<String, dynamic>> objectList(Object? value) => value is List
    ? value.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
    : <Map<String, dynamic>>[];
List<String> strings(Object? value) =>
    value is List ? value.map((e) => e.toString()).toList() : <String>[];
String textOf(Map<String, dynamic> map, String key, [String fallback = '']) =>
    map[key]?.toString() ?? fallback;
int? itemGrade(Object? value) =>
    value is int && value >= 0 && value <= 5 ? value : null;

class Method {
  Method(Map<String, dynamic> j)
    : id = textOf(j, 'id'),
      label = textOf(j, 'label'),
      icon = textOf(j, 'icon'),
      activity = textOf(j, 'activity', 'gathering');
  final String id, label, icon, activity;
}

class Spot {
  Spot(Map<String, dynamic> j)
    : id = textOf(j, 'id'),
      name = textOf(j, 'name'),
      displayName = textOf(
        j,
        'displayName',
        textOf(j, 'name').split('·').last.trim(),
      ),
      nodeName = textOf(j, 'nodeName', textOf(j, 'mapAnchorName')),
      icon = textOf(j, 'icon'),
      region = textOf(j, 'region'),
      methodIds = strings(j['methodIds']),
      priority = (j['priority'] as num?)?.toInt() ?? 100,
      difficulty = textOf(j, 'difficulty', 'Intermediate'),
      summary = textOf(j, 'summary'),
      directions = strings(j['directions']),
      requirements = strings(j['requirements']),
      tips = strings(j['tips']),
      materials = objectList(j['materials']),
      guideLinks = objectList(j['guideLinks']),
      media = objectList(j['media']).map(SpotMedia.new).toList(),
      sourceUrls = strings(j['sourceUrls']),
      x = (j['worldX'] as num?)?.toDouble(),
      z = (j['worldZ'] as num?)?.toDouble(),
      mapPrecision = textOf(j, 'mapPrecision', 'unmapped'),
      mapNote = textOf(j, 'mapNote');
  final String id,
      name,
      displayName,
      nodeName,
      icon,
      region,
      difficulty,
      summary,
      mapPrecision,
      mapNote;
  final List<String> methodIds, directions, requirements, tips, sourceUrls;
  final List<Map<String, dynamic>> materials, guideLinks;
  final List<SpotMedia> media;
  final int priority;
  final double? x, z;
  bool get mapped => x != null && z != null;
}

class SpotMedia {
  SpotMedia(Map<String, dynamic> json)
    : type = textOf(json, 'type'),
      title = textOf(json, 'title'),
      asset = textOf(json, 'asset'),
      url = textOf(json, 'url'),
      sourceUrl = textOf(json, 'sourceUrl'),
      author = textOf(json, 'author'),
      publishedDate = _publishedDate(textOf(json, 'publishedDate')),
      methodIds = strings(json['methodIds']);
  final String type, title, asset, url, sourceUrl, author;
  final DateTime? publishedDate;
  final List<String> methodIds;
  bool matchesMethod(String methodId) =>
      methodIds.isEmpty || methodIds.contains(methodId);

  static DateTime? _publishedDate(String value) {
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) return null;
    final date = DateTime.tryParse(value);
    // DateTime accepts overflowing dates; catalog publication dates must be exact.
    return date != null && date.toIso8601String().startsWith(value)
        ? date
        : null;
  }
}

class BuffComponent {
  BuffComponent(Map<String, dynamic> j)
    : id = textOf(j, 'id', '${j['itemId'] ?? j['name'] ?? ''}'),
      itemId = (j['itemId'] as num?)?.toInt(),
      name = textOf(j, 'name'),
      icon = textOf(j, 'icon'),
      grade = itemGrade(j['grade']),
      effectSummary = textOf(j, 'effectSummary'),
      effects = Map.unmodifiable(
        objectMap(j['effects']).map(
          (k, v) => MapEntry(k, v is num && v.isFinite ? v.toDouble() : 0.0),
        ),
      );

  final String id, name, icon, effectSummary;
  final int? itemId;
  final int? grade;
  final Map<String, double> effects;

  Map<String, dynamic> snapshot() => {
    'id': id,
    if (itemId != null) 'itemId': itemId,
    'name': name,
    'icon': icon,
    if (grade != null) 'grade': grade,
    if (effectSummary.isNotEmpty) 'effectSummary': effectSummary,
    if (effects.isNotEmpty) 'effects': effects,
  };
}

class Buff {
  Buff(Map<String, dynamic> j)
    : id = textOf(j, 'id'),
      name = textOf(j, 'name'),
      category = textOf(j, 'category'),
      icon = textOf(j, 'icon'),
      grade = itemGrade(j['grade']),
      priority = (j['priority'] as num?)?.toInt() ?? 100,
      duration = (j['durationMinutes'] as num?)?.toDouble(),
      recommendedFor = strings(j['recommendedFor']),
      exclusiveGroup = textOf(j, 'exclusiveGroup'),
      conflictsWithGroups = strings(j['conflictsWithGroups']),
      notes = j['notes'] is List
          ? strings(j['notes']).join(' ')
          : textOf(j, 'notes'),
      aliases = strings(j['aliases']),
      durationNote = textOf(j, 'durationNote'),
      effectSummary = textOf(j, 'effectSummary'),
      obtainSummary = textOf(j, 'obtainSummary'),
      referenceOnly = j['referenceOnly'] == true,
      sourceUrls = strings(j['sourceUrls']),
      components = objectList(
        j['components'],
      ).map(BuffComponent.new).toList(growable: false),
      effects = Map.unmodifiable(
        objectMap(j['effects']).map(
          (k, v) => MapEntry(k, v is num && v.isFinite ? v.toDouble() : 0.0),
        ),
      );
  final String id,
      name,
      category,
      icon,
      exclusiveGroup,
      notes,
      durationNote,
      effectSummary,
      obtainSummary;
  final int priority;
  final int? grade;
  final double? duration;
  final bool referenceOnly;
  final List<String> recommendedFor, conflictsWithGroups, sourceUrls, aliases;
  final List<BuffComponent> components;
  final Map<String, double> effects;
  bool conflictsWith(Buff other) =>
      id != other.id &&
      ((exclusiveGroup.isNotEmpty && exclusiveGroup == other.exclusiveGroup) ||
          conflictsWithGroups.contains(other.exclusiveGroup) ||
          other.conflictsWithGroups.contains(exclusiveGroup));
  Map<String, dynamic> snapshot() => {
    'id': id,
    'name': name,
    'category': category,
    'icon': icon,
    if (grade != null) 'grade': grade,
    if (effectSummary.isNotEmpty) 'effectSummary': effectSummary,
    if (obtainSummary.isNotEmpty) 'obtainSummary': obtainSummary,
    if (referenceOnly) 'referenceOnly': true,
    if (components.isNotEmpty)
      'components': components
          .map((component) => component.snapshot())
          .toList(),
    'effects': effects,
    'durationMinutes': duration,
  };
}

class GameItem {
  GameItem(Map<String, dynamic> j)
    : id = '${j['id'] ?? j['itemId'] ?? j['name']}',
      name = textOf(j, 'name'),
      icon = textOf(j, 'icon');
  final String id, name, icon;
}

class Catalog {
  Catalog({
    required this.methods,
    required this.spots,
    required this.buffs,
    required this.items,
    required this.categories,
    required this.stats,
    required this.presets,
    required this.stackingNotes,
    required this.reviewedAt,
    this.limitations = const [],
    this.ordering = '',
    this.mapNodes = const [],
    this.commonLoot = const [],
    this.bairogCalculatorData,
  });
  final List<Method> methods;
  final List<Spot> spots;
  final List<Buff> buffs;
  final List<GameItem> items;
  final List<WorldNode> mapNodes;
  final List<Map<String, dynamic>> commonLoot;
  final BairogCalculatorData? bairogCalculatorData;
  final List<Map<String, dynamic>> categories, stats, presets;
  final List<String> stackingNotes;
  final List<String> limitations;
  final String reviewedAt, ordering;
  static Future<Catalog> load() async {
    final values = await Future.wait(
      ['buffs', 'spots', 'loot_catalog', 'map_nodes', 'bairog_calculator'].map(
        (s) async => objectMap(
          jsonDecode(
            await rootBundle.loadString(
              gatheringBundleAsset('assets/data/$s.json'),
            ),
          ),
        ),
      ),
    );
    final b = values[0], s = values[1], l = values[2];
    return Catalog(
      methods: objectList(s['methods']).map(Method.new).toList(),
      spots: objectList(s['spots']).map(Spot.new).toList()
        ..sort((a, b) => a.priority.compareTo(b.priority)),
      buffs: objectList(b['buffs']).map(Buff.new).toList()
        ..sort((a, b) => a.priority.compareTo(b.priority)),
      items: objectList(l['items']).map(GameItem.new).toList()
        ..sort((a, b) => a.name.compareTo(b.name)),
      categories: objectList(b['categories']),
      stats: objectList(b['stats']),
      presets: objectList(b['presets']),
      stackingNotes: strings(b['stackingNotes']),
      limitations: strings(b['limitations']),
      ordering: textOf(b, 'ordering'),
      reviewedAt: textOf(b, 'reviewedAt', '2026-08-31'),
      mapNodes: objectList(values[3]['nodes']).map(WorldNode.fromJson).toList(),
      commonLoot: objectList(s['commonLoot']),
      bairogCalculatorData: BairogCalculatorData.fromJson(values[4]),
    );
  }

  Map<String, double> sumBuffs(Iterable<String> ids) {
    final selected = ids.toSet();
    final result = <String, double>{};
    for (final b in buffs.where((b) => selected.contains(b.id))) {
      for (final e in b.effects.entries) {
        result.update(e.key, (n) => n + e.value, ifAbsent: () => e.value);
      }
    }
    return result;
  }

  String statLabel(String id) =>
      stats.where((s) => s['id'] == id).firstOrNull?['label']?.toString() ??
      id.replaceAllMapped(RegExp(r'[A-Z]'), (m) => ' ${m[0]}');
  String statUnit(String id) =>
      stats.where((s) => s['id'] == id).firstOrNull?['unit']?.toString() ?? '';
  List<Buff> selectedBuffs(Iterable<String> ids) =>
      buffs.where((b) => ids.contains(b.id)).toList();

  /// Verified drops for this activity. Group labels without item identities are
  /// deliberately excluded; unexpected drops can still be entered manually.
  List<GameItem> lootForSpot(Spot? spot, String methodId) {
    if (spot == null || !spot.methodIds.contains(methodId)) return const [];
    final itemIndex = {for (final item in items) item.id: item};
    final result = <String, GameItem>{};
    for (final material in [...spot.materials, ...commonLoot]) {
      if (!strings(material['methodIds']).contains(methodId) ||
          strings(material['excludedSpotIds']).contains(spot.id)) {
        continue;
      }
      final id = textOf(material, 'itemId');
      if (id.isEmpty || result.containsKey(id)) continue;
      final item =
          itemIndex[id] ??
          GameItem({
            'id': id,
            'name': textOf(material, 'name'),
            'icon': textOf(material, 'icon'),
          });
      if (item.name.isNotEmpty) result[id] = item;
    }
    return result.values.toList();
  }
}

/// Inventory snapshots and amounts sent away are separate observations.
/// Nothing in a draft or saved session contains image bytes or source paths.
class LootEntry {
  LootEntry({
    required this.id,
    required this.name,
    this.icon = '',
    this.start = 0,
    this.remaining = 0,
    this.sentAway = 0,
    this.overrideTotal,
    bool isApproximate = false,
    bool? observationsApproximate,
    this.hasInventorySnapshot = false,
  }) : _isApproximate = isApproximate,
       observationsApproximate =
           (observationsApproximate ?? false) || isApproximate;
  final String id;
  String name, icon;
  int start, remaining, sentAway;
  int? overrideTotal;
  bool _isApproximate;

  /// Durable accuracy of the inventory/deposit observations beneath an override.
  /// Exact whole totals do not erase this provenance.
  bool observationsApproximate;
  bool get isApproximate => overrideTotal == null
      ? observationsApproximate || _isApproximate
      : _isApproximate;
  set isApproximate(bool value) {
    _isApproximate = value;
    if (value) observationsApproximate = true;
  }

  bool hasInventorySnapshot;
  int get rawTotal => overrideTotal ?? remaining - start + sentAway;
  int get total => rawTotal < 0 ? 0 : rawTotal;

  /// Deposits are inventory observations. A manually entered overall total
  /// already includes them until a new inventory snapshot resumes calculation.
  void recordMaidDeposit(int amount, {bool approximate = false}) {
    sentAway += amount;
    if (approximate) observationsApproximate = true;
  }

  void addBatch(int amount) {
    if (overrideTotal case final total?) {
      overrideTotal = total + amount;
    } else {
      sentAway += amount;
    }
  }

  void setSnapshot(int amount, {bool approximate = false}) {
    remaining = amount;
    hasInventorySnapshot = true;
    overrideTotal = null;
    if (approximate) observationsApproximate = true;
  }

  void setStart(int amount, {bool approximate = false}) {
    start = amount;
    if (!hasInventorySnapshot) remaining = amount;
    overrideTotal = null;
    if (approximate) observationsApproximate = true;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'icon': icon,
    'start': start,
    'remaining': remaining,
    'sentAway': sentAway,
    'overrideTotal': overrideTotal,
    'quantity': total,
    'isApproximate': isApproximate,
    'observationsApproximate': observationsApproximate,
    'hasInventorySnapshot': hasInventorySnapshot,
  };
  factory LootEntry.fromJson(Map<String, dynamic> j) => LootEntry(
    id: textOf(j, 'id'),
    name: textOf(j, 'name'),
    icon: textOf(j, 'icon'),
    start: (j['start'] as num?)?.toInt() ?? 0,
    remaining: (j['remaining'] as num?)?.toInt() ?? 0,
    sentAway: (j['sentAway'] as num?)?.toInt() ?? 0,
    overrideTotal: (j['overrideTotal'] as num?)?.toInt(),
    isApproximate: j['isApproximate'] == true,
    observationsApproximate: j['observationsApproximate'] is bool
        ? j['observationsApproximate'] as bool
        : j['isApproximate'] == true ||
              (j['overrideTotal'] != null &&
                  (j['hasInventorySnapshot'] == true ||
                      (j['start'] as num? ?? 0) != 0 ||
                      (j['remaining'] as num? ?? 0) != 0 ||
                      (j['sentAway'] as num? ?? 0) != 0)),
    hasInventorySnapshot: j['hasInventorySnapshot'] == true,
  );
}

class GatheringSession {
  GatheringSession({
    required this.id,
    required this.createdAt,
    required this.methodId,
    required this.methodLabel,
    required this.methodIcon,
    required this.spotId,
    required this.spotName,
    required this.durationSeconds,
    required this.loot,
    required this.buffs,
    required this.buffTotals,
    required this.catalogDate,
    this.pets = const [],
    this.mastery = 0,
    this.notes = '',
    this.sessionImport,
    this.stableV017Location,
    Map<String, dynamic>? preparationSnapshot,
  }) : preparationSnapshot = preparationSnapshot == null
           ? null
           : immutablePreparationSnapshot(preparationSnapshot);
  final String id,
      methodId,
      methodLabel,
      methodIcon,
      spotId,
      spotName,
      catalogDate;
  final DateTime createdAt;
  final int durationSeconds, mastery;
  final String notes;

  /// The exact location text from a migrated Stable v0.1.7 session.
  ///
  /// Presence marks a history-only legacy record. The old format did not
  /// contain item counts, so it must not enter the modern loot editor or be
  /// represented as a measured zero-item session. An empty string is valid
  /// and distinguishes an omitted legacy location from a current custom one.
  final String? stableV017Location;
  final List<LootEntry> loot;
  final List<Map<String, dynamic>> buffs;
  final List<Map<String, dynamic>> pets;
  final Map<String, double> buffTotals;
  final Map<String, dynamic>? preparationSnapshot;
  final SessionImportMetadata? sessionImport;
  int get totalItems => loot.fold(0, (n, e) => n + e.total);
  Map<String, dynamic> toJson() => {
    'id': id,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'methodId': methodId,
    'methodLabel': methodLabel,
    'methodIcon': methodIcon,
    'spotId': spotId,
    'spotName': spotName,
    'durationSeconds': durationSeconds,
    'mastery': mastery,
    'notes': notes,
    'loot': loot.map((e) => e.toJson()).toList(),
    'buffs': buffs
        .map(
          (b) => {
            'id': b['id'],
            'name': b['name'],
            'category': b['category'],
            'icon': b['icon'],
            'grade': ?itemGrade(b['grade']),
            'effects': objectMap(b['effects']),
            'durationMinutes': b['durationMinutes'],
          },
        )
        .toList(),
    'pets': pets
        .map(
          (pet) => {
            'id': pet['id'],
            'name': pet['name'],
            'icon': pet['icon'],
            'summary': pet['summary'],
          },
        )
        .toList(),
    'buffTotals': buffTotals,
    'catalogDate': catalogDate,
    if (stableV017Location != null) 'stableV017Location': stableV017Location,
    if (preparationSnapshot != null) 'preparationSnapshot': preparationSnapshot,
    if (sessionImport != null) 'sessionImport': sessionImport!.toJson(),
  };
  factory GatheringSession.fromJson(Map<String, dynamic> j) {
    if (j['sessionImport'] != null && j['sessionImport'] is! Map) {
      throw const FormatException('Session contains damaged import metadata.');
    }
    if (j['preparationSnapshot'] != null && j['preparationSnapshot'] is! Map) {
      throw const FormatException('Session contains damaged preparation.');
    }
    if (j['stableV017Location'] != null &&
        (j['stableV017Location'] is! String ||
            (j['stableV017Location'] as String).length > 160)) {
      throw const FormatException(
        'Session contains damaged Stable v0.1.7 provenance.',
      );
    }
    for (final key in ['loot', 'buffs']) {
      if (j[key] is! List || (j[key] as List).any((e) => e is! Map)) {
        throw FormatException('Session contains a damaged $key list.');
      }
    }
    if (j['pets'] != null &&
        (j['pets'] is! List || (j['pets'] as List).any((e) => e is! Map))) {
      throw const FormatException('Session contains a damaged pets list.');
    }
    for (final key in ['id', 'methodId', 'methodLabel', 'spotName']) {
      if (j[key] is! String || (j[key] as String).isEmpty) {
        throw FormatException('Session is missing $key.');
      }
    }
    if (j['buffTotals'] is! Map ||
        objectMap(
          j['buffTotals'],
        ).values.any((v) => v is! num || !v.isFinite)) {
      throw const FormatException('Session contains damaged buff totals.');
    }
    for (final buff in objectList(j['buffs'])) {
      if (buff['effects'] is! Map ||
          objectMap(
            buff['effects'],
          ).values.any((v) => v is! num || !v.isFinite)) {
        throw const FormatException('Session contains damaged buff effects.');
      }
    }
    for (final pet in j['pets'] == null ? const [] : objectList(j['pets'])) {
      if (textOf(pet, 'id').isEmpty || textOf(pet, 'name').isEmpty) {
        throw const FormatException('Session contains an unnamed pet.');
      }
    }
    for (final item in objectList(j['loot'])) {
      if (textOf(item, 'id').isEmpty || textOf(item, 'name').isEmpty) {
        throw const FormatException('Session contains an unnamed item.');
      }
      for (final key in ['start', 'remaining', 'sentAway', 'overrideTotal']) {
        final value = item[key];
        if (value == null && key == 'overrideTotal') continue;
        if (value is! num ||
            !value.isFinite ||
            value < 0 ||
            value != value.roundToDouble()) {
          throw FormatException('Session contains a damaged item $key amount.');
        }
      }
    }
    final duration = j['durationSeconds'];
    if (duration is! num ||
        !duration.isFinite ||
        duration <= 0 ||
        duration > 604800 ||
        duration != duration.roundToDouble()) {
      throw const FormatException('Session contains a damaged duration.');
    }
    return GatheringSession(
      id: textOf(j, 'id'),
      createdAt: DateTime.parse(textOf(j, 'createdAt')),
      methodId: textOf(j, 'methodId'),
      methodLabel: textOf(j, 'methodLabel'),
      methodIcon: textOf(j, 'methodIcon'),
      spotId: textOf(j, 'spotId'),
      spotName: textOf(j, 'spotName'),
      durationSeconds: (j['durationSeconds'] as num).toInt(),
      mastery: (j['mastery'] as num?)?.toInt() ?? 0,
      notes: textOf(j, 'notes'),
      stableV017Location: j['stableV017Location'] as String?,
      loot: objectList(j['loot']).map(LootEntry.fromJson).toList(),
      buffs: objectList(j['buffs']),
      pets: j['pets'] == null ? const [] : objectList(j['pets']),
      buffTotals: objectMap(
        j['buffTotals'],
      ).map((k, v) => MapEntry(k, (v as num).toDouble())),
      catalogDate: textOf(j, 'catalogDate'),
      preparationSnapshot: j['preparationSnapshot'] == null
          ? null
          : objectMap(j['preparationSnapshot']),
      sessionImport: j['sessionImport'] == null
          ? null
          : SessionImportMetadata.fromJson(objectMap(j['sessionImport'])),
    );
  }
}

/// Validated, deeply immutable JSON shared by preparation and logged sessions.
/// No new key is added to historical records that did not have a snapshot.
Map<String, dynamic> immutablePreparationSnapshot(Map<String, dynamic> value) {
  Object? freeze(Object? entry) {
    if (entry == null || entry is String || entry is bool) return entry;
    if (entry is num && entry.isFinite) return entry;
    if (entry is List) return List<Object?>.unmodifiable(entry.map(freeze));
    if (entry is Map && entry.keys.every((key) => key is String)) {
      return Map<String, dynamic>.unmodifiable({
        for (final child in entry.entries)
          child.key as String: freeze(child.value),
      });
    }
    throw const FormatException(
      'Session preparation must contain valid JSON values.',
    );
  }

  return freeze(value)! as Map<String, dynamic>;
}
