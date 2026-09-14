import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../visual/visual.dart';
import 'opportunities_glass_material.dart';

/// Feature-owned materials; none of these values comes from Craft Profile.
abstract final class OpportunitiesVisualSpec {
  static const id = 'opportunities-smoked-glass';
  // Card-only density; never scale the toolbar or the user's text setting.
  static const recipeCardScale = .9;
  static const palette = ThemePalette(
    canvas: Color(0xFF0D1926),
    canvasDeep: Color(0xFF0A1420),
    surface: Color(0xFF142536),
    surfaceRaised: Color(0xFF1A2D3E),
    surfaceInset: Color(0xFF102030),
    primary: Color(0xFF78BDB9),
    primaryBright: Color(0xFFACE0DA),
    secondary: Color(0xFFB5BEDC),
    trim: Color(0xFF314A5E),
    trimBright: Color(0xFF637F92),
    text: Color(0xFFEDF2F7),
    textMuted: Color(0xFFB7C6D5),
    success: Color(0xFF9CDEB7),
    warning: Color(0xFFEDC38C),
    danger: Color(0xFFF2A39A),
    shadow: Color(0x9E000000),
    specular: Color(0x66C6E8F5),
  );

  static const typography = ThemeTypography(
    display: TextStyle(
      fontFamily: 'Segoe UI',
      fontSize: 28,
      fontWeight: FontWeight.w600,
      letterSpacing: -.5,
      height: 1.12,
      color: Color(0xFFEDF2F7),
    ),
    section: TextStyle(
      fontFamily: 'Segoe UI',
      fontSize: 18,
      fontWeight: FontWeight.w600,
      letterSpacing: -.2,
      height: 1.18,
      color: Color(0xFFEDF2F7),
    ),
    body: TextStyle(
      fontFamily: 'Segoe UI',
      fontSize: 14,
      height: 1.3,
      color: Color(0xFFEDF2F7),
      fontFeatures: [FontFeature.tabularFigures()],
    ),
    meta: TextStyle(
      fontFamily: 'Segoe UI',
      fontSize: 12,
      height: 1.25,
      color: Color(0xFFB7C6D5),
      fontFeatures: [FontFeature.tabularFigures()],
    ),
    label: TextStyle(
      fontFamily: 'Segoe UI',
      fontSize: 12,
      fontWeight: FontWeight.w500,
      height: 1.2,
      color: Color(0xFFB7C6D5),
    ),
    button: TextStyle(
      fontFamily: 'Segoe UI',
      fontSize: 14,
      fontWeight: FontWeight.w500,
      height: 1.15,
      color: Color(0xFFEDF2F7),
    ),
  );

  static const geometry = ThemeGeometry(
    titleStripHeight: 72,
    workspacePadding: EdgeInsets.fromLTRB(24, 18, 24, 24),
    sidebarWidth: 0,
    contentGap: 14,
    panelRadius: 12,
    commandRadius: 0,
    cardRadius: 12,
    buttonRadius: 8,
    navigationRadius: 9,
    fieldRadius: 8,
    compactBreakpoint: Size(980, 700),
    minimumWindowSize: Size(760, 560),
  );

