// Frozen earlier ResourceMapPill paint oracle. Test-only, never imported by app.
// Source: reviewed earlier ResourceMapPill snapshot retained in release evidence.
// Original SHA256: 775CE9955FBD819BED59DA0B6B9EC22371DEECF4D61AF014189A38AD07FE1143
// Only the chrome-theme import path below is adapted for this test location.
// Preserve frozen import order for source-hash verification after path repair.
// ignore_for_file: directives_ordering
// BEGIN FROZEN PILL SOURCE
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'package:bdo_map_core/src/widgets/resource_map_chrome_theme.dart';

/// One map option, with its own glass backing and no painted list footprint.
/// The child retains its existing action, focus order and semantics.
class ResourceMapPill extends StatefulWidget {
  const ResourceMapPill({
    super.key,
    required this.child,
    this.selected = false,
    this.quiet = false,
    this.padding = EdgeInsets.zero,
  });

  final Widget child;
  final bool selected;
  final bool quiet;
  final EdgeInsetsGeometry padding;

  @override
  State<ResourceMapPill> createState() => _ResourceMapPillState();
}

class _ResourceMapPillState extends State<ResourceMapPill> {
  bool _hovered = false;
  bool _focused = false;
  bool _pressed = false;
  double? _lastOpacity;

  bool get _feedbackEnabled => switch (widget.child) {
    ButtonStyleButton(:final onPressed, :final onLongPress) =>
      onPressed != null || onLongPress != null,
    IconButton(:final onPressed) => onPressed != null,
    InkResponse(:final onTap, :final onDoubleTap, :final onLongPress) =>
      onTap != null || onDoubleTap != null || onLongPress != null,
    _ => true,
  };

  @override
  Widget build(BuildContext context) {
    final chrome = context.mapChrome;
    final opacityChanged =
        _lastOpacity != null && _lastOpacity != chrome.uiOpacity;
    _lastOpacity = chrome.uiOpacity;
    final strength = math.max(.02, chrome.uiOpacity);
    final layered = ResourceMapReadingPlane.contains(context);
    final hovered = _feedbackEnabled && _hovered;
    final focused = _feedbackEnabled && _focused;
    final pressed = _feedbackEnabled && _pressed;
    final active = widget.selected || hovered || focused;
    final fill = active
        ? math.max(.24, strength * (layered ? .66 : 1))
        : math.max(
            .02,
            strength * (layered ? .48 : 1) * (widget.quiet ? .5 : 1),
          );
    const radius = BorderRadius.all(Radius.circular(10));
    final top = Color.lerp(chrome.chromeHighlight, chrome.primary, .045)!;
    final bottom = Color.lerp(chrome.chromeRaised, chrome.chromeBase, .28)!;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() {
        _hovered = false;
        _pressed = false;
      }),
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onFocusChange: (value) => setState(() => _focused = value),
        child: Listener(
          onPointerDown: (event) {
            if (_feedbackEnabled && event.buttons == kPrimaryButton) {
              setState(() => _pressed = true);
            }
          },
          onPointerUp: (_) => setState(() => _pressed = false),
          onPointerCancel: (_) => setState(() => _pressed = false),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: radius,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(
                    alpha: .22 * strength * (layered ? .35 : 1),
                  ),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: radius,
              child: AnimatedContainer(
                // Opacity is already a continuous direct-manipulation input.
                // Retargeting a tween on every tick makes the glass trail the
                // pointer and leaves many rows animating after it stops.
                duration:
                    opacityChanged ||
                        MediaQuery.disableAnimationsOf(context) ||
                        MediaQuery.accessibleNavigationOf(context)
                    ? Duration.zero
                    : const Duration(milliseconds: 150),
                curve: Curves.easeOutCubic,
                decoration: BoxDecoration(
                  borderRadius: radius,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      (pressed ? bottom : top).withValues(alpha: fill * .96),
                      (pressed ? top : bottom).withValues(alpha: fill * .98),
                    ],
                  ),
                  border: Border.all(
                    color:
                        (focused || widget.selected
                                ? chrome.primary
                                : chrome.readingOutline)
                            .withValues(alpha: active ? .65 : .34 * strength),
                  ),
                ),
                child: CustomPaint(
                  painter: _OptionLens(
                    light: chrome.chromeHighlight,
                    shade: chrome.chromeBase,
                    strength: fill,
                    pressed: pressed,
                  ),
                  foregroundPainter: _OptionEdge(
                    color: chrome.primary,
                    strength: strength,
                    selected: widget.selected,
                    focused: focused,
                    hovered: hovered,
                    pressed: pressed,
                  ),
                  child: Material(
                    type: MaterialType.transparency,
                    child: Padding(
                      padding: widget.padding,
                      child: widget.child,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A narrow upper lens and lower contact lip make the option feel raised.
/// Both sit behind content and follow material opacity, never child opacity.
class _OptionLens extends CustomPainter {
  const _OptionLens({
    required this.light,
    required this.shade,
    required this.strength,
    required this.pressed,
  });

  final Color light;
  final Color shade;
  final double strength;
  final bool pressed;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width < 20 || size.height < 20) return;
    final lens = Rect.fromLTWH(
      1,
      1,
      size.width - 2,
      math.min(17, size.height / 3),
    );
    canvas.drawRect(
      lens,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color.lerp(
              light,
              Colors.white,
              .58,
            )!.withValues(alpha: (pressed ? .045 : .14) * strength),
            light.withValues(alpha: 0),
          ],
        ).createShader(lens),
    );
    final lip = Rect.fromLTWH(1, size.height - 5, size.width - 2, 4);
    canvas.drawRect(
      lip,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            shade.withValues(alpha: 0),
            Color.lerp(
              shade,
              Colors.black,
              .65,
            )!.withValues(alpha: (pressed ? .09 : .26) * strength),
          ],
        ).createShader(lip),
    );
  }

  @override
  bool? hitTest(Offset position) => false;

  @override
  bool shouldRepaint(covariant _OptionLens oldDelegate) =>
      light != oldDelegate.light ||
      shade != oldDelegate.shade ||
      strength != oldDelegate.strength ||
      pressed != oldDelegate.pressed;
}

