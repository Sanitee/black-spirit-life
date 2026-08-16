import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'resource_map_chrome_theme.dart';

/// The map concepts that use a recognizable, reusable symbol.
///
/// These symbols intentionally use Flutter's vector icon font and original
/// composition instead of copying Black Desert or third-party map artwork.
enum BdoMapSymbolKind {
  city,
  town,
  gateway,
  connectionNode,
  productionNode,
  residence,
  lodging,
  storage,
  stable,
  shipyard,
  refinery,
  workshop,
}

/// Visual states that may be combined on a [BdoMapSymbol].
///
/// [selected] is a modifier: for example, an owned house may use both
/// [owned] and [selected]. The remaining states describe availability or the
/// reason a house is highlighted.
enum BdoMapSymbolState {
  unowned,
  owned,
  recommendedLodging,
  recommendedPrerequisite,
  selected,
  unavailable,
}

/// The outer silhouette used to distinguish broad map concepts at a glance.
enum BdoMapSymbolShape { circle, roundedSquare, diamond }

/// Immutable metadata for one map symbol.
@immutable
class BdoMapSymbolSpec {
  const BdoMapSymbolSpec({
    required this.icon,
    required this.label,
    required this.shape,
    this.shellScale = 0.82,
    this.iconScale = 0.52,
  });

  final IconData icon;
  final String label;
  final BdoMapSymbolShape shape;
  final double shellScale;
  final double iconScale;
}

/// Resolved colors and geometry for a combination of [BdoMapSymbolState]s.
@immutable
class BdoMapSymbolStyle {
  const BdoMapSymbolStyle({
    required this.foreground,
    required this.background,
    required this.border,
    required this.halo,
    required this.opacity,
    required this.borderWidth,
    required this.haloScale,
    required this.semanticStateLabel,
  });

  final Color foreground;
  final Color background;
  final Color border;
  final Color halo;
  final double opacity;
  final double borderWidth;
  final double haloScale;
  final String semanticStateLabel;
}

/// Returns the familiar map concept represented by [kind].
BdoMapSymbolSpec bdoMapSymbolSpec(BdoMapSymbolKind kind) {
  return switch (kind) {
    BdoMapSymbolKind.city => const BdoMapSymbolSpec(
      icon: Icons.location_city_rounded,
      label: 'City',
      shape: BdoMapSymbolShape.roundedSquare,
      shellScale: 0.94,
      iconScale: 0.58,
    ),
    BdoMapSymbolKind.town => const BdoMapSymbolSpec(
      icon: Icons.holiday_village_rounded,
      label: 'Town',
      shape: BdoMapSymbolShape.roundedSquare,
      shellScale: 0.9,
      iconScale: 0.56,
    ),
    BdoMapSymbolKind.gateway => const BdoMapSymbolSpec(
      icon: Icons.alt_route_rounded,
      label: 'Gateway',
      shape: BdoMapSymbolShape.diamond,
      shellScale: 0.84,
      iconScale: 0.5,
    ),
    BdoMapSymbolKind.connectionNode => const BdoMapSymbolSpec(
      icon: Icons.trip_origin_rounded,
      label: 'Connection node',
      shape: BdoMapSymbolShape.circle,
      shellScale: 0.62,
      iconScale: 0.34,
    ),
    BdoMapSymbolKind.productionNode => const BdoMapSymbolSpec(
      icon: Icons.factory_outlined,
      label: 'Production node',
      shape: BdoMapSymbolShape.circle,
      shellScale: 0.82,
      iconScale: 0.48,
    ),
    BdoMapSymbolKind.residence => const BdoMapSymbolSpec(
      icon: Icons.home_rounded,
      label: 'Residence',
      shape: BdoMapSymbolShape.roundedSquare,
      shellScale: 0.88,
      iconScale: 0.54,
    ),
    BdoMapSymbolKind.lodging => const BdoMapSymbolSpec(
      icon: Icons.bed_rounded,
      label: 'Lodging',
      shape: BdoMapSymbolShape.roundedSquare,
      shellScale: 0.88,
      iconScale: 0.54,
    ),
    BdoMapSymbolKind.storage => const BdoMapSymbolSpec(
      icon: Icons.inventory_2_rounded,
      label: 'Storage',
      shape: BdoMapSymbolShape.roundedSquare,
      shellScale: 0.88,
      iconScale: 0.52,
    ),
    BdoMapSymbolKind.stable => const BdoMapSymbolSpec(
      icon: Icons.pets_rounded,
      label: 'Stable / horse ranch',
      shape: BdoMapSymbolShape.roundedSquare,
      shellScale: 0.88,
      iconScale: 0.52,
    ),
    BdoMapSymbolKind.shipyard => const BdoMapSymbolSpec(
      icon: Icons.sailing_rounded,
      label: 'Shipyard',
      shape: BdoMapSymbolShape.roundedSquare,
      shellScale: 0.88,
      iconScale: 0.52,
    ),
    BdoMapSymbolKind.refinery => const BdoMapSymbolSpec(
      icon: Icons.local_fire_department_rounded,
      label: 'Refinery',
      shape: BdoMapSymbolShape.roundedSquare,
      shellScale: 0.88,
      iconScale: 0.52,
    ),
    BdoMapSymbolKind.workshop => const BdoMapSymbolSpec(
      icon: Icons.handyman_rounded,
      label: 'Workshop',
      shape: BdoMapSymbolShape.roundedSquare,
      shellScale: 0.88,
      iconScale: 0.52,
    ),
  };
}

