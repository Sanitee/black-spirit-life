import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The gathering method represented by a compact map or material-list glyph.
enum BdoGatheringToolKind {
  bareHands,
  hoe,
  fluidCollector,
  lumberingAxe,
  pickaxe,
  butcherKnife,
  tanningKnife,
  combat,
  huntingMatchlock,
  sniperRifle,
  unknown,
}

/// How multiple tools in a gathering method relate to one another.
enum BdoGatheringToolRelation { single, alternative, requiredTogether }

/// Builds the in-game item artwork for one normalized gathering tool.
///
/// [canonicalItemName] is a catalog-facing name, not the serialized method
/// string. Callers can therefore reuse their existing item-artwork resolver
/// without teaching it about combined values such as
/// `Sniper Rifle + Butcher Knife`.
typedef BdoGatheringToolArtworkBuilder =
    Widget Function(
      BuildContext context,
      BdoGatheringToolKind tool,
      String canonicalItemName,
      double size,
    );

/// The normalized tools represented by a serialized `BdoFieldProduct.tool`.
@immutable
class BdoGatheringToolSelection {
  const BdoGatheringToolSelection({
    required this.tools,
    required this.relation,
  });

  final List<BdoGatheringToolKind> tools;
  final BdoGatheringToolRelation relation;

  /// A concise, player-facing description suitable for tooltips.
  String get displayLabel {
    final labels = tools.map(bdoGatheringToolLabel).toList(growable: false);
    return switch (relation) {
      BdoGatheringToolRelation.single => labels.single,
      BdoGatheringToolRelation.alternative => labels.join(' or '),
      BdoGatheringToolRelation.requiredTogether => labels.join(' and '),
    };
  }
}

/// Returns the player-facing name for a normalized gathering tool.
String bdoGatheringToolLabel(BdoGatheringToolKind tool) {
  return switch (tool) {
    BdoGatheringToolKind.bareHands => 'Bare hands',
    BdoGatheringToolKind.hoe => 'Hoe',
    BdoGatheringToolKind.fluidCollector => 'Fluid Collector',
    BdoGatheringToolKind.lumberingAxe => 'Lumbering Axe',
    BdoGatheringToolKind.pickaxe => 'Pickaxe',
    BdoGatheringToolKind.butcherKnife => 'Butcher Knife',
    BdoGatheringToolKind.tanningKnife => 'Tanning Knife',
    BdoGatheringToolKind.combat => 'Combat',
    BdoGatheringToolKind.huntingMatchlock => 'Hunting Matchlock',
    BdoGatheringToolKind.sniperRifle => 'Sniper Rifle',
    BdoGatheringToolKind.unknown => 'Unknown tool',
  };
}

/// Returns the ordinary catalog item used to illustrate [tool].
///
/// Bare hands and combat deliberately have no pretend tool item. Unknown
/// future methods also retain the visible vector fallback instead of resolving
/// unrelated artwork.
String? bdoGatheringToolCatalogItemName(BdoGatheringToolKind tool) {
  return switch (tool) {
    BdoGatheringToolKind.hoe => 'Hoe',
    BdoGatheringToolKind.fluidCollector => 'Fluid Collector',
    BdoGatheringToolKind.lumberingAxe => 'Lumbering Axe',
    BdoGatheringToolKind.pickaxe => 'Pickaxe',
    BdoGatheringToolKind.butcherKnife => 'Butcher Knife',
    BdoGatheringToolKind.tanningKnife => 'Tanning Knife',
    BdoGatheringToolKind.huntingMatchlock => 'Hunting Matchlock',
    BdoGatheringToolKind.sniperRifle => '[Hunting] Sniper Rifle',
    BdoGatheringToolKind.bareHands ||
    BdoGatheringToolKind.combat ||
    BdoGatheringToolKind.unknown => null,
  };
}

/// The package that owns the reviewed, locally bundled gathering-tool art.
const String bdoGatheringToolAssetPackage = 'bdo_map_core';

