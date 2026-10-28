import 'package:flutter/material.dart';

import 'theme.dart';

/// An unblurred working surface. Unlike the map's floating glass, this sits on
/// the quiet desk and can separate editable groups with a crisp, static edge.
class FieldDeskPanel extends StatefulWidget {
  const FieldDeskPanel({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
    this.radius = 12,
    this.interactive = false,
    this.leadingWidth,
    this.leadingHeight,
    this.trailingWidth = 0,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final bool interactive;
  final double? leadingWidth, leadingHeight;
  final double trailingWidth;

  @override
  State<FieldDeskPanel> createState() => _FieldDeskPanelState();
}

class _FieldDeskPanelState extends State<FieldDeskPanel> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.gatheringColors;
    final glass = context.glass;
    final light = colors.brightness == Brightness.light;
    final active = widget.interactive && (_hovered || _focused);
    final radius = widget.radius;
    final base = BoxDecoration(
      borderRadius: BorderRadius.circular(radius),
      gradient: glass.polishedMaterialGradient(
        LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: const [0, .55, 1],
          colors: [
            Color.lerp(
              colors.raised,
              colors.accent,
              active ? .075 : 0,
            )!.withValues(alpha: glass.surfaceOpacity),
            colors.surface.withValues(alpha: glass.surfaceOpacity),
            colors.inset.withValues(alpha: glass.surfaceOpacity),
          ],
        ),
        accented: active,
      ),
      border: Border.all(
        color: _focused && widget.interactive
            ? colors.accent
            : active
            ? colors.accent.withValues(alpha: .65)
            : glass.strongLine,
      ),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(
            alpha: (light ? .18 : .42) * glass.effectStrength,
          ),
          blurRadius: 1,
          offset: const Offset(0, 2),
        ),
      ],
    );
    final face = AnimatedContainer(
      padding: EdgeInsets.zero,
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 150),
      curve: Curves.easeOutCubic,
      decoration: widget.leadingWidth == null
          ? base
          : glass.segmentedDecoration(
              base,
              leadingWidth: widget.leadingWidth!,
              leadingHeight: widget.leadingHeight,
              trailingWidth: widget.trailingWidth,
            ),
      child: CustomPaint(
        foregroundPainter: _DeskEdgePainter(
          colors.rim.withValues(
            alpha: (light ? .94 : .88) * glass.effectStrength,
          ),
          Colors.black.withValues(
            alpha: (light ? .28 : .56) * glass.effectStrength,
          ),
          radius,
        ),
        child: Material(
          type: MaterialType.transparency,
          borderRadius: BorderRadius.circular(radius),
          clipBehavior: Clip.antiAlias,
          child: Padding(padding: widget.padding, child: widget.child),
        ),
      ),
    );
    if (!widget.interactive) return face;
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (value) => setState(() => _focused = value),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: face,
      ),
    );
  }
}

/// A quiet rule connects a heading and its related action without introducing
/// another card, label or fixed-height header.
class FieldDeskSectionHeading extends StatelessWidget {
  const FieldDeskSectionHeading({
    super.key,
    required this.title,
    this.action,
    this.prominent = false,
  });

  final String title;
  final Widget? action;
  final bool prominent;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final text = Text(
        title,
        style: prominent
            ? Theme.of(context).textTheme.headlineSmall
            : Theme.of(context).textTheme.titleLarge,
      );
      if (constraints.maxWidth <
          540 * MediaQuery.textScalerOf(context).scale(1)) {
        return Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 18,
          runSpacing: 4,
          children: [text, ?action],
        );
      }
      return Row(
        children: [
          Flexible(child: text),
          const SizedBox(width: 18),
          Expanded(
            child: Container(
              height: 1,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [context.glass.strongLine, context.glass.line],
                ),
              ),
            ),
          ),
          if (action != null) ...[const SizedBox(width: 14), action!],
        ],
      );
    },
  );
}

/// Paint-only selection cue; never intercepts a click, focus, drag or scroll.
class FieldDeskSelection extends StatelessWidget {
  const FieldDeskSelection({
    super.key,
    required this.selected,
    required this.child,
  });

  final bool selected;
  final Widget child;

  @override
  Widget build(BuildContext context) => CustomPaint(
    foregroundPainter: _DeskSelectionPainter(
      selected ? context.gatheringColors.accent : Colors.transparent,
    ),
    child: child,
  );
}

class _DeskSelectionPainter extends CustomPainter {
  const _DeskSelectionPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (color.a == 0 || size.height <= 16) return;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 10, 3, size.height - 20),
        const Radius.circular(2),
      ),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(_DeskSelectionPainter oldDelegate) =>
      color != oldDelegate.color;
}

class _DeskEdgePainter extends CustomPainter {
  const _DeskEdgePainter(this.color, this.shade, this.radius);
  final Color color;
  final Color shade;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= radius * 2 || size.height <= radius * 2) return;
    final area = Offset.zero & size;
    // Continuous opposed bevels give the face a cut edge without spreading
    // shadow across neighbouring groups or painting over the reading centre.
    final shape = RRect.fromRectAndRadius(
      area.deflate(.75),
      Radius.circular(radius > .75 ? radius - .75 : 0),
    );
    canvas.drawRRect(
      shape,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            color,
            color.withValues(alpha: color.a * .12),
            shade,
          ],
          stops: const [0, .16, 1],
        ).createShader(area),
    );
    canvas.drawRRect(
      shape.deflate(1.75),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = .8
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            color.withValues(alpha: color.a * .40),
            shade.withValues(alpha: 0),
            shade.withValues(alpha: shade.a * .60),
          ],
          stops: const [0, .25, 1],
        ).createShader(area),
    );
  }

  @override
  bool? hitTest(Offset position) => false;

  @override
  bool shouldRepaint(_DeskEdgePainter oldDelegate) =>
      color != oldDelegate.color ||
      shade != oldDelegate.shade ||
      radius != oldDelegate.radius;
}