/// Whether [kind] represents one of the connected town-house services.
///
/// House services use an app-authored gabled silhouette instead of placing a
/// generic Material glyph inside the same square shell as every other map
/// concept. The familiar silhouette keeps dense town views readable without
/// copying Black Desert or third-party marker artwork.
bool bdoMapSymbolUsesHouseSilhouette(BdoMapSymbolKind kind) {
  return switch (kind) {
    BdoMapSymbolKind.residence ||
    BdoMapSymbolKind.lodging ||
    BdoMapSymbolKind.storage ||
    BdoMapSymbolKind.stable ||
    BdoMapSymbolKind.shipyard ||
    BdoMapSymbolKind.refinery ||
    BdoMapSymbolKind.workshop => true,
    _ => false,
  };
}

/// Human-readable state text used by tooltips, legends, and accessibility.
String bdoMapSymbolStateLabel(BdoMapSymbolState state) {
  return switch (state) {
    BdoMapSymbolState.unowned => 'Not owned',
    BdoMapSymbolState.owned => 'Owned',
    BdoMapSymbolState.recommendedLodging => 'Recommended lodging',
    BdoMapSymbolState.recommendedPrerequisite => 'Recommended prerequisite',
    BdoMapSymbolState.selected => 'Selected',
    BdoMapSymbolState.unavailable => 'Unavailable',
  };
}

/// Builds a normalized state set from common house-planning flags.
///
/// Callers may alternatively pass their own state set directly to
/// [BdoMapSymbol].
Set<BdoMapSymbolState> bdoMapSymbolStates({
  bool owned = false,
  bool recommendedLodging = false,
  bool recommendedPrerequisite = false,
  bool selected = false,
  bool unavailable = false,
}) {
  final states = <BdoMapSymbolState>{
    if (owned) BdoMapSymbolState.owned else BdoMapSymbolState.unowned,
    if (recommendedLodging) BdoMapSymbolState.recommendedLodging,
    if (recommendedPrerequisite) BdoMapSymbolState.recommendedPrerequisite,
    if (selected) BdoMapSymbolState.selected,
    if (unavailable) BdoMapSymbolState.unavailable,
  };
  return Set<BdoMapSymbolState>.unmodifiable(states);
}

