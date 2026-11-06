import 'package:bdo_map_core/bdo_map_core.dart';
import 'package:flutter/material.dart';

import '../../visual/visual.dart';

enum PlannerMapEmblem { gathering, checklist, network, npc }

TextStyle plannerMapLookupActionStyle(ThemeSpec spec) =>
    spec.typography.body.copyWith(fontSize: 14, fontWeight: FontWeight.w700);

TextStyle plannerMapLookupDetailStyle(ThemeSpec spec) =>
    spec.typography.meta.copyWith(color: spec.palette.textMuted, fontSize: 11);

double plannerMapLookupMenuWidth({
  required BuildContext context,
  required Size viewportSize,
  required Iterable<String> actionLabels,
  required Iterable<String> actionDetails,
}) {
  final spec = context.visualTheme;
  double measure(String text, TextStyle style) => (TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
    maxLines: 1,
  )..layout()).width;
  var widest = 0.0;
  for (final text in actionLabels) {
    final width = measure(text, plannerMapLookupActionStyle(spec));
    if (width > widest) widest = width;
  }
  for (final text in actionDetails) {
    final width = measure(text, plannerMapLookupDetailStyle(spec));
    if (width > widest) widest = width;
  }
  final limit = (viewportSize.width - 16).clamp(0.0, double.infinity);
  // Both item padding (12) and row chrome (100) count toward the width.
  return (widest + 112).clamp(limit < 310 ? limit : 310.0, limit);
}

/// Open, joined rows. The PopupMenuItem owns focus, hover and activation;
/// this presentation adds neither another button nor a tooltip.
class PlannerMapMenuLabel extends StatelessWidget {
  const PlannerMapMenuLabel({
    required this.emblem,
    required this.label,
    this.detail,
    super.key,
  });

  final PlannerMapEmblem emblem;
  final String label;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final spec = context.visualTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      child: Row(
        children: [
          SizedBox.square(
            dimension: 42,
            child: Center(child: PlannerMapActionEmblem(emblem: emblem)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: plannerMapLookupActionStyle(spec)),
                if (detail != null) ...[
                  const SizedBox(height: 1),
                  Text(detail!, style: plannerMapLookupDetailStyle(spec)),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          ExcludeSemantics(
            child: Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: spec.palette.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

/// Original bundled artwork, with an adapted scroll for the app-only list.
/// The visible action text supplies semantics; the emblems are decorative.
class PlannerMapActionEmblem extends StatelessWidget {
  const PlannerMapActionEmblem({required this.emblem, super.key});

  final PlannerMapEmblem emblem;

  Rect? get sourceRect => switch (emblem) {
    PlannerMapEmblem.gathering => bdoGatheringToolAssetSourceRect(
      BdoGatheringToolKind.bareHands,
    ),
    // Authentic atlas artwork, reused for vendors, not an assertion that this
    // is the current game's dedicated Find NPC control.
    PlannerMapEmblem.npc => const Rect.fromLTWH(141, 1, 34, 34),
    _ => null,
  };

  @override
  Widget build(BuildContext context) {
    final frame = sourceRect;
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: 34,
        child: frame != null
            ? ClipRect(
                child: Stack(
                  children: [
                    Positioned(
                      left: -frame.left,
                      top: -frame.top,
                      width: 512,
                      height: 256,
                      child: Image.asset(
                        bdoGatheringToolAssetPath(
                          BdoGatheringToolKind.bareHands,
                        )!,
                        package: bdoGatheringToolAssetPackage,
                        width: 512,
                        height: 256,
                        fit: BoxFit.fill,
                        filterQuality: FilterQuality.medium,
                        excludeFromSemantics: true,
                      ),
                    ),
                  ],
                ),
              )
            : emblem == PlannerMapEmblem.network
            ? ClipRect(
                child: Transform.scale(
                  scale: 1.7,
                  child: Image.asset(
                    'assets/images/node_icons/0.png',
                    package: 'bdo_map_core',
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.medium,
                    excludeFromSemantics: true,
                  ),
                ),
              )
            : Center(
                child: SizedBox.square(
                  dimension: 28,
                  child: CustomPaint(
                    painter: _ChecklistScrollPainter(
                      context.visualTheme.palette.text,
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}

// Lucide scroll-text, adapted to Flutter Canvas. ISC notice is bundled at
// assets/app/lucide-LICENSE.txt. This is not original Black Desert artwork.
class _ChecklistScrollPainter extends CustomPainter {
  const _ChecklistScrollPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 24, size.height / 24);
    final path = Path()
      ..moveTo(15, 12)
      ..lineTo(10, 12)
      ..moveTo(15, 8)
      ..lineTo(10, 8)
      ..moveTo(19, 17)
      ..lineTo(19, 5)
      ..arcToPoint(
        const Offset(17, 3),
        radius: const Radius.circular(2),
        clockwise: false,
      )
      ..lineTo(4, 3)
      ..moveTo(8, 21)
      ..lineTo(20, 21)
      ..arcToPoint(
        const Offset(22, 19),
        radius: const Radius.circular(2),
        clockwise: false,
      )
      ..lineTo(22, 18)
      ..arcToPoint(
        const Offset(21, 17),
        radius: const Radius.circular(1),
        clockwise: false,
      )
      ..lineTo(11, 17)
      ..arcToPoint(
        const Offset(10, 18),
        radius: const Radius.circular(1),
        clockwise: false,
      )
      ..lineTo(10, 19)
      ..arcToPoint(const Offset(6, 19), radius: const Radius.circular(2))
      ..lineTo(6, 5)
      ..arcToPoint(
        const Offset(2, 5),
        radius: const Radius.circular(2),
        clockwise: false,
      )
      ..lineTo(2, 7)
      ..arcToPoint(
        const Offset(3, 8),
        radius: const Radius.circular(1),
        clockwise: false,
      )
      ..lineTo(6, 8);
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ChecklistScrollPainter oldDelegate) =>
      color != oldDelegate.color;
}
