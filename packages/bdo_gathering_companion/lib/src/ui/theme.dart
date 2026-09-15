import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../assets.dart';

const ink = Color(0xFFF1F3ED);
const muted = Color(0xFFB3C2C5);
const canvasColor = Color(0xFF0C151D);
const accent = Color(0xFF7DE0D3);
const positive = Color(0xFF69C59A);
const _glassRim = Color(0xFFC5E7EE);
const _glassEdge = Color(0xFF638695);
const gold = Color(0xFFE5C58D);
const defaultGlassOpacityPercent = 60;
const glassOpacityPreferenceKey = 'glassOpacityPercent';
const glassBlurSigma = 14.0;

int normalizeGlassOpacity(Object? value) {
  if (value == null || value.toString().trim().isEmpty) {
    return defaultGlassOpacityPercent;
  }
  final parsed = value is num ? value.toDouble() : double.tryParse('$value');
  if (parsed == null || !parsed.isFinite) return defaultGlassOpacityPercent;
  return parsed.round().clamp(0, 100);
}

@immutable
class CompanionGlassTheme extends ThemeExtension<CompanionGlassTheme> {
  const CompanionGlassTheme({
    required this.opacityPercent,
    required this.surfaceOpacity,
    required this.softOpacity,
    required this.controlOpacity,
    required this.solidOpacity,
    required this.hoverOpacity,
    required this.hoverStrongOpacity,
    required this.selectedOpacity,
    required this.selectedStrongOpacity,
    required this.borderOpacity,
    required this.strongBorderOpacity,
    required this.shadowOpacity,
    required this.softShadowOpacity,
    required this.deepShadowOpacity,
    required this.highlightOpacity,
  });

  factory CompanionGlassTheme.fromPercent(Object? value) {
    final percent = normalizeGlassOpacity(value);
    final material = math.max(.02, percent / 100);
    final soft = math.min(1.0, material * (.82 / .76));
    final control = math.min(1.0, material * (.86 / .76));
    final solid = math.min(1.0, material * (.90 / .76));
    final strength = math.min(1.0, material / .76);
    return CompanionGlassTheme(
      opacityPercent: percent,
      surfaceOpacity: material,
      softOpacity: soft,
      controlOpacity: control,
      solidOpacity: solid,
      hoverOpacity: math.max(.16, control),
      hoverStrongOpacity: math.max(.20, solid),
      selectedOpacity: math.max(.24, control),
      selectedStrongOpacity: math.max(.30, solid),
      borderOpacity: .18 * strength,
      strongBorderOpacity: .34 * strength,
      shadowOpacity: .42 * strength,
      softShadowOpacity: .24 * strength,
      deepShadowOpacity: .68 * strength,
      highlightOpacity: .13 * strength,
    );
  }

  final int opacityPercent;
  final double surfaceOpacity;
  final double softOpacity;
  final double controlOpacity;
  final double solidOpacity;
  final double hoverOpacity;
  final double hoverStrongOpacity;
  final double selectedOpacity;
  final double selectedStrongOpacity;
  final double borderOpacity;
  final double strongBorderOpacity;
  final double shadowOpacity;
  final double softShadowOpacity;
  final double deepShadowOpacity;
  final double highlightOpacity;

  double get effectStrength => math.min(1.0, surfaceOpacity / .76);
  // Reading a popup must not depend on how transparent the user wants the map.
  double get backdropOpacity => .60;

  // Translucent glass needs a lighter tint to retain its apparent shade over
  // the scene. Fade that lift out as opacity rises; opaque surfaces keep their
  // original readable colors, and the saved opacity itself is unchanged.
  Color _litTint(Color solid, Color translucent, double opacity) => Color.lerp(
    solid,
    translucent,
    ((1 - surfaceOpacity) / .4).clamp(0.0, 1.0),
  )!.withValues(alpha: opacity);

