part of 'recipe_book_item_info_view.dart';

// Preserve the familiar bullets; long lists use two columns only when readable.
class _EffectColumns extends StatelessWidget {
  const _EffectColumns({required this.effects, required this.style});
  final List<String> effects;
  final TextStyle style;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
      final gap = 28 * scale;
      var split =
          effects.length >= 8 &&
          constraints.maxWidth.isFinite &&
          constraints.maxWidth >= 640 * scale;
      if (split) {
        for (final effect in effects) {
          final painter = TextPainter(
            text: TextSpan(
              text: effect,
              style: DefaultTextStyle.of(context).style.merge(style),
            ),
            textDirection: Directionality.of(context),
            textScaler: MediaQuery.textScalerOf(context),
          )..layout(maxWidth: (constraints.maxWidth - gap) / 2 - 14 * scale);
          if (effect.contains('\n') ||
              painter.computeLineMetrics().length > 2) {
            split = false;
          }
          painter.dispose();
        }
      }
      Widget list(List<String> values) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final value in values) _InfoBullet(value: value, style: style),
        ],
      );
      if (!split) return list(effects);
      final middle = (effects.length / 2).ceil();
      return Row(
        key: const ValueKey('effect-columns'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: list(effects.sublist(0, middle))),
          SizedBox(width: gap),
          Expanded(child: list(effects.sublist(middle))),
        ],
      );
    },
  );
}
