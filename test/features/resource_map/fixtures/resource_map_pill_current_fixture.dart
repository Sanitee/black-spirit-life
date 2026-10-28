// Frozen current ResourceMapPill paint oracle. Test-only, never imported by app.
// Source: reviewed current ResourceMapPill snapshot retained in release evidence.
// Original SHA256: 8F33C4CDDFB9F88247A3DABF5E38A4673AF2CA7DD47DD6B268E1A75DD28B1C6F
// Only the chrome-theme import path below is adapted for this test location.
// Preserve frozen import order for source-hash verification after path repair.
// ignore_for_file: directives_ordering
// BEGIN FROZEN PILL SOURCE
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'package:bdo_map_core/src/widgets/resource_map_chrome_theme.dart';

/// Broad reflected light is baked into the existing material, not composited
/// over it. Keep the source's direction and alpha curve at every point so the
/// opacity slider still controls the same single transparent reading plane.
LinearGradient resourceMapRaisedSurfaceGradient(
  ResourceMapChromeThemeData chrome,
  LinearGradient source, {
  bool pressed = false,
}) {
  final top = chrome.chromeRaised.withAlpha(255);
  final middle = chrome.chromeBase.withAlpha(255);
  final bottom = chrome.controlInset.withAlpha(255);
  final light = top.computeLuminance() > .45;
  final face = light
      ? [
          Color.lerp(top, Colors.white, .42)!,
          Color.lerp(top, Colors.white, .16)!,
          top,
          Color.lerp(middle, top, .85)!,
        ]
      : [
          Color.alphaBlend(chrome.ink.withAlpha(20), top),
          Color.alphaBlend(chrome.ink.withAlpha(10), top),
          Color.lerp(middle, top, .48)!,
          Color.lerp(bottom, middle, .70)!,
        ];
  const faceStops = [0.0, .16, .55, 1.0];
  final sourceStops =
      source.stops ??
      [
        for (var i = 0; i < source.colors.length; i++)
          i / (source.colors.length - 1),
      ];
  final stops = {...sourceStops, ...faceStops}.toList()..sort();
  Color interpolate(List<Color> colors, List<double> positions, double value) {
    for (var i = 1; i < positions.length; i++) {
      if (value <= positions[i]) {
        return Color.lerp(
          colors[i - 1],
          colors[i],
          (value - positions[i - 1]) / (positions[i] - positions[i - 1]),
        )!;
      }
    }
    return colors.last;
  }

  final reflected = pressed ? face.reversed.toList() : face;
  return LinearGradient(
    begin: source.begin,
    end: source.end,
    stops: stops,
    tileMode: source.tileMode,
    transform: source.transform,
    colors: [
      for (final stop in stops)
        interpolate(
          reflected,
          faceStops,
          stop,
        ).withValues(alpha: interpolate(source.colors, sourceStops, stop).a),
    ],
  );
}

/// One map option, with its own glass backing and no painted list footprint.
/// The child retains its existing action, focus order and semantics.
class ResourceMapPill extends StatefulWidget {
  const ResourceMapPill({
    super.key,
    required this.child,
    this.selected = false,
    this.quiet = false,
    this.padding = EdgeInsets.zero,
    this.leadingWidth,
  });

  final Widget child;
  final bool selected;
  final bool quiet;
  final EdgeInsetsGeometry padding;

