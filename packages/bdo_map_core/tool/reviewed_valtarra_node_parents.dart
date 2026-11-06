/// June 4 PC production-node table, corroborated by exact current node IDs.
const reviewedValtarraParentProvenance = <String, Object?>{
  'id': 'pearl-abyss-valtarra-node-parents-2026-11-03',
  'title': 'Valtarra Mountains mining parent correction',
  'url':
      'https://blackdesert.pearlabyss.com/Asia/en-US/News/Notice/Detail?_boardNo=13267',
  'license': 'Factual reference, no source media copied',
  'permittedUse':
      'The official June 4, 2026 PC production-node table places both Noc Ore mining nodes at Valtarra Mountains, not the Altar of Training. Current installed PC node IDs2065/2066 independently link to1611 with matching Powder of Time/Earth outputs. Only names, parents and reciprocal links are corrected; IDs, costs, outputs, coordinates and saved references are retained. This is not a blanket import of disputed native links.',
  'attribution': 'Pearl Abyss Corp.',
};

List<Map<String, Object?>> applyReviewedValtarraNodeParents(
  List<Map<String, Object?>> nodes,
) {
  Map<String, Object?> exact(String id) {
    final matches = nodes.where((n) => n['id'] == id).toList();
    if (matches.length != 1) {
      throw FormatException('Re-review Valtarra node $id.');
    }
    return matches.single;
  }

  final mountain = exact('1611'), altar = exact('1612');
  if (mountain['name'] != 'Valtarra Mountains' ||
      altar['name'] != 'Valtarra - Altar of Training') {
    throw const FormatException('Re-review Valtarra parent identities.');
  }
  bool? applied;
  for (final id in ['2065', '2066']) {
    final n = exact(id), current = n['parentId'] == '1611';
    final parent = current ? mountain : altar,
        other = current ? altar : mountain;
    final outputs = n['outputs'], links = n['linkIds'];
    final products = [4011, id == '2065' ? 4805 : 4804, 1025];
    if ((applied != null && applied != current) ||
        n['parentId'] != (current ? '1611' : '1612') ||
        n['name'] != '${parent['name']} - Mining' ||
        links is! List ||
        links.length != 1 ||
        links.single != n['parentId'] ||
        outputs is! List ||
        outputs.length != products.length ||
        !outputs.asMap().entries.every(
          (e) => (e.value as Map)['gameItemId'] == products[e.key],
        ) ||
        !(parent['linkIds'] as List).contains(id) ||
        (other['linkIds'] as List).contains(id)) {
      throw FormatException(
        'Re-review Valtarra identity, outputs and links $id.',
      );
    }
    applied = current;
  }
  if (applied!) return nodes;
  return [
    for (final n in nodes)
      if (n['id'] == '2065' || n['id'] == '2066')
        {
          ...n,
          'name': 'Valtarra Mountains - Mining',
          'parentId': '1611',
          'linkIds': ['1611'],
        }
      else if (n['id'] == '1611')
        {
          ...n,
          'linkIds': [...n['linkIds']! as List, '2065', '2066'],
        }
      else if (n['id'] == '1612')
        {
          ...n,
          'linkIds': [
            for (final id in n['linkIds']! as List)
              if (id != '2065' && id != '2066') id,
          ],
        }
      else
        n,
  ];
}