/// The edge distinguishes selection from hover without another filled plane.
/// Painting never adds a hit target or a continuously running animation.
class _OptionEdge extends CustomPainter {
  const _OptionEdge({
    required this.color,
    required this.strength,
    required this.selected,
    required this.focused,
    required this.hovered,
    required this.pressed,
  });

  final Color color;
  final double strength;
  final bool selected;
  final bool focused;
  final bool hovered;
  final bool pressed;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width < 20 || size.height < 20) return;
    final bounds = (Offset.zero & size).deflate(1.5);
    canvas.drawRRect(
      RRect.fromRectAndRadius(bounds, const Radius.circular(8.5)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(
              color,
              Colors.white,
              .7,
            )!.withValues(alpha: (pressed ? .10 : .46) * strength),
            color.withValues(alpha: .05 * strength),
            Colors.black.withValues(alpha: .34 * strength),
          ],
          stops: const [0, .46, 1],
        ).createShader(bounds),
    );
    if (selected) {
      final height = math.min(26.0, size.height - 18);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(1.5, (size.height - height) / 2, 2.5, height),
          const Radius.circular(2),
        ),
        Paint()..color = color,
      );
    }
    if (selected || hovered || focused) {
      final rect = Rect.fromLTWH(10, 1.5, size.width - 20, 1);
      canvas.drawRect(
        rect,
        Paint()
          ..shader = LinearGradient(
            colors: [
              color.withValues(alpha: 0),
              color.withValues(alpha: .65 * strength),
              color.withValues(alpha: 0),
            ],
          ).createShader(rect),
      );
    }
    if (focused || pressed) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          (Offset.zero & size).deflate(3),
          const Radius.circular(7),
        ),
        Paint()
          ..color = color.withValues(alpha: focused ? 1 : .6)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    }
  }

  @override
  bool? hitTest(Offset position) => false;

  @override
  bool shouldRepaint(covariant _OptionEdge oldDelegate) =>
      color != oldDelegate.color ||
      strength != oldDelegate.strength ||
      selected != oldDelegate.selected ||
      focused != oldDelegate.focused ||
      hovered != oldDelegate.hovered ||
      pressed != oldDelegate.pressed;
}
