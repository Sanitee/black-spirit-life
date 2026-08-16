import 'map_geometry.dart';
import 'resource_map_data.dart';

/// Factual node-manager guidance for a worker excavation node.
///
/// Manager markers are intentionally available only when [managerLocation]
/// comes from a source that exposes an exact current game-world spawn point.
class BdoExcavationUnlockGuide {
  const BdoExcavationUnlockGuide({
    required this.parentNodeId,
    required this.managerName,
    required this.managerGameNpcId,
    this.managerLocation,
  });

  /// The exploration node that owns the excavation production node.
  final String parentNodeId;

  final String managerName;
  final int managerGameNpcId;

  /// Exact game-world X/Z coordinates, when independently verified.
  ///
  /// A null value must not be replaced with the parent-node coordinate. A node
  /// marker is not necessarily the manager's actual position.
  final BdoWorldPoint? managerLocation;

  bool get canMarkManagerOnMap => managerLocation != null;

  /// Short, deliberately conditional guidance suitable for the map popup.
  ///
  /// Excavation nodes commonly need a manager conversation and Energy, but
  /// the exact requirement and Energy cost are not universal.
  String get unlockInstructions =>
      'If this excavation is hidden, connect and invest in its parent node '
      'first. Then speak to $managerName and check Chat. The Energy cost can '
      'vary by node.';
}

