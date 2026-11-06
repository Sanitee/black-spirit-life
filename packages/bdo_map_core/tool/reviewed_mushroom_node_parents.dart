/// Exact current PC identity correction. Never infer a parent by proximity.
const reviewedMushroomParentProvenance = <String, Object?>{
  'id': 'reviewed-mushroom-node-parents-2026-11-02',
  'title': 'Two reviewed mushroom-node parent identities',
  'url': 'https://bdocodex.com/us/node/1640/',
  'license': 'Factual reference, no source media copied',
  'permittedUse':
      'Current pages for exact node IDs1640 and1641 and the installed PC snapshot agree:1640 belongs to Weenie Cabin1629,1641 to Looney Cabin1628. Keep node IDs, outputs, quantities and positions; correct display names, parent IDs and reciprocal links only. Other disputed native links are not imported.',
  'attribution': 'BDO Codex; Pearl Abyss Corp.',
};

List<Map<String, Object?>> applyReviewedMushroomNodeParents(
  List<Map<String, Object?>> nodes,
) {
  const changes =
      <
        String,
        ({
          String oldParent,
          String parent,
          String oldName,
          String name,
          List<int> products,
        })
      >{
        '1640': (
          oldParent: '1628',
          parent: '1629',
          oldName: 'Looney Cabin - Grow Mushroom',
          name: 'Weenie Cabin - Grow Mushroom',
          products: [5517, 5520, 1024],
        ),
        '1641': (
          oldParent: '1629',
          parent: '1628',
          oldName: 'Weenie Cabin - Grow Mushroom',
          name: 'Looney Cabin - Grow Mushroom',
          products: [5519, 5521, 1024],
        ),
      };
  Map<String, Object?> exact(String id) {
    final matches = nodes.where((n) => n['id'] == id).toList();
    if (matches.length != 1) {
      throw FormatException('Re-review mushroom node $id.');
    }
    return matches.single;
  }

  bool? alreadyApplied;
  for (final entry in changes.entries) {
    final n = exact(entry.key), c = entry.value;
    final current = n['parentId'] == c.parent;
    final links = n['linkIds'];
    final outputs = n['outputs'];
    if ((alreadyApplied != null && alreadyApplied != current) ||
        n['parentId'] != (current ? c.parent : c.oldParent) ||
        n['name'] != (current ? c.name : c.oldName) ||
        links is! List ||
        links.length != 1 ||
        links.single != n['parentId'] ||
        outputs is! List ||
        outputs.length != c.products.length ||
        !outputs.asMap().entries.every(
          (e) => (e.value as Map)['gameItemId'] == c.products[e.key],
        )) {
      throw FormatException(
        'Re-review mushroom identity and outputs ${entry.key}.',
      );
    }
    alreadyApplied = current;
    final parent = exact(n['parentId']! as String);
    final other = exact(current ? c.oldParent : c.parent);
    if (parent['name'] !=
            (n['parentId'] == '1628' ? 'Looney Cabin' : 'Weenie Cabin') ||
        !(parent['linkIds'] as List).contains(entry.key) ||
        (other['linkIds'] as List).contains(entry.key)) {
      throw FormatException(
        'Re-review reciprocal mushroom links ${entry.key}.',
      );
    }
  }
  if (alreadyApplied!) return nodes;
  return [
    for (final node in nodes)
      if (changes[node['id']] case final correction?)
        {
          ...node,
          'name': correction.name,
          'parentId': correction.parent,
          'linkIds': [correction.parent],
        }
      else if (node['id'] == '1628' || node['id'] == '1629')
        {
          ...node,
          'linkIds': [
            for (final id in node['linkIds']! as List)
              if (id == '1640') '1641' else if (id == '1641') '1640' else id,
          ],
        }
      else
        node,
  ];
}