/// Returns the frame-free local artwork used for a real gathering tool.
///
/// Bare hands and combat intentionally remain code-drawn concepts rather than
/// pretending to be inventory items. Unknown future methods also retain the
/// visible vector fallback.
String? bdoGatheringToolAssetPath(BdoGatheringToolKind tool) {
  const assetDirectory = 'assets/images/gathering_tools';
  return switch (tool) {
    BdoGatheringToolKind.hoe => '$assetDirectory/hoe.webp',
    BdoGatheringToolKind.fluidCollector =>
      '$assetDirectory/fluid_collector.webp',
    BdoGatheringToolKind.lumberingAxe => '$assetDirectory/lumbering_axe.webp',
    BdoGatheringToolKind.pickaxe => '$assetDirectory/pickaxe.webp',
    BdoGatheringToolKind.butcherKnife => '$assetDirectory/butcher_knife.webp',
    BdoGatheringToolKind.tanningKnife => '$assetDirectory/tanning_knife.webp',
    BdoGatheringToolKind.huntingMatchlock =>
      '$assetDirectory/hunting_matchlock.webp',
    BdoGatheringToolKind.sniperRifle => '$assetDirectory/sniper_rifle.webp',
    BdoGatheringToolKind.bareHands ||
    BdoGatheringToolKind.combat ||
    BdoGatheringToolKind.unknown => null,
  };
}

/// Supplies app-owned, canonical item artwork to gathering-tool indicators.
///
/// The map package still has a complete code-drawn fallback, so standalone
/// consumers and tests do not need an item catalog. Applications that already
/// resolve BDO item icons can wrap the map once instead of threading a builder
/// through every material card.
class BdoGatheringToolArtworkScope extends InheritedWidget {
  const BdoGatheringToolArtworkScope({
    required this.builder,
    required super.child,
    super.key,
  });

  final BdoGatheringToolArtworkBuilder builder;

  static BdoGatheringToolArtworkBuilder? maybeOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<BdoGatheringToolArtworkScope>()
          ?.builder;

  @override
  bool updateShouldNotify(BdoGatheringToolArtworkScope oldWidget) =>
      oldWidget.builder != builder;
}

/// Normalizes every gathering-tool value currently used by map field products.
///
/// The serialized data remains unchanged. Unknown future values deliberately
/// resolve to a visible fallback instead of dropping the tool indicator.
BdoGatheringToolSelection resolveBdoGatheringTools(String rawTool) {
  final normalized = rawTool
      .trim()
      .replaceAll(RegExp(r'\s+'), ' ')
      .toLowerCase();

  return switch (normalized) {
    'bare hands / hoe' ||
    'bare hands or hoe' => const BdoGatheringToolSelection(
      tools: <BdoGatheringToolKind>[
        BdoGatheringToolKind.bareHands,
        BdoGatheringToolKind.hoe,
      ],
      relation: BdoGatheringToolRelation.alternative,
    ),
    'butcher knife' => const BdoGatheringToolSelection(
      tools: <BdoGatheringToolKind>[BdoGatheringToolKind.butcherKnife],
      relation: BdoGatheringToolRelation.single,
    ),
    'combat' => const BdoGatheringToolSelection(
      tools: <BdoGatheringToolKind>[BdoGatheringToolKind.combat],
      relation: BdoGatheringToolRelation.single,
    ),
    'fluid collector' => const BdoGatheringToolSelection(
      tools: <BdoGatheringToolKind>[BdoGatheringToolKind.fluidCollector],
      relation: BdoGatheringToolRelation.single,
    ),
    'hoe' => const BdoGatheringToolSelection(
      tools: <BdoGatheringToolKind>[BdoGatheringToolKind.hoe],
      relation: BdoGatheringToolRelation.single,
    ),
    'hunting matchlock and butcher knife' => const BdoGatheringToolSelection(
      tools: <BdoGatheringToolKind>[
        BdoGatheringToolKind.huntingMatchlock,
        BdoGatheringToolKind.butcherKnife,
      ],
      relation: BdoGatheringToolRelation.requiredTogether,
    ),
    'hunting matchlock' => const BdoGatheringToolSelection(
      tools: <BdoGatheringToolKind>[BdoGatheringToolKind.huntingMatchlock],
      relation: BdoGatheringToolRelation.single,
    ),
    'lumbering axe' => const BdoGatheringToolSelection(
      tools: <BdoGatheringToolKind>[BdoGatheringToolKind.lumberingAxe],
      relation: BdoGatheringToolRelation.single,
    ),
    'pickaxe' => const BdoGatheringToolSelection(
      tools: <BdoGatheringToolKind>[BdoGatheringToolKind.pickaxe],
      relation: BdoGatheringToolRelation.single,
    ),
    'sniper rifle + butcher knife' => const BdoGatheringToolSelection(
      tools: <BdoGatheringToolKind>[
        BdoGatheringToolKind.sniperRifle,
        BdoGatheringToolKind.butcherKnife,
      ],
      relation: BdoGatheringToolRelation.requiredTogether,
    ),
    'sniper rifle' ||
    '[hunting] sniper rifle' => const BdoGatheringToolSelection(
      tools: <BdoGatheringToolKind>[BdoGatheringToolKind.sniperRifle],
      relation: BdoGatheringToolRelation.single,
    ),
    'tanning knife' => const BdoGatheringToolSelection(
      tools: <BdoGatheringToolKind>[BdoGatheringToolKind.tanningKnife],
      relation: BdoGatheringToolRelation.single,
    ),
    _ => const BdoGatheringToolSelection(
      tools: <BdoGatheringToolKind>[BdoGatheringToolKind.unknown],
      relation: BdoGatheringToolRelation.single,
    ),
  };
}