  static const materials = ThemeMaterials(
    canvas: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF10232E), Color(0xFF0D1926), Color(0xFF0A1420)],
      stops: [0, .5, 1],
    ),
    surface: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF172B3A), Color(0xFF142536), Color(0xFF122333)],
      stops: [0, .45, 1],
    ),
    surfaceRaised: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        Color(0xFF1D3141),
        Color(0xFF1B2F40),
        Color(0xFF1A2D3E),
        Color(0xFF182A3A),
      ],
      stops: [0, .16, .58, 1],
    ),
    primary: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        Color(0xFF294B52),
        Color(0xFF26454D),
        Color(0xFF203E47),
        Color(0xFF1C3541),
      ],
      stops: [0, .18, .76, 1],
    ),
    secondary: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF1D3243), Color(0xFF182A3B), Color(0xFF152636)],
      stops: [0, .75, 1],
    ),
    modalScrim: Color(0xCA030B19),
    lowShadow: [],
    highShadow: [
      BoxShadow(
        color: Color(0xA3000000),
        blurRadius: 42,
        offset: Offset(0, 18),
      ),
      BoxShadow(color: Color(0x21000000), blurRadius: 4, offset: Offset(0, 2)),
    ],
  );

  // Existing tooltip callers use a Gradient contract; both stops form one
  // opaque reading colour, independent of the scene beneath the overlay.
  static const overlay = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF1A2D3E), Color(0xFF1A2D3E)],
  );

  // The artwork-led recipe card is distinct from neutral detail/readout panels.
  // Its depth comes from one soft shadow and the integrated artwork rail.
  static const recipeCard = BoxDecoration(
    color: Color(0xFF162A3A),
    borderRadius: BorderRadius.all(Radius.circular(12)),
    border: Border.fromBorderSide(BorderSide(color: Color(0xFF314A5E))),
    boxShadow: [
      BoxShadow(color: Color(0x24030A10), blurRadius: 18, offset: Offset(0, 7)),
    ],
  );
  static const recipeArtworkRail = BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF223F4B), Color(0xFF193140)],
    ),
    border: Border(right: BorderSide(color: Color(0xFF314A5E))),
  );
  static const recipeFooter = BoxDecoration(
    color: Color(0xFF132635),
    border: Border(top: BorderSide(color: Color(0xFF314A5E))),
  );

  static const spec = ThemeSpec(
    id: id,
    displayName: 'Quiet Navy',
    // Only neutral Material theme plumbing is shared with the Standard family.
    // OpportunitySurface and OpportunityButton own every visible material.
    family: RetainedVisualFamily.standard,
    layoutProfile: ThemeLayoutProfile.standardWorkspace,
    brightness: Brightness.dark,
    palette: palette,
    typography: typography,
    geometry: geometry,
    materials: materials,
    motion: ThemeMotionCapabilities(
      interactionDuration: Duration(milliseconds: 140),
      supportsAtmosphere: false,
      supportsButtonEffects: false,
      supportsOrnament: false,
    ),
  );
}

/// Retains the public surface contract without inheriting calculator artwork.
class OpportunitySurface extends AppSurface {
  const OpportunitySurface({
    required super.child,
    super.spec,
    super.role,
    super.tone,
    super.padding,
    super.semanticLabel,
    super.ornamentIndex,
    super.clipBehavior,
    super.key,
    this.decoration,
  });

  final BoxDecoration? decoration;

  @override
  Widget build(BuildContext context) {
    final tokens = spec ?? OpportunitiesVisualSpec.spec;
    final p = tokens.palette;
    final modal =
        role == AppSurfaceRole.modal ||
        role == AppSurfaceRole.popup ||
        role == AppSurfaceRole.tooltip;
    final flat =
        role == AppSurfaceRole.layout || role == AppSurfaceRole.commandBand;
    final row = role == AppSurfaceRole.row;
    final raised = modal || role == AppSurfaceRole.panel;
    final radius = flat
        ? 0.0
        : modal
        ? tokens.geometry.panelRadius
        : tokens.geometry.cardRadius;
    final toneColor = tone == AppSurfaceTone.neutral ? null : p.forTone(tone);
    final materialDecoration =
        decoration ??
        BoxDecoration(
          color: flat
              ? Colors.transparent
              : row
              ? p.surfaceInset
              : raised
              ? p.surfaceRaised
              : p.surface,
          borderRadius: BorderRadius.circular(radius),
          border: flat
              ? null
              : Border.all(color: (toneColor ?? p.trim).withAlpha(160)),
        );
    Widget result = DecoratedBox(
      key: AppSurface.materialKey,
      decoration: materialDecoration,
      child: Material(
        type: MaterialType.transparency,
        child: Padding(
          padding:
              padding ??
              (flat ? EdgeInsets.zero : EdgeInsets.all(row ? 8 : 12)),
          child: DefaultTextStyle.merge(
            style: tokens.typography.body,
            child: child,
          ),
        ),
      ),
    );
    if (clipBehavior != Clip.none) {
      result = ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        clipBehavior: clipBehavior,
        child: result,
      );
    }
    return semanticLabel == null
        ? result
        : Semantics(container: true, label: semanticLabel, child: result);
  }
}

/// A stationary tint and keyboard outline; interactions never lift the card.
class OpportunityCardMotion extends StatefulWidget {
  const OpportunityCardMotion({required this.child, super.key});
  final Widget child;

  @override
  State<OpportunityCardMotion> createState() => _OpportunityCardMotionState();
}