/// Resolves a coherent visual treatment for one or more symbol states.
///
/// Availability/recommendation colors remain visible when selected; selection
/// adds the bright outer edge and halo. If conflicting base states are passed,
/// unavailable wins, followed by lodging recommendation, prerequisite
/// recommendation, owned, and unowned.
BdoMapSymbolStyle bdoMapSymbolStyle(
  Iterable<BdoMapSymbolState> states, {
  ResourceMapChromeThemeData chromeTheme =
      ResourceMapChromeThemeData.sakuraCartographer,
}) {
  final normalized = states.toSet();
  if (normalized.isEmpty) {
    normalized.add(BdoMapSymbolState.unowned);
  }

  final selected = normalized.contains(BdoMapSymbolState.selected);
  final baseState = switch (normalized) {
    _ when normalized.contains(BdoMapSymbolState.unavailable) =>
      BdoMapSymbolState.unavailable,
    _ when normalized.contains(BdoMapSymbolState.recommendedLodging) =>
      BdoMapSymbolState.recommendedLodging,
    _ when normalized.contains(BdoMapSymbolState.recommendedPrerequisite) =>
      BdoMapSymbolState.recommendedPrerequisite,
    _ when normalized.contains(BdoMapSymbolState.owned) =>
      BdoMapSymbolState.owned,
    _ => BdoMapSymbolState.unowned,
  };

  final base = switch (baseState) {
    BdoMapSymbolState.unowned => const BdoMapSymbolStyle(
      foreground: Color(0xFFD9DFDC),
      background: Color(0xF01A2421),
      border: Color(0xFF73817C),
      halo: Color(0x2473817C),
      opacity: 0.94,
      borderWidth: 1.35,
      haloScale: 1,
      semanticStateLabel: 'Not owned',
    ),
    BdoMapSymbolState.owned => const BdoMapSymbolStyle(
      foreground: Color(0xFF10272B),
      background: Color(0xFF63D4E4),
      border: Color(0xFFD0FAFF),
      halo: Color(0x5263D4E4),
      opacity: 1,
      borderWidth: 1.4,
      haloScale: 1.18,
      semanticStateLabel: 'Owned',
    ),
    BdoMapSymbolState.recommendedLodging => const BdoMapSymbolStyle(
      foreground: Color(0xFF0C291B),
      background: Color(0xFF70DEA2),
      border: Color(0xFFD2FFE4),
      halo: Color(0x5570DEA2),
      opacity: 1,
      borderWidth: 1.5,
      haloScale: 1.18,
      semanticStateLabel: 'Recommended lodging',
    ),
    BdoMapSymbolState.recommendedPrerequisite => const BdoMapSymbolStyle(
      foreground: Color(0xFF2B220B),
      background: Color(0xFFF0C963),
      border: Color(0xFFFFEDB0),
      halo: Color(0x55E8BE60),
      opacity: 1,
      borderWidth: 1.5,
      haloScale: 1.18,
      semanticStateLabel: 'Recommended prerequisite',
    ),
    BdoMapSymbolState.unavailable => const BdoMapSymbolStyle(
      foreground: Color(0xFFA7B0AD),
      background: Color(0xC7161E1C),
      border: Color(0xFF4D5955),
      halo: Color(0x004D5955),
      opacity: 0.56,
      borderWidth: 1,
      haloScale: 1,
      semanticStateLabel: 'Unavailable',
    ),
    BdoMapSymbolState.selected => throw StateError(
      'Selected is a modifier and cannot be a base state.',
    ),
  };

  if (!selected) {
    return base;
  }

  return BdoMapSymbolStyle(
    foreground: base.foreground,
    background: base.background,
    border: chromeTheme.accent,
    halo: chromeTheme.accent.withAlpha(102),
    opacity: base.opacity,
    borderWidth: 2.2,
    haloScale: math.max(base.haloScale, 1.26),
    semanticStateLabel: '${base.semanticStateLabel}, selected',
  );
}

/// A small native Flutter symbol for nodes, settlements, and town houses.
///
/// It is deliberately non-interactive. Wrap it in the caller's button or map
/// marker so the complete marker remains one hit target. [Semantics] still
/// supplies an accessible name and state when the symbol is used as artwork.
class BdoMapSymbol extends StatelessWidget {
  const BdoMapSymbol({
    super.key,
    required this.kind,
    this.states = const {BdoMapSymbolState.unowned},
    this.size = 32,
    this.semanticLabel,
    this.tooltip,
  }) : assert(size > 0);

  final BdoMapSymbolKind kind;
  final Set<BdoMapSymbolState> states;
  final double size;
  final String? semanticLabel;

  /// Optional visible tooltip text. Omit for dense map layers and let the
  /// owning map marker provide one tooltip for its complete hit target.
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final spec = bdoMapSymbolSpec(kind);
    final chromeTheme = ResourceMapChromeTheme.of(context);
    final style = bdoMapSymbolStyle(states, chromeTheme: chromeTheme);
    final selected = states.contains(BdoMapSymbolState.selected);
    final unavailable = states.contains(BdoMapSymbolState.unavailable);
    final label = semanticLabel ?? '${spec.label}; ${style.semanticStateLabel}';