/// A compact, frame-free gathering-tool indicator.
///
/// It is intentionally non-interactive so a whole material row can remain one
/// clear hit target. Real tools use reviewed local game artwork by default;
/// hands, combat, unknown methods, and failed asset loads keep a code-drawn
/// fallback. The owning row may override fallback [color] through [IconTheme].
class BdoGatheringToolIcon extends StatelessWidget {
  const BdoGatheringToolIcon({
    super.key,
    required this.tool,
    this.size = 20,
    this.color,
    this.artworkBuilder,
  }) : assert(size > 0);

  /// The unmodified `BdoFieldProduct.tool` value.
  final String tool;
  final double size;
  final Color? color;
  final BdoGatheringToolArtworkBuilder? artworkBuilder;

  @override
  Widget build(BuildContext context) {
    final selection = resolveBdoGatheringTools(tool);
    final effectiveColor =
        color ??
        IconTheme.of(context).color ??
        Theme.of(context).colorScheme.onSurface;
    final effectiveArtworkBuilder =
        artworkBuilder ?? BdoGatheringToolArtworkScope.maybeOf(context);
    final separatorWidth = math.max(10.0, size * .5);
    final width = selection.tools.length == 1
        ? size
        : (size * selection.tools.length) +
              (separatorWidth * (selection.tools.length - 1));
    final semanticPrefix = selection.tools.length == 1
        ? 'Required tool'
        : 'Required tools';

    final glyph = SizedBox(
      width: width,
      height: size,
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            for (var index = 0; index < selection.tools.length; index += 1) ...[
              if (index > 0)
                SizedBox(
                  key: ValueKey<String>(
                    'bdo-gathering-tool-separator-${selection.relation.name}',
                  ),
                  width: separatorWidth,
                  child: Center(
                    child: Text(
                      selection.relation == BdoGatheringToolRelation.alternative
                          ? '/'
                          : '+',
                      style: TextStyle(
                        color: effectiveColor,
                        fontSize: math.max(10.0, size * .55),
                        height: 1,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
              _buildToolArtwork(
                context,
                tool: selection.tools[index],
                size: size,
                color: effectiveColor,
                artworkBuilder: effectiveArtworkBuilder,
              ),
            ],
          ],
        ),
      ),
    );

    return Semantics(
      container: true,
      image: true,
      label: '$semanticPrefix: ${selection.displayLabel}',
      child: Tooltip(
        message: selection.displayLabel,
        excludeFromSemantics: true,
        child: glyph,
      ),
    );
  }

  Widget _buildToolArtwork(
    BuildContext context, {
    required BdoGatheringToolKind tool,
    required double size,
    required Color color,
    required BdoGatheringToolArtworkBuilder? artworkBuilder,
  }) {
    final canonicalItemName = bdoGatheringToolCatalogItemName(tool);
    if (artworkBuilder != null && canonicalItemName != null) {
      return SizedBox.square(
        dimension: size,
        child: artworkBuilder(context, tool, canonicalItemName, size),
      );
    }
    final assetPath = bdoGatheringToolAssetPath(tool);
    if (assetPath != null) {
      return SizedBox.square(
        dimension: size,
        child: Image.asset(
          assetPath,
          key: ValueKey<String>('bdo-gathering-tool-artwork-${tool.name}'),
          package: bdoGatheringToolAssetPackage,
          width: size,
          height: size,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.medium,
          gaplessPlayback: true,
          excludeFromSemantics: true,
          errorBuilder: (context, error, stackTrace) => CustomPaint(
            painter: _BdoGatheringToolPainter(
              selection: BdoGatheringToolSelection(
                tools: <BdoGatheringToolKind>[tool],
                relation: BdoGatheringToolRelation.single,
              ),
              color: color,
            ),
          ),
        ),
      );
    }
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _BdoGatheringToolPainter(
          selection: BdoGatheringToolSelection(
            tools: <BdoGatheringToolKind>[tool],
            relation: BdoGatheringToolRelation.single,
          ),
          color: color,
        ),
      ),
    );
  }
}