class _OpportunityCardMotionState extends State<OpportunityCardMotion> {
  bool _hovered = false, _focused = false, _pressed = false;

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.disableAnimationsOf(context);
    final active = _hovered || _focused;
    return Focus(
      canRequestFocus: false,
      onFocusChange: (value) => setState(() => _focused = value),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() {
          _hovered = false;
          _pressed = false;
        }),
        child: Listener(
          onPointerDown: (event) {
            if (event.buttons == 1) setState(() => _pressed = true);
          },
          onPointerUp: (_) => setState(() => _pressed = false),
          onPointerCancel: (_) => setState(() => _pressed = false),
          child: AnimatedContainer(
            duration: reduced
                ? Duration.zero
                : const Duration(milliseconds: 140),
            curve: Curves.easeOutCubic,
            foregroundDecoration: BoxDecoration(
              color: OpportunitiesVisualSpec.palette.primary.withAlpha(
                _pressed ? 10 : (active ? 5 : 0),
              ),
              borderRadius: BorderRadius.circular(
                OpportunitiesVisualSpec.geometry.cardRadius,
              ),
              border: Border.all(
                color: _focused
                    ? OpportunitiesVisualSpec.palette.primaryBright
                    : Colors.transparent,
              ),
            ),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

class OpportunityComparisonRowFinish extends StatelessWidget {
  const OpportunityComparisonRowFinish({
    required this.child,
    this.alternate = false,
    super.key,
  });

  final Widget child;
  final bool alternate;

  @override
  Widget build(BuildContext context) => Ink(
    decoration: _ComparisonRowDecoration(
      color: alternate
          ? OpportunitiesVisualSpec.palette.surfaceRaised
          : OpportunitiesVisualSpec.palette.surface,
      border: const Border(bottom: BorderSide(color: Color(0x80314A5E))),
    ),
    child: child,
  );
}

class _ComparisonRowDecoration extends BoxDecoration {
  const _ComparisonRowDecoration({required super.color, required super.border});

  // Ink normally turns painted border widths into layout padding.
  @override
  EdgeInsetsGeometry get padding => EdgeInsets.zero;
}

/// Native focus/keyboard behavior, with a small feature-owned material palette.
class OpportunityButton extends AppButton {
  const OpportunityButton({
    required super.child,
    required super.onPressed,
    super.onPressedAsync,
    super.spec,
    super.role,
    super.selected,
    super.showNavigationOrnament,
    super.minimumSize,
    super.padding,
    super.focusNode,
    super.autofocus,
    super.semanticLabel,
    super.tooltip,
    super.key,
  });

  factory OpportunityButton.label(
    String label, {
    required VoidCallback? onPressed,
    Future<void> Function()? onPressedAsync,
    ThemeSpec? spec,
    AppButtonRole role = AppButtonRole.secondary,
    bool selected = false,
    bool showNavigationOrnament = true,
    Size? minimumSize,
    EdgeInsetsGeometry? padding,
    FocusNode? focusNode,
    bool autofocus = false,
    String? semanticLabel,
    String? tooltip,
    Key? key,
  }) => OpportunityButton(
    key: key,
    onPressed: onPressed,
    onPressedAsync: onPressedAsync,
    spec: spec,
    role: role,
    selected: selected,
    showNavigationOrnament: showNavigationOrnament,
    minimumSize: minimumSize,
    padding: padding,
    focusNode: focusNode,
    autofocus: autofocus,
    semanticLabel: semanticLabel ?? label,
    tooltip: tooltip,
    child: Text(label),
  );

  factory OpportunityButton.icon({
    required Widget icon,
    required VoidCallback? onPressed,
    Future<void> Function()? onPressedAsync,
    required String semanticLabel,
    ThemeSpec? spec,
    FocusNode? focusNode,
    bool autofocus = false,
    String? tooltip,
    Key? key,
  }) => OpportunityButton(
    key: key,
    onPressed: onPressed,
    onPressedAsync: onPressedAsync,
    spec: spec,
    role: AppButtonRole.icon,
    focusNode: focusNode,
    autofocus: autofocus,
    semanticLabel: semanticLabel,
    tooltip: tooltip,
    child: icon,
  );

  @override
  State<AppButton> createState() => _OpportunityButtonState();
}

class _OpportunityButtonState extends State<AppButton> {
  final _ownedFocus = FocusNode();
  bool _hovered = false;
  bool _pressed = false;
  bool _focused = false;
  bool get _enabled =>
      widget.onPressed != null || widget.onPressedAsync != null;

  @override
  void didUpdateWidget(AppButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_enabled) {
      _hovered = false;
      _pressed = false;
    }
  }

  @override
  void dispose() {
    _ownedFocus.dispose();
    super.dispose();
  }

  void _activate() {
    if (!_enabled) return;
    if (widget.onPressedAsync case final callback?) {
      unawaited(callback());
    } else {
      widget.onPressed?.call();
    }
  }

  void _state({bool? hover, bool? press, bool? focus}) {
    if (_hovered == (hover ?? _hovered) &&
        _pressed == (press ?? _pressed) &&
        _focused == (focus ?? _focused)) {
      return;
    }
    setState(() {
      _hovered = hover ?? _hovered;
      _pressed = press ?? _pressed;
      _focused = focus ?? _focused;
    });
  }

  @override
  Widget build(BuildContext context) {
    final spec = widget.spec ?? OpportunitiesVisualSpec.spec;
    final p = spec.palette;
    final active = widget.selected || widget.role == AppButtonRole.primary;
    final danger = widget.role == AppButtonRole.danger;
    final icon = widget.role == AppButtonRole.icon;
    final quiet = icon || widget.role == AppButtonRole.infoChip;
    final highlight = _enabled && (_hovered || _focused);
    final foreground = !_enabled
        ? p.textMuted.withAlpha(112)
        : danger
        ? p.danger
        : p.text;
    final border = !_enabled
        ? p.trim.withAlpha(45)
        : _focused
        ? p.primaryBright
        : active
        ? p.primaryBright.withAlpha(190)
        : highlight
        ? p.trimBright.withAlpha(175)
        : quiet
        ? Colors.transparent
        : p.trim.withAlpha(95);
    final fill = !_enabled
        ? p.surfaceInset.withAlpha(130)
        : danger
        ? p.danger.withAlpha(highlight ? 40 : 24)
        : active
        ? Color.alphaBlend(
            p.primary.withAlpha(_pressed ? 45 : 32),
            p.surfaceInset,
          )
        : _pressed
        ? p.surface
        : highlight
        ? p.surfaceRaised
        : quiet
        ? Colors.transparent
        : p.surfaceInset;
    final requestedMin =
        widget.minimumSize ??
        (icon ? const Size.square(40) : const Size(0, 40));
    final min = Size(
      math.max(icon ? 40 : 0, requestedMin.width),
      math.max(40, requestedMin.height),
    );
    final radius =
        widget.role == AppButtonRole.navigation ||
            widget.role == AppButtonRole.modeSelector
        ? spec.geometry.navigationRadius
        : spec.geometry.buttonRadius;
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : spec.motion.interactionDuration;
    Widget button = FocusableActionDetector(
      focusNode: widget.focusNode ?? _ownedFocus,
      autofocus: widget.autofocus,
      enabled: _enabled,
      mouseCursor: _enabled
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      onShowHoverHighlight: (value) => _state(hover: value),
      onShowFocusHighlight: (value) => _state(focus: value),
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
      },
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            _activate();
            return null;
          },
        ),
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: !_enabled ? null : (_) => _state(press: true),
        onTapUp: !_enabled ? null : (_) => _state(press: false),
        onTapCancel: !_enabled ? null : () => _state(press: false),
        onTap: !_enabled ? null : _activate,
        child: AnimatedContainer(
          key: AppButton.materialKey,
          duration: duration,
          curve: Curves.easeOutCubic,
          constraints: BoxConstraints(
            minWidth: min.width,
            minHeight: min.height,
          ),
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: border),
          ),
          child: Padding(
            padding:
                widget.padding ??
                (icon
                    ? const EdgeInsets.all(6)
                    : const EdgeInsets.symmetric(horizontal: 10, vertical: 6)),
            child: Opacity(
              opacity: _pressed && _enabled ? .88 : 1,
              child: IconTheme.merge(
                data: IconThemeData(color: foreground, size: 18),
                child: DefaultTextStyle.merge(
                  style: spec.typography.button.copyWith(
                    color: foreground,
                    fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                  ),
                  child: Center(
                    widthFactor: 1,
                    heightFactor: 1,
                    child: widget.child,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    button = Semantics(
      button: true,
      enabled: _enabled,
      selected: widget.selected,
      label: widget.semanticLabel,
      onTap: _enabled ? _activate : null,
      excludeSemantics: widget.semanticLabel != null,
      child: button,
    );
    return widget.tooltip == null
        ? button
        : Tooltip(message: widget.tooltip!, child: button);
  }
}

class OpportunityFilterButton extends AppFilterButton {
  const OpportunityFilterButton({
    required super.selected,
    required super.label,
    required super.onChanged,
    super.semanticLabel,
    super.key,
  });

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    toggled: selected,
    child: OpportunityButton(
      role: AppButtonRole.optionPill,
      selected: selected,
      minimumSize: const Size(0, 40),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      semanticLabel: semanticLabel ?? label,
      onPressed: onChanged == null ? null : () => onChanged!(!selected),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            selected ? Icons.check_circle_outline : Icons.circle_outlined,
            size: 18,
          ),
          const SizedBox(width: 6),
          Flexible(child: Text(label)),
        ],
      ),
    ),
  );
}