    Widget symbol = SizedBox.square(
      dimension: size,
      child: ExcludeSemantics(
        child: Opacity(
          opacity: style.opacity,
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (style.halo.a > 0)
                Container(
                  width: size * style.haloScale,
                  height: size * style.haloScale,
                  decoration: BoxDecoration(
                    color: style.halo,
                    shape: BoxShape.circle,
                  ),
                ),
              _BdoMapSymbolShell(
                kind: kind,
                spec: spec,
                style: style,
                size: size,
                chromeTheme: chromeTheme,
                selected: selected,
              ),
            ],
          ),
        ),
      ),
    );

    if (tooltip case final tooltipText? when tooltipText.trim().isNotEmpty) {
      symbol = Tooltip(message: tooltipText, child: symbol);
    }

    return Semantics(
      container: true,
      image: true,
      label: label,
      selected: selected,
      enabled: !unavailable,
      child: symbol,
    );
  }
}

class _BdoMapSymbolShell extends StatelessWidget {
  const _BdoMapSymbolShell({
    required this.kind,
    required this.spec,
    required this.style,
    required this.size,
    required this.chromeTheme,
    required this.selected,
  });

  final BdoMapSymbolKind kind;
  final BdoMapSymbolSpec spec;
  final BdoMapSymbolStyle style;
  final double size;
  final ResourceMapChromeThemeData chromeTheme;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    if (bdoMapSymbolUsesHouseSilhouette(kind)) {
      return SizedBox.square(
        dimension: size,
        child: CustomPaint(
          key: ValueKey<String>('bdo-house-silhouette-${kind.name}'),
          painter: BdoHouseMapSymbolPainter(
            kind: kind,
            style: style,
            selected: selected,
          ),
        ),
      );
    }

    final shellSize = size * spec.shellScale;
    final isDiamond = spec.shape == BdoMapSymbolShape.diamond;

    Widget icon = Icon(
      spec.icon,
      color: style.foreground,
      size: size * spec.iconScale,
    );
    if (isDiamond) {
      icon = Transform.rotate(angle: -math.pi / 4, child: icon);
    }

    final shell = Container(
      width: shellSize,
      height: shellSize,
      decoration: BoxDecoration(
        color: style.background,
        shape: spec.shape == BdoMapSymbolShape.circle
            ? BoxShape.circle
            : BoxShape.rectangle,
        borderRadius: spec.shape == BdoMapSymbolShape.circle
            ? null
            : BorderRadius.circular(size * 0.15),
        border: Border.all(color: style.border, width: style.borderWidth),
        boxShadow: [
          BoxShadow(
            color: selected
                ? chromeTheme.selectedShadow.color
                : chromeTheme.idleShadow.color,
            blurRadius: size * 0.15,
            offset: Offset(0, size * 0.07),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: icon,
    );

    if (spec.shape == BdoMapSymbolShape.roundedSquare) {
      final pointerSize = size * .19;
      return SizedBox.square(
        dimension: size,
        child: Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: <Widget>[
            Positioned(
              top: (size - shellSize) / 2 + shellSize - pointerSize * .72,
              child: Transform.rotate(
                angle: math.pi / 4,
                child: Container(
                  width: pointerSize,
                  height: pointerSize,
                  decoration: BoxDecoration(
                    color: style.background,
                    border: Border(
                      right: BorderSide(
                        color: style.border,
                        width: style.borderWidth,
                      ),
                      bottom: BorderSide(
                        color: style.border,
                        width: style.borderWidth,
                      ),
                    ),
                    borderRadius: BorderRadius.circular(size * .025),
                  ),
                ),
              ),
            ),
            Positioned(
              top: (size - shellSize) / 2 - pointerSize * .22,
              child: shell,
            ),
          ],
        ),
      );
    }

    return Transform.rotate(angle: isDiamond ? math.pi / 4 : 0, child: shell);
  }
}

/// Paints the compact house markers used by connected town-property maps.
///
/// The silhouette and the seven service glyphs are original vector geometry.
/// Keeping them in one painter avoids the double-frame look of an icon inside
/// a rounded-square marker and remains inexpensive when a dense city displays
/// hundreds of houses.
class BdoHouseMapSymbolPainter extends CustomPainter {
  const BdoHouseMapSymbolPainter({
    required this.kind,
    required this.style,
    required this.selected,
  }) : assert(
         kind == BdoMapSymbolKind.residence ||
             kind == BdoMapSymbolKind.lodging ||
             kind == BdoMapSymbolKind.storage ||
             kind == BdoMapSymbolKind.stable ||
             kind == BdoMapSymbolKind.shipyard ||
             kind == BdoMapSymbolKind.refinery ||
             kind == BdoMapSymbolKind.workshop,
       );