  Color get panel => _litTint(
    const Color(0xFF1B2A35),
    const Color(0xFF273D49),
    surfaceOpacity,
  );
  Color get row => _litTint(
    const Color(0xFF243744),
    const Color(0xFF304954),
    controlOpacity,
  );
  Color get group => _litTint(
    const Color(0xFF0F1820),
    const Color(0xFF121B23),
    math.max(.02, softOpacity * .5),
  );
  Color get inset => const Color(
    0xFF0A1117,
  ).withValues(alpha: math.max(.02, softOpacity * .54));

  /// Quiet blue-grey backing also keeps missing-artwork fallback text readable.
  Color get iconWell => _litTint(
    const Color(0xFF253540),
    const Color(0xFF2D424E),
    controlOpacity,
  );

  /// Light steel plates are for artwork only; labels stay on the dark control.
  Color get toolPlate => _litTint(
    const Color(0xFF546574),
    const Color(0xFF6E7F8F),
    controlOpacity,
  );
  Color get toolPlateSelected => _litTint(
    const Color(0xFF607383),
    const Color(0xFF7F96A7),
    selectedOpacity,
  );

  Color get line => _glassEdge.withValues(alpha: .62 * effectStrength);
  Color get strongLine => _glassEdge.withValues(alpha: .62 * effectStrength);
  Color get insetLine => _glassEdge.withValues(alpha: .47 * effectStrength);
  Color get active => _litTint(
    const Color(0xFF214A4D),
    const Color(0xFF2B5456),
    selectedOpacity,
  );
  Color get hover =>
      _litTint(const Color(0xFF263E4B), const Color(0xFF2E4E60), hoverOpacity);
  Color get accentSelection => active;
  Color get accentSelectionSoft => active.withValues(alpha: active.a * .7);
  Color get popup =>
      const Color(0xFF0F1820).withValues(alpha: math.max(.98, solidOpacity));

  LinearGradient get surfaceGradient => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    stops: const [0, .52, 1],
    colors: [
      _litTint(
        const Color(0xFF253946),
        const Color(0xFF2D4652),
        surfaceOpacity,
      ),
      _litTint(
        const Color(0xFF15232E),
        const Color(0xFF1D303C),
        surfaceOpacity,
      ),
      _litTint(const Color(0xFF111C26), const Color(0xFF172730), softOpacity),
    ],
  );

  LinearGradient get headerGradient => LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      _litTint(
        const Color(0xFF18242F),
        const Color(0xFF19242E),
        surfaceOpacity,
      ),
      _litTint(const Color(0xFF0A1117), const Color(0xFF0B1219), softOpacity),
    ],
  );

  LinearGradient get controlGradient => LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      row,
      _litTint(
        const Color(0xFF101B24),
        const Color(0xFF111D27),
        controlOpacity,
      ),
    ],
  );

  LinearGradient get hoverGradient => LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [hover, controlGradient.colors.last],
  );

  LinearGradient get selectedGradient => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      active,
      _litTint(
        const Color(0xFF142B34),
        const Color(0xFF173540),
        selectedOpacity,
      ),
    ],
  );

  /// Actions stay opaque, as before, so dark action text stays readable even
  /// when the surrounding glass is set to its minimum opacity.
  LinearGradient get primaryGradient => const LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFA9EDE0), Color(0xFF68C9BB)],
  );

  LinearGradient get groupGradient => LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [group, inset],
  );

  LinearGradient get iconWellGradient => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      iconWell,
      _litTint(
        const Color(0xFF0A1117),
        const Color(0xFF0B1219),
        controlOpacity,
      ),
    ],
  );

  LinearGradient get toolWellGradient => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      toolPlate,
      _litTint(
        const Color(0xFF253540),
        const Color(0xFF2F424F),
        controlOpacity,
      ),
    ],
  );

  RadialGradient artworkHighlight({bool tool = false}) => RadialGradient(
    center: const Alignment(0, -.76),
    radius: .85,
    colors: [
      _glassRim.withValues(alpha: (tool ? .22 : .06) * effectStrength),
      _glassRim.withValues(alpha: 0),
    ],
    stops: const [0, 1],
  );

  /// Compatibility sheen is extremely subtle. Raised controls use edge-only
  /// glints instead, leaving their approved colored faces uncoated.
  LinearGradient get clearcoatGradient => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    stops: const [0, .36, .72, 1],
    colors: [
      _glassRim.withValues(alpha: highlightOpacity * .035),
      _glassRim.withValues(alpha: highlightOpacity * .015),
      Colors.transparent,
      const Color(0xFF080E14).withValues(alpha: highlightOpacity * .18),
    ],
  );

  List<BoxShadow> get panelShadows => [
    BoxShadow(
      color: Colors.black.withValues(alpha: .33 * effectStrength),
      blurRadius: 26,
      offset: const Offset(0, 12),
    ),
    BoxShadow(
      color: Colors.black.withValues(alpha: softShadowOpacity),
      blurRadius: 3,
      offset: const Offset(0, 2),
    ),
  ];

  @override
  CompanionGlassTheme copyWith({int? opacityPercent}) =>
      CompanionGlassTheme.fromPercent(opacityPercent ?? this.opacityPercent);

  @override
  CompanionGlassTheme lerp(covariant CompanionGlassTheme? other, double t) =>
      CompanionGlassTheme.fromPercent(
        lerpDouble(
          opacityPercent.toDouble(),
          other?.opacityPercent.toDouble(),
          t,
        ),
      );
}

