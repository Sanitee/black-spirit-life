/// Permanent map correction from the official October 8, 2026 PC update.
/// These were unlinked sea labels, not investable or production nodes.
const octoberSeaNodeCorrection = <String, Object?>{
  'id': 'pearl-abyss-sea-node-correction-2026-10-08',
  'title': 'Official Oceanus Sea and Tiamat Sea node-display correction',
  'url':
      'https://www.naeu.playblackdesert.com/en-US/News/Detail?countryType=en-US&groupContentNo=10678',
  'license': 'Official factual cross-check; no source media copied',
  'permittedUse':
      'The October 8, 2026 PC update corrects Oceanus Sea and Tiamat Sea '
      'being displayed as ordinary world-map nodes. Exclude the two empty, '
      'unlinked exploration records 2113 and 2114 from the older seed. '
      'Retain all production nodes, fishing records and sea-region geometry; '
      'no fishing-origin or distance correction is inferred.',
  'attribution': 'Pearl Abyss Corp.',
};

List<Map<String, Object?>> applyReviewedSeaNodeCorrection(
  List<Map<String, Object?>> nodes,
) {
  const removed = {'2113': 'Oceanus Sea', '2114': 'Tiamat Sea'};
  for (final entry in removed.entries) {
    final matches = nodes.where((node) => node['id'] == entry.key).toList();
    if (matches.length != 1) {
      throw FormatException('Re-review the sea-node seed: ${entry.key}.');
    }
    final node = matches.single;
    if (node['name'] != entry.value ||
        node['nodeType'] != 'Connection' ||
        node['isProductionNode'] != false ||
        node['isResourceNode'] != false ||
        node['contributionPoints'] != 0 ||
        node['parentId'] != null ||
        (node['outputs']! as List).isNotEmpty ||
        (node['linkIds']! as List).isNotEmpty ||
        nodes.any(
          (other) =>
              other['parentId'] == entry.key ||
              (other['linkIds']! as List).contains(entry.key),
        )) {
      throw FormatException(
        'Sea-node ${entry.key} is no longer an empty label.',
      );
    }
  }
  return nodes
      .where((node) => !removed.containsKey(node['id']))
      .toList(growable: false);
}
