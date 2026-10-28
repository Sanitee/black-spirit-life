import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../diagnostics/earlier_resource_pill_paint.dart';
import 'resource_map_chrome_theme.dart';
import 'resource_map_copper_finish.dart';

/// Uses the actual finish pigment. Material density belongs to alpha, never to
/// an inverse RGB mix that changes the theme's copper, paper or reading colours.
Color resourceMapMaterialPigment(
  ResourceMapChromeThemeData chrome,
  Color pigment,
  double alpha, {
  bool artwork = false,
}) {
  assert(alpha.isFinite && alpha >= 0 && alpha <= 1);
  return pigment.withValues(alpha: alpha);
}

/// Broad reflected light is baked into the existing material, not composited
/// over it. Keep the source's direction and alpha curve at every point so the
/// opacity slider still controls the same single transparent reading plane.
LinearGradient resourceMapRaisedSurfaceGradient(
  ResourceMapChromeThemeData chrome,
  LinearGradient source, {
  bool pressed = false,
}) {
  final top = chrome.chromeRaised.withValues(alpha: 1);
  final middle = chrome.chromeBase.withValues(alpha: 1);
  final bottom = chrome.controlInset.withValues(alpha: 1);
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
        resourceMapMaterialPigment(
          chrome,
          interpolate(reflected, faceStops, stop),
          interpolate(source.colors, sourceStops, stop).a,
        ),
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
    final strength = diagnosticEarlierResourcePillPaint
        ? math.max(.02, chrome.uiOpacity)
        : chrome.materialOpacity;
    final layered = ResourceMapReadingPlane.contains(context);
    final hovered = _feedbackEnabled && _hovered;
    final focused = _feedbackEnabled && _focused;
    final pressed = _feedbackEnabled && _pressed;
    final copper =
        !diagnosticEarlierResourcePillPaint && widget.leadingWidth != null;
    final active = widget.selected || hovered || focused;
    // Copper reflection lives in the bay and rim. Hovering must not brighten
    // the reading plane or change the user's transparency beneath the text.
    final fill = (copper ? widget.selected : active)
        ? math.max(.24, strength * (layered ? .66 : 1))
        : math.max(
            .02,
            strength * (layered ? .48 : 1) * (widget.quiet ? .5 : 1),
          );
    final radius = BorderRadius.all(
      Radius.circular(diagnosticEarlierResourcePillPaint ? 10 : 8),
    );
    final top = Color.lerp(chrome.chromeHighlight, chrome.primary, .045)!;
    final bottom = Color.lerp(chrome.chromeRaised, chrome.chromeBase, .28)!;
    final face = diagnosticEarlierResourcePillPaint
        ? LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              (pressed ? bottom : top).withValues(alpha: fill * .96),
              (pressed ? top : bottom).withValues(alpha: fill * .98),
            ],
          )
        : (copper ? resourceMapCopperFace : resourceMapRaisedSurfaceGradient)(
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
          ((focused && !copper) || widget.selected
                  ? chrome.primary
                  : copper
                  ? chrome.accent
                  : chrome.readingOutline)
              .withValues(
                alpha: (copper ? widget.selected : active)
                    ? .65
                    : .34 * strength,
              ),
    );
    final decoration =
        diagnosticEarlierResourcePillPaint || widget.leadingWidth == null
        ? BoxDecoration(borderRadius: radius, gradient: face, border: border)
        : _ResourceMapArtworkBayDecoration(
            face: face,
            bay: resourceMapCopperBay(
              chrome,
              face,
              pressed: pressed,
              highlighted: hovered || focused,
            ),
            leadingWidth: widget.leadingWidth!,
            seamLight: chrome.accent.withValues(alpha: .66 * strength),
            seamShade: Colors.black.withValues(alpha: .38 * strength),
            borderRadius: radius,
            border: border,
          );
    final duration =
        opacityChanged ||
            MediaQuery.disableAnimationsOf(context) ||
            MediaQuery.accessibleNavigationOf(context)
        ? Duration.zero
        : Duration(milliseconds: copper ? 140 : 150);
    final content = Material(
      type: MaterialType.transparency,
      child: Padding(padding: widget.padding, child: widget.child),
    );
    Widget paintOption(double reflection, Widget child) => CustomPaint(
      painter: diagnosticEarlierResourcePillPaint
          ? EarlierResourcePillLens(
              light: chrome.chromeHighlight,
              shade: chrome.chromeBase,
              strength: fill,
              pressed: pressed,
            )
          : _OptionLens(
              shade: chrome.chromeBase,
              strength: fill,
              pressed: pressed,
              depth: copper ? 5 : 4,
            ),
      foregroundPainter: diagnosticEarlierResourcePillPaint
          ? EarlierResourcePillEdge(
              color: chrome.primary,
              strength: strength,
              selected: widget.selected,
              focused: focused,
              hovered: hovered,
              pressed: pressed,
            )
          : _OptionEdge(
              color: chrome.accent,
              interactionColor: chrome.primary,
              lightSurface: chrome.brightness == Brightness.light,
              strength: strength,
              selected: widget.selected,
              focused: focused,
              hovered: copper ? false : hovered,
              pressed: pressed,
              copperReflection: copper ? reflection : null,
            ),
      child: child,
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
            decoration: _cardContactDecoration(
              borderRadius: radius,
              boxShadow: diagnosticEarlierResourcePillPaint
                  ? [
                      BoxShadow(
                        color: Colors.black.withValues(
                          alpha: .22 * strength * (layered ? .35 : 1),
                        ),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ]
                  : [
                      // The reading plane attenuates the face, not the contact
                      // beneath it. A firm contact and a softer cast separate
                      // each card from the quiet rail without another fill.
                      BoxShadow(
                        color: Colors.black.withValues(
                          alpha:
                              (chrome.brightness == Brightness.light
                                  ? .18
                                  : .55) *
                              strength *
                              (pressed ? .45 : 1),
                        ),
                        blurRadius: 2,
                        offset: Offset(0, pressed ? 1 : 3),
                      ),
                      BoxShadow(
                        color: Colors.black.withValues(
                          alpha:
                              (chrome.brightness == Brightness.light
                                  ? .11
                                  : .35) *
                              strength *
                              (pressed ? .45 : 1),
                        ),
                        blurRadius: 8,
                        offset: Offset(0, pressed ? 2 : 4),
                      ),
                    ],
            ),
            child: ClipRRect(
              borderRadius: radius,
              child: AnimatedContainer(
                // Opacity is already a continuous direct-manipulation input.
                // Retargeting a tween on every tick makes the glass trail the
                // pointer and leaves many rows animating after it stops.
                duration: duration,
                curve: Curves.easeOutCubic,
                decoration: decoration,
                // A stable shell preserves the child's state when the optional
                // artwork bay is added. Ordinary controls never run this tween.
                child: TweenAnimationBuilder<double>(
                  tween: Tween<double>(
                    begin: 0,
                    end: copper && (hovered || focused) ? 1 : 0,
                  ),
                  duration: copper ? duration : Duration.zero,
                  curve: Curves.easeOutCubic,
                  builder: (context, reflection, child) =>
                      paintOption(reflection, child!),
                  child: content,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

BoxDecoration _cardContactDecoration({
  required BorderRadius borderRadius,
  required List<BoxShadow> boxShadow,
}) => diagnosticEarlierResourcePillPaint
    ? BoxDecoration(borderRadius: borderRadius, boxShadow: boxShadow)
    : _ResourceMapContactDecoration(
        borderRadius: borderRadius,
        boxShadow: boxShadow,
      );

/// BoxShadow normally also fills the area beneath a translucent face. Clip that
/// interior out so contact depth cannot become an unintended black body layer.
class _ResourceMapContactDecoration extends BoxDecoration {
  const _ResourceMapContactDecoration({
    required super.borderRadius,
    required super.boxShadow,
  });

  @override
  BoxPainter createBoxPainter([VoidCallback? onChanged]) =>
      _ResourceMapContactPainter(this, onChanged);
}

class _ResourceMapContactPainter extends BoxPainter {
  _ResourceMapContactPainter(this.decoration, VoidCallback? onChanged)
    : delegate = BoxDecoration(
        borderRadius: decoration.borderRadius,
        boxShadow: decoration.boxShadow,
      ).createBoxPainter(onChanged),
      super(onChanged);

  final _ResourceMapContactDecoration decoration;
  final BoxPainter delegate;

  @override
  void paint(Canvas canvas, Offset offset, ImageConfiguration configuration) {
    final size = configuration.size;
    if (size == null || size.isEmpty) return;
    final bounds = offset & size;
    var extent = 0.0;
    for (final shadow in decoration.boxShadow!) {
      extent = math.max(
        extent,
        shadow.blurSigma * 3 +
            shadow.spreadRadius.abs() +
            math.max(shadow.offset.dx.abs(), shadow.offset.dy.abs()) +
            1,
      );
    }
    final outside = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(bounds.inflate(extent))
      ..addRRect(
        decoration.borderRadius!
            .resolve(configuration.textDirection)
            .toRRect(bounds),
      );
    canvas.save();
    canvas.clipPath(outside);
    delegate.paint(canvas, offset, configuration);
    canvas.restore();
  }

  @override
  void dispose() {
    delegate.dispose();
    super.dispose();
  }
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
    // Disjoint clips draw each base pixel once. The metal's reflected light is
    // resolved in its own bay, as on Opportunities' artwork column.
    canvas.save();
    canvas.clipRect(body, doAntiAlias: false);
    facePainter.paint(canvas, offset, configuration);
    canvas.restore();
    canvas.save();
    canvas.clipRect(bay, doAntiAlias: false);
    canvas.clipRRect(
      (decoration.borderRadius ?? BorderRadius.zero)
          .resolve(configuration.textDirection)
          .toRRect(rect),
    );
    canvas.drawRect(bay, Paint()..shader = decoration.bay.createShader(bay));
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
    this.depth = 4,
  });

  final Color shade;
  final double strength;
  final bool pressed;
  final double depth;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width < 20 || size.height < 20) return;
    final lip = Rect.fromLTWH(
      1,
      size.height - depth - 1,
      size.width - 2,
      depth,
    );
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
      depth != oldDelegate.depth ||
      pressed != oldDelegate.pressed;
}

/// The edge distinguishes selection from hover without another filled plane.
/// Painting never adds a hit target or a continuously running animation.
class _OptionEdge extends CustomPainter {
  const _OptionEdge({
    required this.color,
    required this.interactionColor,
    required this.lightSurface,
    required this.strength,
    required this.selected,
    required this.focused,
    required this.hovered,
    required this.pressed,
    this.copperReflection,
  });

  final Color color;
  final Color interactionColor;
  final bool lightSurface;
  final double strength;
  final bool selected;
  final bool focused;
  final bool hovered;
  final bool pressed;
  final double? copperReflection;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width < 20 || size.height < 20) return;
    final bounds = (Offset.zero & size).deflate(.5);
    canvas.drawRRect(
      RRect.fromRectAndRadius(bounds, const Radius.circular(7.5)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            (pressed ? Colors.black : color).withValues(
              alpha: (pressed ? .64 : .96) * strength,
            ),
            color.withValues(alpha: .18 * strength),
            color.withValues(alpha: .08 * strength),
            (pressed ? color : Colors.black).withValues(
              alpha: (pressed ? .36 : .78) * strength,
            ),
          ],
          stops: const [0, .14, .76, 1],
        ).createShader(bounds),
    );
    // The top shoulder is the dominant light, not a second bright rectangle.
    // Side rims stay quiet; the short dark bottom lip remains in _OptionLens.
    final shoulder = Rect.fromLTWH(2, 1.5, size.width - 4, 4);
    canvas.drawRRect(
      RRect.fromRectAndRadius(shoulder, const Radius.circular(2)),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            (pressed ? Colors.black : color).withValues(
              alpha: (pressed ? .18 : .15) * strength,
            ),
            color.withValues(alpha: 0),
          ],
        ).createShader(shoulder),
    );
    final inner = bounds.deflate(1);
    canvas.drawRRect(
      RRect.fromRectAndRadius(inner, const Radius.circular(6.5)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            (pressed ? Colors.black : Colors.white).withValues(
              alpha: (pressed ? .35 : (lightSurface ? .55 : .28)) * strength,
            ),
            color.withValues(alpha: .035 * strength),
            color.withValues(alpha: 0),
            Colors.black.withValues(alpha: (pressed ? .18 : .58) * strength),
          ],
          stops: const [0, .18, .70, 1],
        ).createShader(inner),
    );
    if (!pressed) {
      final glint = Rect.fromLTWH(8, .5, size.width - 16, 1);
      canvas.drawRect(
        glint,
        Paint()
          ..shader = LinearGradient(
            colors: [
              color.withValues(alpha: .96 * strength),
              Colors.white.withValues(alpha: .58 * strength),
              color.withValues(alpha: .14 * strength),
            ],
            stops: const [0, .33, 1],
          ).createShader(glint),
      );
    }
    if (selected) {
      final height = math.min(26.0, size.height - 18);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(1.5, (size.height - height) / 2, 2.5, height),
          const Radius.circular(2),
        ),
        Paint()..color = interactionColor,
      );
    }
    final reflection =
        copperReflection ?? (selected || hovered || focused ? 1 : 0);
    if (reflection > 0 || selected) {
      final rect = Rect.fromLTWH(10, 1.5, size.width - 20, 1);
      canvas.drawRect(
        rect,
        Paint()
          ..shader = LinearGradient(
            colors: [
              color.withValues(alpha: 0),
              color.withValues(
                alpha: .65 * strength * (selected ? 1 : reflection),
              ),
              color.withValues(alpha: 0),
            ],
          ).createShader(rect),
      );
    }
    if (focused || pressed) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          (Offset.zero & size).deflate(3),
          const Radius.circular(5),
        ),
        Paint()
          ..color = interactionColor.withValues(alpha: focused ? 1 : .6)
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
      interactionColor != oldDelegate.interactionColor ||
      lightSurface != oldDelegate.lightSurface ||
      strength != oldDelegate.strength ||
      selected != oldDelegate.selected ||
      focused != oldDelegate.focused ||
      hovered != oldDelegate.hovered ||
      copperReflection != oldDelegate.copperReflection ||
      pressed != oldDelegate.pressed;
}