extension CompanionGlassContext on BuildContext {
  CompanionGlassTheme get glass =>
      Theme.of(this).extension<CompanionGlassTheme>() ??
      CompanionGlassTheme.fromPercent(defaultGlassOpacityPercent);
}

BoxDecoration glassPanelDecoration({
  required CompanionGlassTheme glass,
  double radius = 12,
  bool elevated = false,
  Gradient? gradient,
}) => BoxDecoration(
  gradient: gradient ?? glass.surfaceGradient,
  borderRadius: BorderRadius.circular(radius),
  border: Border.all(color: glass.strongLine),
  boxShadow: elevated
      ? [
          BoxShadow(
            color: Colors.black.withValues(alpha: glass.deepShadowOpacity),
            blurRadius: 22,
            offset: const Offset(0, 9),
          ),
          BoxShadow(
            color: const Color(
              0xFFC5E7EE,
            ).withValues(alpha: glass.highlightOpacity * .55),
            blurRadius: 1,
            offset: const Offset(0, -1),
          ),
        ]
      : null,
);

/// A structural glass surface. Keep this around whole panels rather than small
/// repeated controls so the blur remains inexpensive and the icons stay crisp.
class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
    this.radius = 12,
    this.elevated = true,
    this.gradient,
    this.reading = false,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final bool elevated;
  final Gradient? gradient;

  /// Dialogs keep their glass finish without letting map labels compete with
  /// the content. Ordinary map panels still follow the user's opacity slider.
  final bool reading;

  @override
  Widget build(BuildContext context) {
    if (reading) {
      return Theme(
        data: companionTheme(
          opacityPercent: math.max(96, context.glass.opacityPercent),
        ),
        child: Builder(builder: _buildSurface),
      );
    }
    return _buildSurface(context);
  }

  Widget _buildSurface(BuildContext context) {
    final borderRadius = BorderRadius.circular(radius);
    final glass = context.glass;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        boxShadow: elevated ? glass.panelShadows : null,
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: glassBlurSigma,
            sigmaY: glassBlurSigma,
            tileMode: TileMode.clamp,
          ),
          child: DecoratedBox(
            decoration: glassPanelDecoration(
              glass: glass,
              radius: radius,
              gradient: gradient,
            ),
            child: CustomPaint(
              foregroundPainter: _GlassEdgePainter(
                radius,
                glass.highlightOpacity * 1.65,
              ),
              child: Padding(padding: padding, child: child),
            ),
          ),
        ),
      ),
    );
  }
}

