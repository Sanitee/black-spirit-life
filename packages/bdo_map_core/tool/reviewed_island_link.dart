/// Exact named connection added by the official December 1, 2021 PC patch.
/// Not permission to import all retained client waypoint/sea-region adjacency.
const reviewedIslandLinkProvenance = <String, Object?>{
  'id': 'pearl-abyss-lisz-narvo-link-2021-12-01',
  'title': 'Official Lisz Island and Narvo Island connection',
  'url':
      'https://www.naeu.playblackdesert.com/en-US/News/Detail?groupContentNo=2227',
  'license': 'Official factual cross-check; no source media copied',
  'permittedUse':
      'Restore the bidirectional connection between Lisz Island1054 and '
      'Narvo Island1055 explicitly added on December1,2021. Exact names, '
      'positions, costs and connection independently corroborated in current '
      'installed PC data. No new node, output, cost or worker economic value.',
  'attribution': 'Pearl Abyss Corp.',
};

List<Map<String, Object?>> applyReviewedIslandLink(
  List<Map<String, Object?>> nodes,
) {
  const expected = {'1054': 'Lisz Island', '1055': 'Narvo Island'};
  final pair = <String, Map<String, Object?>>{};
  for (final entry in expected.entries) {
    final matches = nodes.where((n) => n['id'] == entry.key).toList();
    if (matches.length != 1) {
      throw FormatException('Re-review island link identity: ${entry.key}.');
    }
    final node = matches.single;
    if (node['name'] != entry.value ||
        node['nodeType'] != 'Connection' ||
        node['isProductionNode'] != false ||
        node['isResourceNode'] != false ||
        node['contributionPoints'] != 1 ||
        (node['outputs']! as List).isNotEmpty) {
      throw FormatException('Island link endpoint changed: ${entry.key}.');
    }
    pair[entry.key] = node;
  }
  final forward = (pair['1054']!['linkIds']! as List).contains('1055');
  final reverse = (pair['1055']!['linkIds']! as List).contains('1054');
  if (forward != reverse) {
    throw const FormatException('Re-review asymmetric Lisz/Narvo seed.');
  }
  return [
    for (final node in nodes)
      if (pair.containsKey(node['id']) && !forward)
        {
          ...node,
          'linkIds': [
            ...(node['linkIds']! as List).cast<String>(),
            node['id'] == '1054' ? '1055' : '1054',
          ]..sort((a, b) => int.parse(a).compareTo(int.parse(b))),
        }
      else
        {...node},
  ];
}
