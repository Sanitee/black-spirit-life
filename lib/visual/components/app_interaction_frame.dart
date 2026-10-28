import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../foundations/theme_spec.dart';

/// Local edge lighting for an existing interactive surface. This adds no
/// action, padding, transform or hit target; its child owns every interaction.
class AppInteractionFrame extends StatefulWidget {
  const AppInteractionFrame({
    super.key,
    required this.child,
    this.enabled = true,
    this.selected = false,
    this.radius = 10,
    this.accent,
  });

  final Widget child;
  final bool enabled;
  final bool selected;
  final double radius;
  final Color? accent;

  @override
  State<AppInteractionFrame> createState() => _AppInteractionFrameState();
}

class _AppInteractionFrameState extends State<AppInteractionFrame>
    with SingleTickerProviderStateMixin {
  late final AnimationController _light = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 160),
  );
  bool _hovered = false;
  bool _focused = false;
  bool _motion = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final configured = ThemeSpecScope.maybeOf(
      context,
    )?.motion.interactionDuration;
    _motion =
        TickerMode.valuesOf(context).enabled &&
        !MediaQuery.disableAnimationsOf(context) &&
        !MediaQuery.accessibleNavigationOf(context) &&
        configured != Duration.zero;
    _updateLight();
  }

  @override
  void didUpdateWidget(AppInteractionFrame oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled) _hovered = false;
    _updateLight();
  }

  void _updateLight() {
    final target = widget.enabled && (_hovered || _focused) ? 1.0 : 0.0;
    if (!_motion) {
      _light.stop();
      _light.value = target;
    } else if (_light.value != target) {
      _light.animateTo(target, curve: Curves.easeOutCubic);
    }
  }

  void _hover(bool value) {
    if (_hovered == value) return;
    _hovered = value;
    _updateLight();
  }

  void _focus(bool value) {
    if (_focused == value) return;
    setState(() => _focused = value);
    _updateLight();
  }

  @override
  void dispose() {
    _light.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent =
        widget.accent ??
        ThemeSpecScope.maybeOf(context)?.palette.primaryBright ??
        Theme.of(context).colorScheme.primary;
    return MouseRegion(
      opaque: false,
      onEnter: widget.enabled ? (_) => _hover(true) : null,
      onExit: (_) => _hover(false),
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        includeSemantics: false,
        onFocusChange: _focus,
        child: RepaintBoundary(
          child: CustomPaint(
            foregroundPainter: AppInteractionEdgePainter(
              light: _light,
              accent: accent,
              radius: widget.radius,
              selected: widget.enabled && widget.selected,
              focused: widget.enabled && _focused,
            ),
            child: RepaintBoundary(child: widget.child),
          ),
        ),
      ),
    );
  }
}

class AppInteractionEdgePainter extends CustomPainter {
  AppInteractionEdgePainter({
    required this.light,
    required this.accent,
    required this.radius,
    required this.selected,
    required this.focused,
  }) : super(repaint: light);

  final Animation<double> light;
  final Color accent;
  final double radius;
  final bool selected;
  final bool focused;

  @override
  void paint(Canvas canvas, Size size) {
    final strength = math.max(selected ? .22 : 0.0, light.value);
    if (strength <= 0 || size.shortestSide < 6) return;
    final rect = (Offset.zero & size).deflate(1);
    final shape = RRect.fromRectAndRadius(
      rect,
      Radius.circular(math.min(radius, size.shortestSide / 2)),
    );
    final paint = Paint()..style = PaintingStyle.stroke;
    // A narrow contact glow stays inside the existing surface. No blurred
    // backdrop or oversized shadow needs to be recomposited while scrolling.
    canvas.drawRRect(
      shape.deflate(1),
      paint
        ..strokeWidth = 3
        ..color = accent.withValues(alpha: .075 * strength),
    );
    canvas.drawRRect(
      shape,
      paint
        ..strokeWidth = focused ? 1.6 : 1
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accent.withValues(alpha: .85 * strength),
            accent.withValues(alpha: .24 * strength),
            accent.withValues(alpha: .48 * strength),
          ],
          stops: const [0, .55, 1],
        ).createShader(rect),
    );
  }

  @override
  bool? hitTest(Offset position) => false;

  @override
  bool shouldRepaint(covariant AppInteractionEdgePainter oldDelegate) =>
      light != oldDelegate.light ||
      accent != oldDelegate.accent ||
      radius != oldDelegate.radius ||
      selected != oldDelegate.selected ||
      focused != oldDelegate.focused;
}