/// A raised face without changing its child's layout or interaction contract.
/// The shared Material keeps InkWell feedback above the gradient, not below it.
class GlassControl extends StatefulWidget {
  const GlassControl({
    super.key,
    required this.child,
    this.selected = false,
    this.hovered = false,
    this.primary = false,
    this.radius = 9,
  });

  final Widget child;
  final bool selected;
  final bool hovered;
  final bool primary;
  final double radius;

  @override
  State<GlassControl> createState() => _GlassControlState();
}

class _GlassControlState extends State<GlassControl> {
  bool _hover = false, _pressed = false, _focus = false;

  // Direct Material buttons expose their disabled state. Other children keep
  // ownership of action gating; this decorative wrapper never enables actions.
  bool get _feedbackEnabled => switch (widget.child) {
    ButtonStyleButton(:final onPressed, :final onLongPress) =>
      onPressed != null || onLongPress != null,
    IconButton(:final onPressed) => onPressed != null,
    _ => true,
  };

  @override
  Widget build(BuildContext context) {
    final glass = context.glass;
    final borderRadius = BorderRadius.circular(widget.radius);
    final selected = widget.selected;
    final hovered = _feedbackEnabled && (widget.hovered || _hover || _focus);
    final pressed = _feedbackEnabled && _pressed;
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    final duration = reducedMotion
        ? Duration.zero
        : const Duration(milliseconds: 160);
    return Focus(
      canRequestFocus: false,
      onFocusChange: (value) => setState(() => _focus = value),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() {
          _hover = false;
          _pressed = false;
        }),
        child: Listener(
          onPointerDown: (event) {
            if (_feedbackEnabled && event.buttons == kPrimaryButton) {
              setState(() => _pressed = true);
            }
          },
          onPointerUp: (_) => setState(() => _pressed = false),
          onPointerCancel: (_) => setState(() => _pressed = false),
          child: TweenAnimationBuilder<double>(
            key: const ValueKey('glass-control-lift'),
            tween: Tween(
              begin: 0,
              end: hovered && !pressed && !reducedMotion ? -1 : 0,
            ),
            duration: duration,
            curve: Curves.easeOutCubic,
            builder: (context, lift, child) => Transform.translate(
              offset: Offset(0, lift),
              transformHitTests: false,
              child: child,
            ),
            child: AnimatedScale(
              scale: pressed && !reducedMotion ? .985 : 1,
              duration: duration,
              curve: Curves.easeOutCubic,
              child: AnimatedContainer(
                duration: duration,
                curve: Curves.easeOutCubic,
                decoration: BoxDecoration(
                  borderRadius: borderRadius,
                  boxShadow: [
                    if (hovered || selected)
                      BoxShadow(
                        color: accent.withValues(alpha: _focus ? .18 : .07),
                        blurRadius: hovered ? 16 : 9,
                        spreadRadius: _focus ? 1 : 0,
                      ),
                    BoxShadow(
                      color: Colors.black.withValues(
                        alpha: (selected ? .47 : .33) * glass.effectStrength,
                      ),
                      blurRadius: selected ? 12 : 7,
                      offset: Offset(0, selected ? 5 : 3),
                    ),
                  ],
                ),
                child: Material(
                  color: Colors.transparent,
                  borderRadius: borderRadius,
                  clipBehavior: Clip.antiAlias,
                  child: _GlassControlInk(
                    selected: selected,
                    hovered: hovered,
                    primary: widget.primary,
                    radius: widget.radius,
                    child: widget.child,
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

class _GlassControlInk extends StatelessWidget {
  const _GlassControlInk({
    required this.child,
    this.selected = false,
    this.hovered = false,
    this.primary = false,
    this.radius = 9,
  });

  final Widget child;
  final bool selected;
  final bool hovered;
  final bool primary;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final glass = context.glass;
    final finish = BoxDecoration(
      gradient: primary
          ? glass.primaryGradient
          : selected
          ? glass.selectedGradient
          : hovered
          ? glass.hoverGradient
          : glass.controlGradient,
      borderRadius: BorderRadius.circular(radius),
    );
    return TweenAnimationBuilder<Decoration>(
      key: const ValueKey('glass-control-finish'),
      tween: DecorationTween(begin: finish, end: finish),
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 160),
      curve: Curves.easeOutCubic,
      builder: (context, decoration, child) =>
          Ink(padding: EdgeInsets.zero, decoration: decoration, child: child),
      child: CustomPaint(
        foregroundPainter: _GlassEdgePainter(
          radius,
          primary ? .38 : (selected ? .38 : .19) * glass.effectStrength,
          bottomOpacity: (primary ? .20 : .50) * glass.effectStrength,
          borderColor: primary
              ? Color.lerp(accent, _glassRim, .65)!
              : selected
              ? accent.withValues(alpha: .55 + .45 * glass.effectStrength)
              : hovered
              ? _glassRim.withValues(alpha: glass.effectStrength)
              : glass.line,
        ),
        child: child,
      ),
    );
  }
}

/// A crisp artwork-only well. No opacity/filter is applied to the game asset.
class GlassArtworkWell extends StatelessWidget {
  const GlassArtworkWell({
    super.key,
    required this.child,
    this.tool = false,
    this.radius = 7,
  });

  final Widget child;
  final bool tool;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final glass = context.glass;
    final borderRadius = BorderRadius.circular(radius);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: tool ? glass.toolWellGradient : glass.iconWellGradient,
        borderRadius: borderRadius,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .33 * glass.effectStrength),
            blurRadius: 3,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: glass.artworkHighlight(tool: tool),
          borderRadius: borderRadius,
        ),
        child: CustomPaint(
          foregroundPainter: _GlassEdgePainter(
            radius,
            .28 * glass.effectStrength,
            bottomOpacity: .50 * glass.effectStrength,
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Brief confirmation around changed read-only totals; never animates or
/// replaces editable text, and stays still when reduced motion is requested.
class ValueChangePulse extends StatefulWidget {
  const ValueChangePulse({super.key, required this.value, required this.child});
  final Object value;
  final Widget child;

  @override
  State<ValueChangePulse> createState() => _ValueChangePulseState();
}

class _ValueChangePulseState extends State<ValueChangePulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 650),
    value: 1,
  );

  @override
  void didUpdateWidget(ValueChangePulse oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value) {
      if (MediaQuery.disableAnimationsOf(context)) {
        _pulse.value = 1;
      } else {
        _pulse.forward(from: 0);
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) _pulse.value = 1;
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _pulse,
    child: widget.child,
    builder: (context, child) => DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(5),
        color: accent.withValues(alpha: (1 - _pulse.value) * .18),
      ),
      child: child,
    ),
  );
}

/// Painted below text and artwork, and on the same Material as its ink response.
/// No extra backdrop filter per card or control.
class GlassSheen extends StatelessWidget {
  const GlassSheen({super.key, required this.child, this.radius = 10});

  final Widget child;
  final double radius;

  @override
  Widget build(BuildContext context) => Ink(
    decoration: BoxDecoration(
      gradient: context.glass.clearcoatGradient,
      borderRadius: BorderRadius.circular(radius),
    ),
    child: child,
  );
}

class _GlassEdgePainter extends CustomPainter {
  const _GlassEdgePainter(
    this.radius,
    this.opacity, {
    this.bottomOpacity = 0,
    this.borderColor,
  });

  final double radius;
  final double opacity;
  final double bottomOpacity;
  final Color? borderColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    if (borderColor case final color?) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          (Offset.zero & size).deflate(.5),
          Radius.circular(radius),
        ),
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    }
    final horizontal = Rect.fromLTWH(0, 0, size.width, 4);
    final topPaint = Paint()
      ..strokeWidth = 1
      ..shader = LinearGradient(
        colors: [
          _glassRim.withValues(alpha: opacity),
          _glassRim.withValues(alpha: opacity * .45),
          Colors.transparent,
        ],
        stops: const [0, .42, 1],
      ).createShader(horizontal);
    canvas.drawLine(
      Offset(radius * .7, .75),
      Offset(size.width - radius, .75),
      topPaint,
    );