/// Reviewed manager records for every parent of a bundled excavation node.
///
/// See `docs/resource-map/worker-node-unlock-data-provenance.md` before
/// changing these facts or adding a manager marker.
const List<BdoExcavationUnlockGuide> bdoExcavationUnlockGuides =
    <BdoExcavationUnlockGuide>[
      BdoExcavationUnlockGuide(
        parentNodeId: '24',
        managerName: 'Stone Chamber Excavation Lead',
        managerGameNpcId: 50009,
        managerLocation: BdoWorldPoint(-46008.6, 3455),
      ),
      BdoExcavationUnlockGuide(
        parentNodeId: '345',
        managerName: 'Karu',
        managerGameNpcId: 41086,
        managerLocation: BdoWorldPoint(37478.7, -107868),
      ),
      BdoExcavationUnlockGuide(
        parentNodeId: '347',
        managerName: 'Zara Lynch',
        managerGameNpcId: 41093,
        managerLocation: BdoWorldPoint(-17993.4, -38133.4),
      ),
      BdoExcavationUnlockGuide(
        parentNodeId: '638',
        managerName: 'Griffian Bernianto',
        managerGameNpcId: 43449,
        managerLocation: BdoWorldPoint(-229908, 11573.8),
      ),
      BdoExcavationUnlockGuide(
        parentNodeId: '710',
        managerName: 'Kamasylve Priestess Lunia',
        managerGameNpcId: 50454,
        managerLocation: BdoWorldPoint(-251690, -208681),
      ),
      BdoExcavationUnlockGuide(
        parentNodeId: '715',
        managerName: 'Mansha',
        managerGameNpcId: 50459,
        managerLocation: BdoWorldPoint(-376017, -123338),
      ),
      BdoExcavationUnlockGuide(
        parentNodeId: '1156',
        managerName: 'Jamo Hasa',
        managerGameNpcId: 50546,
        managerLocation: BdoWorldPoint(168070, 2585.2),
      ),
      BdoExcavationUnlockGuide(
        parentNodeId: '1324',
        managerName: 'Hazer',
        managerGameNpcId: 50600,
        managerLocation: BdoWorldPoint(462208, 78112),
      ),
      BdoExcavationUnlockGuide(
        parentNodeId: '1332',
        managerName: 'Siriya Min',
        managerGameNpcId: 50620,
        managerLocation: BdoWorldPoint(815342, 278063),
      ),
      BdoExcavationUnlockGuide(
        parentNodeId: '1333',
        managerName: 'Semica',
        managerGameNpcId: 50618,
        managerLocation: BdoWorldPoint(743483, 144494),
      ),
      BdoExcavationUnlockGuide(
        parentNodeId: '1334',
        managerName: 'Samaya',
        managerGameNpcId: 50619,
        managerLocation: BdoWorldPoint(892139, 60953.5),
      ),
      BdoExcavationUnlockGuide(
        parentNodeId: '1335',
        managerName: 'Saimar',
        managerGameNpcId: 50617,
        managerLocation: BdoWorldPoint(822785, -10472.3),
      ),
      BdoExcavationUnlockGuide(
        parentNodeId: '1336',
        managerName: 'Tarik',
        managerGameNpcId: 50621,
        managerLocation: BdoWorldPoint(893017, -61507.7),
      ),
      BdoExcavationUnlockGuide(
        parentNodeId: '1390',
        managerName: 'Salta',
        managerGameNpcId: 50665,
        managerLocation: BdoWorldPoint(1083310, 405019),
      ),
      BdoExcavationUnlockGuide(
        parentNodeId: '1613',
        managerName: 'Voraro',
        managerGameNpcId: 50707,
        managerLocation: BdoWorldPoint(-424965, -322887),
      ),
      BdoExcavationUnlockGuide(
        parentNodeId: '1619',
        managerName: 'Hunnie',
        managerGameNpcId: 50713,
        managerLocation: BdoWorldPoint(-551359, -319416),
      ),
      BdoExcavationUnlockGuide(
        parentNodeId: '1628',
        managerName: 'Looney',
        managerGameNpcId: 45580,
        managerLocation: BdoWorldPoint(-576555, -438540),
      ),
      BdoExcavationUnlockGuide(
        parentNodeId: '1629',
        managerName: 'Weenie',
        managerGameNpcId: 45579,
        managerLocation: BdoWorldPoint(-584288, -375340),
      ),
      BdoExcavationUnlockGuide(
        parentNodeId: '1655',
        managerName: 'Camira',
        managerGameNpcId: 50727,
      ),
      BdoExcavationUnlockGuide(
        parentNodeId: '1656',
        managerName: 'Ominous Altar',
        managerGameNpcId: 50729,
      ),
      BdoExcavationUnlockGuide(
        parentNodeId: '1663',
        managerName: 'Jyarro',
        managerGameNpcId: 50747,
      ),
      BdoExcavationUnlockGuide(
        parentNodeId: '1694',
        managerName: 'Thornwood Goddess Statue',
        managerGameNpcId: 50763,
      ),
      BdoExcavationUnlockGuide(
        parentNodeId: '1704',
        managerName: 'Runaway Monster',
        managerGameNpcId: 50777,
      ),
      BdoExcavationUnlockGuide(
        parentNodeId: '1743',
        managerName: 'Tunn Verdun',
        managerGameNpcId: 50778,
      ),
      BdoExcavationUnlockGuide(
        parentNodeId: '1759',
        managerName: 'Alvaro',
        managerGameNpcId: 50791,
      ),
      BdoExcavationUnlockGuide(
        parentNodeId: '1762',
        managerName: 'Ganzorig',
        managerGameNpcId: 50797,
      ),
      BdoExcavationUnlockGuide(
        parentNodeId: '1763',
        managerName: 'Reina Balacs',
        managerGameNpcId: 50795,
      ),
      BdoExcavationUnlockGuide(
        parentNodeId: '1788',
        managerName: 'Tombkebi',
        managerGameNpcId: 47311,
      ),
      BdoExcavationUnlockGuide(
        parentNodeId: '1789',
        managerName: 'Doaji',
        managerGameNpcId: 47318,
      ),
      BdoExcavationUnlockGuide(
        parentNodeId: '1797',
        managerName: "Tiger Victim's Grave",
        managerGameNpcId: 47364,
      ),
      BdoExcavationUnlockGuide(
        parentNodeId: '1799',
        managerName: "Hwisa's Grave",
        managerGameNpcId: 47365,
      ),
      BdoExcavationUnlockGuide(
        parentNodeId: '1838',
        managerName: 'Ezrin',
        managerGameNpcId: 47442,
      ),
      BdoExcavationUnlockGuide(
        parentNodeId: '1860',
        managerName: 'Hosu',
        managerGameNpcId: 47625,
      ),
      BdoExcavationUnlockGuide(
        parentNodeId: '1870',
        managerName: 'Bonghwang Statue',
        managerGameNpcId: 47636,
      ),
      BdoExcavationUnlockGuide(
        parentNodeId: '2016',
        managerName: 'Dener',
        managerGameNpcId: 47685,
      ),
      BdoExcavationUnlockGuide(
        parentNodeId: '2022',
        managerName: 'Nadir',
        managerGameNpcId: 47700,
      ),
    ];

final Map<String, BdoExcavationUnlockGuide>
_bdoExcavationUnlockGuidesByParentNodeId = <String, BdoExcavationUnlockGuide>{
  for (final guide in bdoExcavationUnlockGuides) guide.parentNodeId: guide,
};

/// Returns reviewed manager guidance for an excavation production node.
///
/// Non-excavation nodes and records without a parent deliberately return null.
BdoExcavationUnlockGuide? bdoExcavationUnlockGuideFor(BdoWorkerNode node) {
  if (!node.isProductionNode || node.nodeType != 'Excavation') {
    return null;
  }
  final parentId = node.parentId;
  if (parentId == null) {
    return null;
  }
  return _bdoExcavationUnlockGuidesByParentNodeId[parentId];
}
