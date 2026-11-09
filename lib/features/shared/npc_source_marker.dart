import 'package:flutter/material.dart';

import '../../visual/components/app_tooltip.dart';
import '../../visual/visual.dart';
import 'availability_game_icon.dart';
export 'npc_vendor_hint.dart';

/// A secondary source beside an item name, using the same NPC artwork.
class NpcSourceMarker extends StatelessWidget {
  const NpcSourceMarker({this.textKey, this.vendorHint, super.key});
  final String? vendorHint;
  final Key? textKey;

  TextStyle _style(BuildContext context) =>
      context.visualTheme.typography.meta.copyWith(
        fontSize: 11.5,
        fontWeight: FontWeight.w400,
        fontStyle: FontStyle.normal,
        color: context.visualTheme.palette.textMuted,
      );

  double preferredWidth(BuildContext context) {
    final painter = TextPainter(
      text: TextSpan(
        text: 'NPC',
        style: DefaultTextStyle.of(context).style.merge(_style(context)),
      ),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final width = painter.width.ceilToDouble() + 18;
    painter.dispose();
    return width;
  }

  @override
  Widget build(BuildContext context) => AppTooltip(
    // Explicitly requested for NPC vendors; all other badges stay quiet.
    approvedHover: true,
    waitDuration: const Duration(seconds: 1),
    exitDuration: Duration.zero,
    message: vendorHint ?? 'NPC vendor',
    child: Semantics(
      label: vendorHint ?? 'Available from an NPC',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AvailabilityGameIcon(
            artwork: AvailabilityArtwork.npc,
            size: 14,
            color: context.visualTheme.palette.textMuted,
          ),
          const SizedBox(width: 4),
          Text(
            'NPC',
            key: textKey,
            style: _style(context),
            maxLines: 1,
            softWrap: false,
          ),
        ],
      ),
    ),
  );
}

/// Keep the vendor source attached to the name, never in an availability column.
class ItemNameWithNpc extends StatelessWidget {
  const ItemNameWithNpc({
    required this.child,
    required this.npc,
    this.markerKey,
    this.vendorHint,
    super.key,
  });
  final Widget child;
  final bool npc;
  final Key? markerKey;
  final String? vendorHint;

  @override
  Widget build(BuildContext context) => !npc
      ? child
      : Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(child: child),
            const SizedBox(width: 12),
            NpcSourceMarker(key: markerKey, vendorHint: vendorHint),
          ],
        );
}