    final vertical = Rect.fromLTWH(0, 0, 4, size.height);
    final leftPaint = Paint()
      ..strokeWidth = .8
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          _glassRim.withValues(alpha: opacity * .65),
          _glassRim.withValues(alpha: opacity * .30),
          Colors.transparent,
        ],
        stops: const [0, .36, .9],
      ).createShader(vertical);
    canvas.drawLine(
      Offset(.75, radius * .7),
      Offset(.75, size.height - radius),
      leftPaint,
    );
    if (bottomOpacity > 0) {
      canvas.drawLine(
        Offset(radius, size.height - .75),
        Offset(size.width - radius, size.height - .75),
        Paint()
          ..color = Colors.black.withValues(alpha: bottomOpacity)
          ..strokeWidth = 1,
      );
    }
  }

  @override
  bool shouldRepaint(_GlassEdgePainter oldDelegate) =>
      oldDelegate.radius != radius ||
      oldDelegate.opacity != opacity ||
      oldDelegate.bottomOpacity != bottomOpacity ||
      oldDelegate.borderColor != borderColor;
}

class CompanionBackdrop extends StatelessWidget {
  const CompanionBackdrop({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => SizedBox.expand(
    child: DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          stops: [0, .72],
          colors: [Color(0xFF162934), Color(0xFF080F18)],
        ),
      ),
      child: CustomPaint(
        // At near-clear settings the glow is directly behind text. Keep it
        // readable there without dulling the selected default appearance.
        painter: _BackdropDepthPainter(
          math.min(1.0, .78 + .22 * context.glass.surfaceOpacity / .6),
        ),
        child: child,
      ),
    ),
  );
}

