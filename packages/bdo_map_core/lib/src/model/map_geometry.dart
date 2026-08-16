import 'dart:math' as math;
import 'dart:ui';

/// A point in Black Desert's canonical game-world X/Z coordinate system.
///
/// Data remains in this representation so basemap providers can be changed
/// without rewriting resource coordinates.
class BdoWorldPoint {
  const BdoWorldPoint(this.x, this.z);

  final double x;
  final double z;

  /// Converts game X/Z into the Cartesian map plane used by tile providers.
  BdoMapPoint get mapPoint => BdoMapPoint(x, -z);

  factory BdoWorldPoint.fromJson(Map<String, Object?> json) {
    return BdoWorldPoint(
      (json['x']! as num).toDouble(),
      (json['z']! as num).toDouble(),
    );
  }

  Map<String, double> toJson() => <String, double>{'x': x, 'z': z};

  @override
  bool operator ==(Object other) =>
      other is BdoWorldPoint && other.x == x && other.z == z;

  @override
  int get hashCode => Object.hash(x, z);

  @override
  String toString() => 'BdoWorldPoint($x, $z)';
}

/// A Cartesian point in the map plane. Positive Y points down on screen.
class BdoMapPoint {
  const BdoMapPoint(this.x, this.y);

  static const zero = BdoMapPoint(0, 0);

  final double x;
  final double y;

  Offset get offset => Offset(x, y);
  BdoWorldPoint get worldPoint => BdoWorldPoint(x, -y);

  BdoMapPoint translate(double dx, double dy) => BdoMapPoint(x + dx, y + dy);

  double distanceTo(BdoMapPoint other) {
    return math.sqrt(
      math.pow(other.x - x, 2).toDouble() + math.pow(other.y - y, 2).toDouble(),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is BdoMapPoint && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);

  @override
  String toString() => 'BdoMapPoint($x, $y)';
}

class BdoMapBounds {
  const BdoMapBounds({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  }) : assert(right > left),
       assert(bottom > top);

  final double left;
  final double top;
  final double right;
  final double bottom;

  double get width => right - left;
  double get height => bottom - top;
  BdoMapPoint get center => BdoMapPoint(left + width / 2, top + height / 2);

  bool contains(BdoMapPoint point) {
    return point.x >= left &&
        point.x <= right &&
        point.y >= top &&
        point.y <= bottom;
  }

  bool intersects(BdoMapBounds other) {
    return left <= other.right &&
        right >= other.left &&
        top <= other.bottom &&
        bottom >= other.top;
  }

  BdoMapBounds inflate(double amount) => BdoMapBounds(
    left: left - amount,
    top: top - amount,
    right: right + amount,
    bottom: bottom + amount,
  );

  @override
  String toString() => 'BdoMapBounds($left, $top, $right, $bottom)';
}