/// Fixed local input materials, retaining editing and keyboard contracts.
class OpportunityTextField extends AppTextField {
  const OpportunityTextField({
    this.flat = false,
    super.controller,
    super.focusNode,
    super.label,
    super.hintText,
    super.onChanged,
    super.onSubmitted,
    super.onKeyEvent,
    super.onTap,
    super.keyboardType,
    super.inputFormatters,
    super.textAlign,
    super.textStyle,
    super.hintStyle,
    super.contentPadding,
    super.textAlignVertical,
    super.enabled,
    super.obscureText,
    super.maxLines,
    super.minLines,
    super.prefixIcon,
    super.suffixIcon,
    super.semanticLabel,
    super.emphasis,
    super.minimumHeight,
    super.key,
  });

  /// Numeric/search controls can reserve a full-height suffix without adding
  /// the ordinary suffix's minimum width.
  final bool flat;

  @override
  Widget build(BuildContext context) {
    const spec = OpportunitiesVisualSpec.spec;
    const p = OpportunitiesVisualSpec.palette;
    final controlStyle = textStyle ?? spec.typography.body;
    final scaledLine =
        MediaQuery.textScalerOf(context).scale(controlStyle.fontSize ?? 14) *
        (controlStyle.height ?? 1.3);
    final minHeight = math.max(
      math.max(minimumHeight ?? 40.0, 40.0),
      scaledLine + 16,
    );
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(spec.geometry.fieldRadius),
      borderSide: BorderSide(color: p.trim.withAlpha(190)),
    );
    Widget field = TextField(
      controller: controller,
      focusNode: focusNode,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      onTap: onTap,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      textAlign: textAlign,
      textAlignVertical:
          textAlignVertical ??
          (maxLines == 1 ? TextAlignVertical.center : TextAlignVertical.top),
      enabled: enabled,
      obscureText: obscureText,
      maxLines: maxLines,
      minLines: minLines,
      cursorColor: p.primaryBright,
      style: controlStyle,
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        fillColor: emphasis == AppTextFieldEmphasis.subdued
            ? p.canvasDeep.withAlpha(180)
            : p.surfaceInset,
        labelText: label,
        hintText: hintText,
        labelStyle: spec.typography.label,
        // InputDecorator scales floating labels by .75. Keep the visible
        // label at the same size as the resting label.
        floatingLabelStyle: spec.typography.label.copyWith(
          fontSize: spec.typography.label.fontSize! / .75,
        ),
        hintStyle: hintStyle ?? controlStyle.copyWith(color: p.textMuted),
        contentPadding:
            contentPadding ??
            const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        prefixIcon: prefixIcon,
        suffixIcon: suffixIcon ?? (flat ? const SizedBox.shrink() : null),
        prefixIconConstraints: const BoxConstraints(
          minWidth: 34,
          minHeight: 34,
        ),
        suffixIconConstraints: BoxConstraints(
          minWidth: flat && suffixIcon == null ? 0 : 34,
          minHeight: flat ? minHeight : 34,
        ),
        constraints: BoxConstraints(minHeight: minHeight),
        border: border,
        enabledBorder: border,
        focusedBorder: border.copyWith(
          borderSide: BorderSide(color: p.primaryBright),
        ),
        disabledBorder: border.copyWith(
          borderSide: BorderSide(color: p.trim.withAlpha(60)),
        ),
      ),
    );
    if (onKeyEvent != null) {
      field = Focus(
        canRequestFocus: false,
        skipTraversal: true,
        includeSemantics: false,
        onKeyEvent: onKeyEvent,
        child: field,
      );
    }
    return semanticLabel == null
        ? field
        : Semantics(textField: true, label: semanticLabel, child: field);
  }
}

class OpportunityDeskBackdrop extends StatelessWidget {
  const OpportunityDeskBackdrop({super.key});

  @override
  Widget build(BuildContext context) => const RepaintBoundary(
    child: IgnorePointer(
      child: CustomPaint(painter: OpportunityGlassBackdrop()),
    ),
  );
}

/// One restrained entrance; never restarts for incoming market rows.
class OpportunityEntrance extends StatefulWidget {
  const OpportunityEntrance({required this.child, super.key});
  final Widget child;

  @override
  State<OpportunityEntrance> createState() => _OpportunityEntranceState();
}

class _OpportunityEntranceState extends State<OpportunityEntrance>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = 1;
      _started = true;
    } else if (!_started) {
      _started = true;
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: _controller.drive(CurveTween(curve: Curves.easeOutCubic)),
    child: SlideTransition(
      position: _controller.drive(
        Tween(
          begin: const Offset(0, .015),
          end: Offset.zero,
        ).chain(CurveTween(curve: Curves.easeOutCubic)),
      ),
      child: widget.child,
    ),
  );
}