class _BackdropDepthPainter extends CustomPainter {
  const _BackdropDepthPainter(this.lightStrength);

  final double lightStrength;

  Color _light(Color color) => color.withValues(alpha: color.a * lightStrength);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    final firstLight = Rect.fromCircle(
      center: Offset(size.width * .13, 0),
      radius: size.longestSide * .46,
    );
    canvas.drawCircle(
      firstLight.center,
      firstLight.width / 2,
      Paint()
        ..shader = RadialGradient(
          stops: [0, 1],
          colors: [_light(const Color(0x1F6CB7C8)), const Color(0x006CB7C8)],
        ).createShader(firstLight),
    );

    final secondLight = Rect.fromCircle(
      center: Offset(size.width * .90, 0),
      radius: size.longestSide * .40,
    );
    canvas.drawCircle(
      secondLight.center,
      secondLight.width / 2,
      Paint()
        ..shader = RadialGradient(
          stops: [0, 1],
          colors: [_light(const Color(0x1A2A6581)), const Color(0x002A6581)],
        ).createShader(secondLight),
    );

    // Decorative contour engraving, not geographic data. The centre stays
    // quiet for the working panels; only the exposed edges carry linework.
    for (final origin in [
      Offset(size.width * 1.04, size.height * .22),
      Offset(-size.width * .14, size.height * .94),
    ]) {
      for (var ring = 0; ring < 19; ring++) {
        final path = Path();
        final radius = 70.0 + ring * 24;
        for (var step = 0; step <= 160; step++) {
          final angle = step / 160 * math.pi * 2;
          final ripple =
              math.sin(angle * 3 + ring * .16) * 15 +
              math.cos(angle * 5 - ring * .11) * 8;
          final point =
              origin +
              Offset(
                math.cos(angle) * (radius + ripple) * 1.18,
                math.sin(angle) * (radius + ripple) * .72,
              );
          if (step == 0) {
            path.moveTo(point.dx, point.dy);
          } else {
            path.lineTo(point.dx, point.dy);
          }
        }
        canvas.drawPath(
          path,
          Paint()
            ..color = accent.withValues(
              alpha: (ring % 4 == 0 ? .065 : .026) * lightStrength,
            )
            ..style = PaintingStyle.stroke
            ..strokeWidth = ring % 4 == 0 ? 1 : .7,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_BackdropDepthPainter oldDelegate) =>
      lightStrength != oldDelegate.lightStrength;
}

Widget companionBackdropBuilder(BuildContext context, Widget? child) =>
    SizedBox.expand(
      child: Stack(
        fit: StackFit.expand,
        children: [
          const CompanionBackdrop(child: SizedBox.expand()),
          if (child != null) Positioned.fill(child: child),
        ],
      ),
    );

// Client item grades; colors checked against BDO Codex's grade frames.
Color? itemGradeColor(int? grade) => switch (grade) {
  0 => const Color(0xFFFFFFFF),
  1 => const Color(0xFF5FF369),
  2 => const Color(0xFF04B3F1),
  3 => const Color(0xFFF6C232),
  4 => const Color(0xFFFF7C00),
  5 => const Color(0xFFA070EF),
  _ => null,
};

ThemeData companionTheme({Object? opacityPercent}) {
  final glass = CompanionGlassTheme.fromPercent(opacityPercent);
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: Colors.transparent,
    fontFamily: 'Segoe UI',
    colorScheme: ColorScheme.dark(
      primary: accent,
      onPrimary: Color(0xFF071013),
      secondary: gold,
      surface: glass.panel,
      onSurface: ink,
      error: Color(0xFFFFB4A3),
      shadow: Colors.black.withValues(alpha: glass.shadowOpacity),
    ),
    shadowColor: Colors.black.withValues(alpha: glass.shadowOpacity),
    textTheme: const TextTheme(
      headlineLarge: TextStyle(
        fontSize: 32,
        fontWeight: FontWeight.w700,
        letterSpacing: -.7,
        color: ink,
      ),
      headlineSmall: TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w600,
        color: ink,
      ),
      titleLarge: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: ink,
      ),
      titleMedium: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: ink,
      ),
      bodyLarge: TextStyle(fontSize: 15, height: 1.45, color: ink),
      bodyMedium: TextStyle(fontSize: 14, height: 1.4, color: ink),
      bodySmall: TextStyle(fontSize: 14, height: 1.4, color: muted),
    ),
    tooltipTheme: TooltipThemeData(
      waitDuration: const Duration(milliseconds: 300),
      textStyle: const TextStyle(fontSize: 14, height: 1.4, color: ink),
      textAlign: TextAlign.left,
      constraints: const BoxConstraints(maxWidth: 360),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: glass.popup,
        border: Border.all(color: _glassEdge.withValues(alpha: .7)),
        borderRadius: BorderRadius.circular(8),
        boxShadow: const [
          BoxShadow(
            color: Color(0x66000000),
            blurRadius: 16,
            offset: Offset(0, 6),
          ),
        ],
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: glass.inset,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: glass.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: glass.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: accent, width: 1.5),
      ),
    ),
    dividerColor: glass.line,
    dividerTheme: DividerThemeData(color: glass.line, thickness: 1),
    cardTheme: CardThemeData(
      color: glass.panel,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: glass.strongLine),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: glass.popup,
      barrierColor: Colors.black.withValues(alpha: glass.backdropOpacity),
      surfaceTintColor: Colors.transparent,
    ),
    popupMenuTheme: PopupMenuThemeData(
      // Menus are reading surfaces, not part of the transparent map chrome.
      color: glass.popup,
      surfaceTintColor: Colors.transparent,
      shadowColor: const Color(0x66000000),
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: _glassEdge.withValues(alpha: .7)),
      ),
      menuPadding: const EdgeInsets.symmetric(vertical: 6),
      textStyle: const TextStyle(fontSize: 14, height: 1.35, color: ink),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 17),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        backgroundBuilder: (context, states, child) =>
            states.contains(WidgetState.disabled)
            ? child ?? const SizedBox.shrink()
            : _GlassControlInk(
                primary: true,
                radius: 10,
                child: child ?? const SizedBox.shrink(),
              ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: ink,
        side: BorderSide(color: glass.line),
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 15),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
    chipTheme: ChipThemeData(
      side: BorderSide(color: glass.line),
      backgroundColor: glass.row,
      selectedColor: glass.active,
      labelStyle: const TextStyle(color: ink),
      secondaryLabelStyle: const TextStyle(color: ink),
      checkmarkColor: accent,
    ),
    scrollbarTheme: const ScrollbarThemeData(
      thumbVisibility: WidgetStatePropertyAll(false),
      trackVisibility: WidgetStatePropertyAll(false),
    ),
    extensions: [glass],
  );
}

