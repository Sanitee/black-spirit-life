/// A named game-world node; links are recorded facts, never inferred routes.
class WorldNode {
  const WorldNode({
    required this.id,
    required this.name,
    required this.x,
    required this.z,
    required this.icon,
    this.type = 'Connection',
    this.links = const [],
  });

  factory WorldNode.fromJson(Map<String, dynamic> json) {
    final x = json['x'], z = json['z'];
    final id = json['id']?.toString() ?? '';
    final name = json['name']?.toString() ?? '';
    if (id.isEmpty ||
        name.isEmpty ||
        x is! num ||
        z is! num ||
        !x.isFinite ||
        !z.isFinite) {
      throw const FormatException(
        'A world node is missing verified coordinates or identity.',
      );
    }
    return WorldNode(
      id: id,
      name: name,
      x: x.toDouble(),
      z: z.toDouble(),
      icon: json['icon']?.toString() ?? '',
      type: json['type']?.toString() ?? 'Connection',
      links: List.unmodifiable(
        (json['links'] as List? ?? const []).map((value) => value.toString()),
      ),
    );
  }

  final String id, name, type, icon;
  final double x, z;
  final List<String> links;
  bool get isSettlement => type == 'City' || type == 'Town';
}