  final BdoMapSymbolKind kind;
  final BdoMapSymbolStyle style;
  final bool selected;

  Color get serviceAccent => switch (kind) {
    BdoMapSymbolKind.residence => const Color(0xFFEBD294),
    BdoMapSymbolKind.lodging => const Color(0xFF7EE4B2),
    BdoMapSymbolKind.storage => const Color(0xFF78C8EB),
    BdoMapSymbolKind.stable => const Color(0xFFE8B96A),
    BdoMapSymbolKind.shipyard => const Color(0xFF72D5E5),
    BdoMapSymbolKind.refinery => const Color(0xFFF28D70),
    BdoMapSymbolKind.workshop => const Color(0xFFCBA6E5),
    _ => style.foreground,
  };

  @override
  void paint(Canvas canvas, Size size) {
    final width = size.width;
    final height = size.height;
    double x(double value) => width * value;
    double y(double value) => height * value;

    final house = Path()
      ..moveTo(x(.50), y(.035))
      ..lineTo(x(.96), y(.36))
      ..lineTo(x(.85), y(.36))
      ..lineTo(x(.85), y(.92))
      ..quadraticBezierTo(x(.85), y(.955), x(.815), y(.955))
      ..lineTo(x(.185), y(.955))
      ..quadraticBezierTo(x(.15), y(.955), x(.15), y(.92))
      ..lineTo(x(.15), y(.36))
      ..lineTo(x(.04), y(.36))
      ..close();

    canvas.drawShadow(
      house,
      Colors.black.withAlpha(selected ? 190 : 145),
      selected ? 3 : 1.8,
      true,
    );
    canvas.drawPath(
      house,
      Paint()
        ..color = style.background
        ..style = PaintingStyle.fill,
    );

    // A shallow roof plane adds the beveled depth of an in-game map marker
    // while retaining one clean outer frame.
    final roofPlane = Path()
      ..moveTo(x(.50), y(.09))
      ..lineTo(x(.90), y(.37))
      ..lineTo(x(.80), y(.37))
      ..lineTo(x(.50), y(.16))
      ..lineTo(x(.20), y(.37))
      ..lineTo(x(.10), y(.37))
      ..close();
    canvas.drawPath(
      roofPlane,
      Paint()
        ..color = Color.lerp(style.background, style.foreground, .12)!
        ..style = PaintingStyle.fill,
    );

    canvas.drawPath(
      house,
      Paint()
        ..color = style.border
        ..style = PaintingStyle.stroke
        ..strokeWidth = style.borderWidth
        ..strokeJoin = StrokeJoin.round,
    );

    final eave = Paint()
      ..color = serviceAccent.withAlpha(style.opacity < .8 ? 145 : 235)
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.25, width * .055)
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(x(.20), y(.39)), Offset(x(.80), y(.39)), eave);