  /// Paints a satin artwork bay within this existing width, without allocating
  /// space or changing the child's layout. Null retains the plain glass face.
  /// The bay follows the leading edge in either text direction.
  final double? leadingWidth;

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
    final face = resourceMapRaisedSurfaceGradient(
      chrome,
      LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        stops: const [0, .12, .72, 1],
        colors: [
          (pressed ? bottom : top).withValues(alpha: fill * .96),
          Color.lerp(
            top,
            bottom,
            pressed ? .80 : .36,
          )!.withValues(alpha: fill * .96),
          Color.lerp(
            top,
            bottom,
            pressed ? .36 : .80,
          )!.withValues(alpha: fill * .98),
          (pressed ? top : bottom).withValues(alpha: fill * .98),
        ],
      ),
      pressed: pressed,
    );
    final border = Border.all(
      color:
          (focused || widget.selected ? chrome.primary : chrome.readingOutline)
              .withValues(alpha: active ? .65 : .34 * strength),
    );
    final decoration = widget.leadingWidth == null
        ? BoxDecoration(borderRadius: radius, gradient: face, border: border)
        : _ResourceMapArtworkBayDecoration(
            face: face,
            bay: _artworkBayGradient(chrome, face, pressed: pressed),
            leadingWidth: widget.leadingWidth!,
            seamLight: chrome.accent.withValues(alpha: .66 * strength),
            seamShade: Colors.black.withValues(alpha: .38 * strength),
            borderRadius: radius,
            border: border,
          );
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
                  blurRadius: 1,
                  offset: const Offset(0, 2),
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
                decoration: decoration,
                child: CustomPaint(
                  painter: _OptionLens(
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

LinearGradient _artworkBayGradient(
  ResourceMapChromeThemeData chrome,
  LinearGradient face, {
  required bool pressed,
}) {
  final top = chrome.chromeRaised.withAlpha(255);
  final bottom = chrome.controlInset.withAlpha(255);
  final light = top.computeLuminance() > .45;
  final metal = Color.lerp(
    top,
    chrome.accent.withAlpha(255),
    light ? .30 : .68,
  )!;
  final colors = [
    Color.lerp(metal, bottom, .24)!,
    Color.lerp(metal, Colors.white, light ? .24 : .22)!,
    metal,
    Color.lerp(metal, bottom, light ? .34 : .49)!,
  ];
  const positions = [0.0, .14, .45, 1.0];
  final sourceStops = face.stops!;
  final stops = {...sourceStops, ...positions}.toList()..sort();
  Color interpolate(List<Color> values, List<double> locations, double value) {
    for (var i = 1; i < locations.length; i++) {
      if (value <= locations[i]) {
        return Color.lerp(
          values[i - 1],
          values[i],
          (value - locations[i - 1]) / (locations[i] - locations[i - 1]),
        )!;
      }
    }
    return values.last;
  }

  final reflected = pressed ? colors.reversed.toList() : colors;
  return LinearGradient(
    begin: face.begin,
    end: face.end,
    tileMode: face.tileMode,
    transform: face.transform,
    stops: stops,
    colors: [
      for (final stop in stops)
        interpolate(
          reflected,
          positions,
          stop,
        ).withValues(alpha: interpolate(face.colors, sourceStops, stop).a),
    ],
  );
}

/// One split material, not a second translucent coat. Retaining BoxDecoration's
/// border/padding contract also keeps every existing child and hit target fixed.
class _ResourceMapArtworkBayDecoration extends BoxDecoration {
  const _ResourceMapArtworkBayDecoration({
    required LinearGradient face,
    required this.bay,
    required this.leadingWidth,
    required this.seamLight,
    required this.seamShade,
    super.border,
    super.borderRadius,
  }) : super(gradient: face);

  final LinearGradient bay;
  final double leadingWidth;
  final Color seamLight;
  final Color seamShade;

  static _ResourceMapArtworkBayDecoration interpolate(
    BoxDecoration first,
    BoxDecoration last,
    double t,
  ) {
    final a = first is _ResourceMapArtworkBayDecoration ? first : null;
    final b = last is _ResourceMapArtworkBayDecoration ? last : null;
    final firstFace = first.gradient! as LinearGradient;
    final lastFace = last.gradient! as LinearGradient;
    return _ResourceMapArtworkBayDecoration(
      face: LinearGradient.lerp(firstFace, lastFace, t)!,
      bay: LinearGradient.lerp(a?.bay ?? firstFace, b?.bay ?? lastFace, t)!,
      leadingWidth:
          (a?.leadingWidth ?? 0) * (1 - t) + (b?.leadingWidth ?? 0) * t,
      seamLight: Color.lerp(a?.seamLight, b?.seamLight, t)!,
      seamShade: Color.lerp(a?.seamShade, b?.seamShade, t)!,
      border: BoxBorder.lerp(first.border, last.border, t),
      borderRadius: BorderRadiusGeometry.lerp(
        first.borderRadius,
        last.borderRadius,
        t,
      ),
    );
  }

  @override
  BoxDecoration? lerpFrom(Decoration? a, double t) =>
      a is BoxDecoration && a.gradient is LinearGradient
      ? interpolate(a, this, t)
      : super.lerpFrom(a, t);

  @override
  BoxDecoration? lerpTo(Decoration? b, double t) =>
      b is BoxDecoration && b.gradient is LinearGradient
      ? interpolate(this, b, t)
      : super.lerpTo(b, t);

  @override
  BoxPainter createBoxPainter([VoidCallback? onChanged]) =>
      _ResourceMapArtworkBayPainter(this, onChanged);

  @override
  bool operator ==(Object other) =>
      other is _ResourceMapArtworkBayDecoration &&
      super == other &&
      bay == other.bay &&
      leadingWidth == other.leadingWidth &&
      seamLight == other.seamLight &&
      seamShade == other.seamShade;

  @override
  int get hashCode =>
      Object.hash(super.hashCode, bay, leadingWidth, seamLight, seamShade);
}

class _ResourceMapArtworkBayPainter extends BoxPainter {
  _ResourceMapArtworkBayPainter(this.decoration, VoidCallback? onChanged)
    : facePainter = BoxDecoration(
        gradient: decoration.gradient,
        border: decoration.border,
        borderRadius: decoration.borderRadius,
      ).createBoxPainter(onChanged),
      bayPainter = BoxDecoration(
        gradient: decoration.bay,
        border: decoration.border,
        borderRadius: decoration.borderRadius,
      ).createBoxPainter(onChanged),
      super(onChanged);

  final _ResourceMapArtworkBayDecoration decoration;
  final BoxPainter facePainter;
  final BoxPainter bayPainter;

  @override
  void paint(Canvas canvas, Offset offset, ImageConfiguration configuration) {
    final size = configuration.size;
    if (size == null || size.isEmpty) return;
    final width = decoration.leadingWidth.isFinite
        ? decoration.leadingWidth.clamp(0.0, size.width).toDouble()
        : 0.0;
    if (width == 0) {
      facePainter.paint(canvas, offset, configuration);
      return;
    }
    final rect = offset & size;
    final rtl = configuration.textDirection == TextDirection.rtl;
    final cut = rtl ? rect.right - width : rect.left + width;
    final bay = Rect.fromLTRB(
      rtl ? cut : rect.left,
      rect.top,
      rtl ? rect.right : cut,
      rect.bottom,
    );
    final body = Rect.fromLTRB(
      rtl ? rect.left : cut,
      rect.top,
      rtl ? cut : rect.right,
      rect.bottom,
    );
    // Hard-edged, disjoint clips share the same boundary: each base pixel is
    // drawn once. Both gradients retain full-face coordinates and alpha.
    canvas.save();
    canvas.clipRect(body, doAntiAlias: false);
    facePainter.paint(canvas, offset, configuration);
    canvas.restore();
    canvas.save();
    canvas.clipRect(bay, doAntiAlias: false);
    bayPainter.paint(canvas, offset, configuration);
    canvas.restore();

    canvas.save();
    canvas.clipRRect(
      (decoration.borderRadius ?? BorderRadius.zero)
          .resolve(configuration.textDirection)
          .toRRect(rect),
    );
    final seam = Rect.fromLTWH(rtl ? cut : cut - 2, rect.top, 2, size.height);
    canvas.drawRect(
      seam,
      Paint()
        ..shader = LinearGradient(
          begin: rtl ? Alignment.centerRight : Alignment.centerLeft,
          end: rtl ? Alignment.centerLeft : Alignment.centerRight,
          colors: [
            decoration.seamShade.withValues(alpha: 0),
            decoration.seamShade,
          ],
        ).createShader(seam),
    );
    canvas.drawLine(
      Offset(rtl ? cut + .5 : cut - .5, rect.top + 1),
      Offset(rtl ? cut + .5 : cut - .5, rect.bottom - 1),
      Paint()
        ..strokeWidth = 1
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            decoration.seamLight,
            decoration.seamLight.withValues(alpha: 0),
          ],
        ).createShader(seam),
    );
    if (width > 20 && size.height > 12) {
      final ledge = Rect.fromLTWH(
        bay.left + 10,
        rect.bottom - 4,
        width - 20,
        1,
      );
      canvas.drawRect(
        ledge,
        Paint()
          ..shader = LinearGradient(
            colors: [
              decoration.seamLight.withValues(alpha: 0),
              decoration.seamLight,
              decoration.seamLight.withValues(alpha: 0),
            ],
          ).createShader(ledge),
      );
    }
    canvas.restore();
  }

  @override
  void dispose() {
    facePainter.dispose();
    bayPainter.dispose();
    super.dispose();
  }
}

/// A short lower contact lip anchors the broad raised face. Reflected light
/// lives in the base gradient so it cannot add another opacity layer.
class _OptionLens extends CustomPainter {
  const _OptionLens({
    required this.shade,
    required this.strength,
    required this.pressed,
  });

  final Color shade;
  final double strength;
  final bool pressed;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width < 20 || size.height < 20) return;
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
            )!.withValues(alpha: (pressed ? .09 : .34) * strength),
          ],
        ).createShader(lip),
    );
  }

  @override
  bool? hitTest(Offset position) => false;

  @override
  bool shouldRepaint(covariant _OptionLens oldDelegate) =>
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
        ..strokeWidth = 1.25
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color.lerp(
              color,
              Colors.white,
              .7,
            )!.withValues(alpha: (pressed ? .10 : .88) * strength),
            color.withValues(alpha: .18 * strength),
            Colors.black.withValues(alpha: .62 * strength),
          ],
          stops: const [0, .16, 1],
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