class GameIcon extends StatelessWidget {
  const GameIcon(
    this.path, {
    super.key,
    this.size = 36,
    this.grade,
    this.backgroundColor,
  });
  final String path;
  final double size;
  final int? grade;
  final Color? backgroundColor;
  @override
  Widget build(BuildContext context) {
    final artwork = path.isEmpty
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.all(2),
            child: Image.asset(
              path,
              package: gatheringAssetPackage,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.medium,
              errorBuilder: (_, error, stack) => Tooltip(
                message: 'Game artwork unavailable',
                child: Center(
                  child: Text(
                    '?',
                    style: TextStyle(color: muted, fontSize: size * .45),
                  ),
                ),
              ),
            ),
          );
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: backgroundColor,
        gradient: backgroundColor == null
            ? context.glass.iconWellGradient
            : null,
        borderRadius: BorderRadius.circular(7),
      ),
      foregroundDecoration: switch (itemGradeColor(grade)) {
        final color? => BoxDecoration(
          border: Border.all(color: color, width: 1.5),
          borderRadius: BorderRadius.circular(7),
        ),
        null => null,
      },
      child: backgroundColor != null
          ? artwork
          : DecoratedBox(
              decoration: BoxDecoration(
                gradient: context.glass.artworkHighlight(),
                borderRadius: BorderRadius.circular(7),
              ),
              child: CustomPaint(
                foregroundPainter: _GlassEdgePainter(
                  7,
                  .13 * context.glass.effectStrength,
                  bottomOpacity: .5 * context.glass.effectStrength,
                ),
                child: artwork,
              ),
            ),
    );
  }
}

class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.title,
    this.subtitle,
    required this.child,
    this.trailing,
  });
  final String title;
  final String? subtitle;
  final Widget child;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              ?trailing,
            ],
          ),
          if (subtitle != null)
            Padding(
              padding: const EdgeInsets.only(top: 5),
              child: Text(
                subtitle!,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    ),
  );
}

String countText(num n) => n.toInt().toString().replaceAllMapped(
  RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
  (m) => '${m[1]},',
);
String numberText(num n) =>
    n == n.roundToDouble() ? n.toInt().toString() : n.toStringAsFixed(1);
String formatDurationMinutes(num minutes) => minutes.isFinite && minutes >= 0
    ? durationText((minutes * 60).round())
    : '—';

String durationText(int seconds) {
  if (seconds <= 0) return '0 s';
  final days = seconds ~/ 86400;
  final hours = seconds % 86400 ~/ 3600;
  final minutes = seconds % 3600 ~/ 60;
  final remainder = seconds % 60;
  return [
    if (days > 0) '$days ${days == 1 ? 'day' : 'days'}',
    if (hours > 0) '$hours h',
    if (minutes > 0) '$minutes min',
    if (remainder > 0) '$remainder s',
  ].join(' ');
}