    final glyph = Paint()
      ..color = style.foreground
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.35, width * .065)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    _paintServiceGlyph(canvas, size, glyph);

    final statusRail = Paint()
      ..color = serviceAccent.withAlpha(style.opacity < .8 ? 135 : 225)
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.15, width * .05)
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(x(.31), y(.875)),
      Offset(x(.69), y(.875)),
      statusRail,
    );
  }

  void _paintServiceGlyph(Canvas canvas, Size size, Paint paint) {
    final width = size.width;
    final height = size.height;
    double x(double value) => width * value;
    double y(double value) => height * value;

    switch (kind) {
      case BdoMapSymbolKind.residence:
        final door = RRect.fromRectAndRadius(
          Rect.fromLTRB(x(.42), y(.51), x(.58), y(.80)),
          Radius.circular(width * .025),
        );
        canvas.drawRRect(door, paint);
        canvas.drawCircle(
          Offset(x(.545), y(.665)),
          math.max(.8, width * .027),
          Paint()..color = paint.color,
        );
        for (final centerX in <double>[.30, .70]) {
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromCenter(
                center: Offset(x(centerX), y(.59)),
                width: x(.12),
                height: y(.12),
              ),
              Radius.circular(width * .02),
            ),
            paint,
          );
        }
      case BdoMapSymbolKind.lodging:
        canvas.drawLine(Offset(x(.28), y(.49)), Offset(x(.28), y(.76)), paint);
        canvas.drawLine(Offset(x(.72), y(.58)), Offset(x(.72), y(.76)), paint);
        canvas.drawLine(Offset(x(.28), y(.72)), Offset(x(.72), y(.72)), paint);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTRB(x(.30), y(.55), x(.71), y(.68)),
            Radius.circular(width * .025),
          ),
          paint,
        );
        canvas.drawLine(Offset(x(.37), y(.56)), Offset(x(.37), y(.67)), paint);
      case BdoMapSymbolKind.storage:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTRB(x(.27), y(.51), x(.73), y(.76)),
            Radius.circular(width * .035),
          ),
          paint,
        );
        canvas.drawLine(Offset(x(.28), y(.59)), Offset(x(.72), y(.59)), paint);
        canvas.drawLine(Offset(x(.45), y(.62)), Offset(x(.55), y(.62)), paint);
      case BdoMapSymbolKind.stable:
        final horseshoe = Path()
          ..moveTo(x(.32), y(.49))
          ..lineTo(x(.32), y(.58))
          ..cubicTo(x(.32), y(.77), x(.68), y(.77), x(.68), y(.58))
          ..lineTo(x(.68), y(.49));
        canvas.drawPath(horseshoe, paint);
        canvas.drawLine(Offset(x(.27), y(.49)), Offset(x(.37), y(.49)), paint);
        canvas.drawLine(Offset(x(.63), y(.49)), Offset(x(.73), y(.49)), paint);
      case BdoMapSymbolKind.shipyard:
        canvas.drawLine(Offset(x(.50), y(.45)), Offset(x(.50), y(.67)), paint);
        final sail = Path()
          ..moveTo(x(.47), y(.47))
          ..lineTo(x(.47), y(.63))
          ..lineTo(x(.30), y(.63))
          ..close();
        canvas.drawPath(sail, paint);
        final hull = Path()
          ..moveTo(x(.27), y(.67))
          ..quadraticBezierTo(x(.50), y(.80), x(.73), y(.67));
        canvas.drawPath(hull, paint);
        canvas.drawLine(Offset(x(.34), y(.79)), Offset(x(.66), y(.79)), paint);
      case BdoMapSymbolKind.refinery:
        final flame = Path()
          ..moveTo(x(.53), y(.43))
          ..cubicTo(x(.43), y(.52), x(.39), y(.59), x(.42), y(.67))
          ..cubicTo(x(.47), y(.80), x(.66), y(.77), x(.66), y(.63))
          ..cubicTo(x(.66), y(.55), x(.61), y(.50), x(.58), y(.46))
          ..cubicTo(x(.58), y(.57), x(.51), y(.57), x(.53), y(.43))
          ..close();
        canvas.drawPath(flame, paint..style = PaintingStyle.fill);
      case BdoMapSymbolKind.workshop:
        canvas.save();
        canvas.translate(x(.50), y(.62));
        canvas.rotate(-math.pi / 4);
        canvas.drawLine(Offset(0, -y(.12)), Offset(0, y(.17)), paint);
        canvas.drawLine(
          Offset(-x(.11), -y(.12)),
          Offset(x(.11), -y(.12)),
          paint,
        );
        canvas.restore();
        canvas.drawLine(Offset(x(.36), y(.50)), Offset(x(.65), y(.75)), paint);
      default:
        break;
    }
  }

  @override
  bool shouldRepaint(BdoHouseMapSymbolPainter oldDelegate) {
    return oldDelegate.kind != kind ||
        oldDelegate.selected != selected ||
        oldDelegate.style.foreground != style.foreground ||
        oldDelegate.style.background != style.background ||
        oldDelegate.style.border != style.border ||
        oldDelegate.style.opacity != style.opacity ||
        oldDelegate.style.borderWidth != style.borderWidth;
  }
}