class _BdoGatheringToolPainter extends CustomPainter {
  const _BdoGatheringToolPainter({
    required this.selection,
    required this.color,
  });

  final BdoGatheringToolSelection selection;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (selection.tools.length == 1) {
      _drawGlyph(canvas, Offset.zero & size, selection.tools.single);
      return;
    }

    final glyphSize = size.height * .76;
    final top = (size.height - glyphSize) / 2;
    _drawGlyph(
      canvas,
      Rect.fromLTWH(0, top, glyphSize, glyphSize),
      selection.tools.first,
    );
    _drawGlyph(
      canvas,
      Rect.fromLTWH(size.width - glyphSize, top, glyphSize, glyphSize),
      selection.tools.last,
    );

    final separatorPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1, size.height * .075)
      ..strokeCap = StrokeCap.round;
    final center = size.center(Offset.zero);
    final half = size.height * .11;
    if (selection.relation == BdoGatheringToolRelation.alternative) {
      canvas.drawLine(
        Offset(center.dx - half * .65, center.dy + half),
        Offset(center.dx + half * .65, center.dy - half),
        separatorPaint,
      );
    } else {
      canvas.drawLine(
        Offset(center.dx - half, center.dy),
        Offset(center.dx + half, center.dy),
        separatorPaint,
      );
      canvas.drawLine(
        Offset(center.dx, center.dy - half),
        Offset(center.dx, center.dy + half),
        separatorPaint,
      );
    }
  }

  void _drawGlyph(Canvas canvas, Rect rect, BdoGatheringToolKind kind) {
    canvas.save();
    canvas.translate(rect.left, rect.top);
    canvas.scale(rect.width / 24, rect.height / 24);

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    switch (kind) {
      case BdoGatheringToolKind.bareHands:
        _drawBareHands(canvas, paint);
      case BdoGatheringToolKind.hoe:
        _drawHoe(canvas, paint);
      case BdoGatheringToolKind.fluidCollector:
        _drawFluidCollector(canvas, paint);
      case BdoGatheringToolKind.lumberingAxe:
        _drawLumberingAxe(canvas, paint);
      case BdoGatheringToolKind.pickaxe:
        _drawPickaxe(canvas, paint);
      case BdoGatheringToolKind.butcherKnife:
        _drawButcherKnife(canvas, paint);
      case BdoGatheringToolKind.tanningKnife:
        _drawTanningKnife(canvas, paint);
      case BdoGatheringToolKind.combat:
        _drawCombat(canvas, paint);
      case BdoGatheringToolKind.huntingMatchlock:
        _drawMatchlock(canvas, paint);
      case BdoGatheringToolKind.sniperRifle:
        _drawSniperRifle(canvas, paint);
      case BdoGatheringToolKind.unknown:
        _drawUnknown(canvas, paint);
    }

    canvas.restore();
  }

  void _drawBareHands(Canvas canvas, Paint paint) {
    final hand = Path()
      ..moveTo(8.2, 21)
      ..cubicTo(6.4, 18.4, 5.2, 15.9, 4.2, 13.2)
      ..cubicTo(3.8, 12.1, 4.2, 11.1, 5.1, 10.8)
      ..cubicTo(6.1, 10.5, 7, 12.3, 7.7, 13.2)
      ..lineTo(7.7, 6.4)
      ..cubicTo(7.7, 5.3, 8.4, 4.7, 9.3, 4.7)
      ..cubicTo(10.2, 4.7, 10.7, 5.4, 10.7, 6.3)
      ..lineTo(10.7, 11.1)
      ..lineTo(10.7, 4.7)
      ..cubicTo(10.7, 3.7, 11.4, 3.1, 12.2, 3.1)
      ..cubicTo(13.1, 3.1, 13.7, 3.8, 13.7, 4.7)
      ..lineTo(13.7, 11)
      ..lineTo(13.7, 5.3)
      ..cubicTo(13.7, 4.4, 14.4, 3.8, 15.2, 3.8)
      ..cubicTo(16.1, 3.8, 16.7, 4.5, 16.7, 5.4)
      ..lineTo(16.7, 11.8)
      ..lineTo(16.7, 7)
      ..cubicTo(16.7, 6.1, 17.4, 5.5, 18.2, 5.5)
      ..cubicTo(19.1, 5.5, 19.7, 6.2, 19.7, 7.1)
      ..lineTo(19.7, 14.2)
      ..cubicTo(19.7, 18.4, 17.1, 21, 13.3, 21)
      ..close();
    canvas.drawPath(hand, paint);
  }

  void _drawHoe(Canvas canvas, Paint paint) {
    canvas.drawLine(const Offset(6, 21), const Offset(16.2, 5.3), paint);
    final head = Path()
      ..moveTo(12.8, 4.1)
      ..lineTo(20.8, 7.3)
      ..cubicTo(19.5, 9.6, 17.1, 10.6, 14.8, 9.7);
    canvas.drawPath(head, paint);
    canvas.drawLine(const Offset(5.2, 21), const Offset(7.2, 21), paint);
  }

  void _drawFluidCollector(Canvas canvas, Paint paint) {
    final body = Path()
      ..moveTo(5.2, 14.2)
      ..lineTo(12.8, 6.6)
      ..lineTo(17.4, 11.2)
      ..lineTo(9.8, 18.8)
      ..close();
    canvas.drawPath(body, paint);
    canvas.drawLine(const Offset(12.2, 7.2), const Offset(9.8, 4.8), paint);
    canvas.drawLine(const Offset(8.5, 4.2), const Offset(11, 6.7), paint);
    canvas.drawLine(const Offset(10, 18.5), const Offset(7, 21.5), paint);
    canvas.drawLine(const Offset(6.2, 20.7), const Offset(7.8, 22.3), paint);
    final drop = Path()
      ..moveTo(18.2, 14.1)
      ..cubicTo(16.8, 16.1, 16.2, 17, 16.2, 18.1)
      ..cubicTo(16.2, 19.6, 17.2, 20.6, 18.5, 20.6)
      ..cubicTo(19.9, 20.6, 20.8, 19.6, 20.8, 18.2)
      ..cubicTo(20.8, 17.1, 20.1, 16, 18.2, 14.1);
    canvas.drawPath(drop, paint);
  }

  void _drawLumberingAxe(Canvas canvas, Paint paint) {
    canvas.drawLine(const Offset(10, 21), const Offset(13.8, 7.8), paint);
    final head = Path()
      ..moveTo(8.8, 4.2)
      ..cubicTo(12, 3.3, 16.2, 4.4, 19.7, 6.7)
      ..cubicTo(18.6, 10.2, 16.7, 12.4, 13.6, 13.4)
      ..lineTo(12.4, 8.4)
      ..cubicTo(10.9, 7.7, 9.7, 6.3, 8.8, 4.2)
      ..close();
    canvas.drawPath(head, paint);
    canvas.drawLine(const Offset(9.2, 21), const Offset(11, 21), paint);
  }

  void _drawPickaxe(Canvas canvas, Paint paint) {
    canvas.drawLine(const Offset(12, 7.7), const Offset(12, 21), paint);
    final head = Path()
      ..moveTo(3.1, 10.2)
      ..cubicTo(7.6, 5.2, 16.4, 5.2, 20.9, 10.2)
      ..cubicTo(16.9, 8.4, 7.1, 8.4, 3.1, 10.2);
    canvas.drawPath(head, paint);
    canvas.drawLine(const Offset(11.1, 21), const Offset(12.9, 21), paint);
  }

  void _drawButcherKnife(Canvas canvas, Paint paint) {
    final blade = Path()
      ..moveTo(5, 4.2)
      ..lineTo(19.8, 4.2)
      ..lineTo(19.8, 13.8)
      ..cubicTo(14.9, 13.6, 11.6, 12.4, 8.8, 10.3)
      ..lineTo(5, 10.3)
      ..close();
    canvas.drawPath(blade, paint);
    canvas.drawCircle(const Offset(17.1, 7.1), 1.1, paint);
    final handle = Path()
      ..moveTo(5, 9.1)
      ..lineTo(5, 19.8)
      ..lineTo(8.8, 19.8)
      ..lineTo(8.8, 10.3);
    canvas.drawPath(handle, paint);
  }

  void _drawTanningKnife(Canvas canvas, Paint paint) {
    final blade = Path()
      ..moveTo(5.6, 8.8)
      ..cubicTo(8.9, 13.4, 15.1, 13.4, 18.4, 8.8)
      ..cubicTo(15, 11.1, 9, 11.1, 5.6, 8.8);
    canvas.drawPath(blade, paint);
    canvas.drawLine(const Offset(5.6, 8.8), const Offset(3.5, 6.6), paint);
    canvas.drawLine(const Offset(18.4, 8.8), const Offset(20.5, 6.6), paint);
    canvas.drawLine(const Offset(3.5, 5.4), const Offset(3.5, 8), paint);
    canvas.drawLine(const Offset(20.5, 5.4), const Offset(20.5, 8), paint);
  }

  void _drawCombat(Canvas canvas, Paint paint) {
    canvas.drawLine(const Offset(5, 4.2), const Offset(18.8, 18), paint);
    canvas.drawLine(const Offset(19, 4.2), const Offset(5.2, 18), paint);
    canvas.drawLine(const Offset(4.2, 15.4), const Offset(8, 19.2), paint);
    canvas.drawLine(const Offset(16, 19.2), const Offset(19.8, 15.4), paint);
    canvas.drawLine(const Offset(4.1, 19.1), const Offset(5.9, 20.9), paint);
    canvas.drawLine(const Offset(18.1, 20.9), const Offset(19.9, 19.1), paint);
  }

  void _drawMatchlock(Canvas canvas, Paint paint) {
    final stock = Path()
      ..moveTo(4, 15.7)
      ..lineTo(9.6, 13.2)
      ..lineTo(20.8, 7.6)
      ..lineTo(21.5, 9.1)
      ..lineTo(10.6, 14.6)
      ..lineTo(8.4, 18.8)
      ..cubicTo(6.2, 18.7, 4.8, 17.8, 4, 15.7)
      ..close();
    canvas.drawPath(stock, paint);
    canvas.drawLine(const Offset(11, 14.3), const Offset(12.8, 17.5), paint);
    canvas.drawCircle(const Offset(13.2, 11.4), 1.2, paint);
  }

  void _drawSniperRifle(Canvas canvas, Paint paint) {
    final rifle = Path()
      ..moveTo(3.2, 15.5)
      ..lineTo(9.2, 13.5)
      ..lineTo(21.2, 10.3)
      ..lineTo(21.6, 11.9)
      ..lineTo(10.2, 15)
      ..lineTo(8.2, 18.7)
      ..cubicTo(6.2, 18.4, 4.3, 17.2, 3.2, 15.5)
      ..close();
    canvas.drawPath(rifle, paint);
    canvas.drawLine(const Offset(11.2, 14.7), const Offset(12.8, 18.7), paint);
    canvas.drawRect(const Rect.fromLTWH(12.2, 8.2, 5.6, 2.7), paint);
    canvas.drawLine(const Offset(13.4, 8.2), const Offset(13, 6.9), paint);
    canvas.drawLine(const Offset(16.6, 8.2), const Offset(17, 6.9), paint);
  }

  void _drawUnknown(Canvas canvas, Paint paint) {
    canvas.drawCircle(const Offset(12, 12), 8.2, paint);
    final question = Path()
      ..moveTo(9.2, 9)
      ..cubicTo(9.5, 6.8, 11, 5.8, 12.8, 5.8)
      ..cubicTo(15.1, 5.8, 16.5, 7.2, 16.5, 9.2)
      ..cubicTo(16.5, 11, 15.3, 11.8, 13.8, 12.8)
      ..cubicTo(12.8, 13.5, 12.3, 14.1, 12.3, 15.2);
    canvas.drawPath(question, paint);
    canvas.drawCircle(const Offset(12.3, 18), .55, paint);
  }

  @override
  bool shouldRepaint(covariant _BdoGatheringToolPainter oldDelegate) {
    if (color != oldDelegate.color ||
        selection.relation != oldDelegate.selection.relation ||
        selection.tools.length != oldDelegate.selection.tools.length) {
      return true;
    }
    for (var index = 0; index < selection.tools.length; index += 1) {
      if (selection.tools[index] != oldDelegate.selection.tools[index]) {
        return true;
      }
    }
    return false;
  }
}
