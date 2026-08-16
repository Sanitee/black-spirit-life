import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../foundations/theme_spec.dart';
import '../illuminated_ledger/ledger_ornament_painters.dart';
import '../sakura_night_garden/sakura_material_painters.dart';
import '../sakura_night_garden/sakura_spec.dart';
import '../standard/standard_spec.dart';
import 'button_effect_scope.dart';

const Color _ledgerAccentBorder = Color(0xFFB9903E);
const Color _ledgerInactiveBorder = Color(0x8A7A5B2A);
const List<BoxShadow> _ledgerButtonShellShadow = <BoxShadow>[
  BoxShadow(color: Color(0x4A352516), blurRadius: 6, offset: Offset(0, 3)),
];
const List<BoxShadow> _sakuraButtonShellShadow = <BoxShadow>[
  BoxShadow(color: Color(0x91000000), blurRadius: 7, offset: Offset(0, 3)),
  BoxShadow(color: Color(0x26A66C69), blurRadius: 1, offset: Offset(0, -1)),
];

enum AppButtonRole {
  primary,
  secondary,
  navigation,
  sidebarNavigation,
  modeSelector,
  optionPill,
  ingredientToggle,
  infoChip,
  icon,
  danger,
  completion,
}

/// Retained button primitive with explicit and layout-stable interaction states.
class AppButton extends StatefulWidget {
  const AppButton({
    required this.child,
    required this.onPressed,
    this.onPressedAsync,
    this.spec,
    this.role = AppButtonRole.secondary,
    this.selected = false,
    this.showNavigationOrnament = true,
    this.minimumSize,
    this.padding,
    this.focusNode,
    this.autofocus = false,
    this.semanticLabel,
    this.tooltip,
    super.key,
  }) : assert(onPressed == null || onPressedAsync == null);

  factory AppButton.label(
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
  }) => AppButton(
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

  factory AppButton.icon({
    required Widget icon,
    required VoidCallback? onPressed,
    Future<void> Function()? onPressedAsync,
    required String semanticLabel,
    ThemeSpec? spec,
    FocusNode? focusNode,
    bool autofocus = false,
    String? tooltip,
    Key? key,
  }) => AppButton(
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

  final Widget child;
  final VoidCallback? onPressed;
  final Future<void> Function()? onPressedAsync;
  final ThemeSpec? spec;
  final AppButtonRole role;
  final bool selected;
  final bool showNavigationOrnament;
  final Size? minimumSize;
  final EdgeInsetsGeometry? padding;
  final FocusNode? focusNode;
  final bool autofocus;
  final String? semanticLabel;
  final String? tooltip;

  static const Key materialKey = ValueKey<String>('app-button-material');

  @override
  State<AppButton> createState() => _AppButtonState();
}

class _AppButtonState extends State<AppButton> {
  late final FocusNode _ownedFocusNode = FocusNode();
  bool _hovered = false;
  bool _pressed = false;
  bool _focused = false;

  bool get _enabled =>
      widget.onPressed != null || widget.onPressedAsync != null;
  FocusNode get _focusNode => widget.focusNode ?? _ownedFocusNode;

  @override
  void didUpdateWidget(AppButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_enabled && (_hovered || _pressed)) {
      _hovered = false;
      _pressed = false;
    }
  }

  @override
  void dispose() {
    _ownedFocusNode.dispose();
    super.dispose();
  }

  void _setHovered(bool value) {
    if (_hovered == value || !_enabled) return;
    setState(() => _hovered = value);
  }

  void _setFocused(bool value) {
    if (_focused == value) return;
    setState(() => _focused = value);
  }

  void _setPressed(bool value) {
    if (_pressed == value || !_enabled) return;
    setState(() => _pressed = value);
  }

  Object? _keyboardActivate(ActivateIntent intent) {
    if (!_enabled) return null;
    setState(() => _pressed = true);
    _activate();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _pressed = false);
    });
    return null;
  }

  void _activate() {
    if (widget.onPressedAsync case final callback?) {
      unawaited(callback());
    } else {
      widget.onPressed?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = widget.spec ?? context.visualTheme;
    final effects = ButtonEffectScope.maybeOf(context);
    // A theme capability is authoritative for both the animated overlay and
    // any effect-derived fill underneath it. This keeps Classic controls
    // quiet even when an older saved profile still contains button effects.
    final effectSettings = tokens.motion.supportsButtonEffects
        ? effects?.settings
        : null;
    final visual = _AppButtonVisual.resolve(
      spec: tokens,
      standard: context.standardVisual,
      effects: effectSettings,
      role: widget.role,
      selected: widget.selected,
      enabled: _enabled,
      hovered: _hovered,
      pressed: _pressed,
      focused: _focused,
    );
    final minSize = widget.minimumSize ?? _defaultMinimumSize(tokens);
    final contentPadding = widget.padding ?? _defaultPadding(tokens);
    final materialPadding = tokens.isSakuraNightGarden
        ? EdgeInsets.zero
        : contentPadding;
    final materialInset =
        tokens.isSakuraNightGarden && widget.role == AppButtonRole.completion
        ? const EdgeInsets.all(3)
        : EdgeInsets.zero;
    final ledgerSidebarDivider =
        tokens.isIlluminatedLedger &&
        widget.role == AppButtonRole.sidebarNavigation &&
        !widget.selected;

    Widget buildMaterial() {
      final material = AnimatedContainer(
        key: AppButton.materialKey,
        duration: tokens.motion.interactionDuration,
        curve: Curves.easeOutCubic,
        padding: materialPadding,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          gradient: visual.gradient,
          image: tokens.isSakuraNightGarden
              ? DecorationImage(
                  image: const AssetImage(
                    'assets/sakura/materials/charcoal-plum-lacquer.png',
                  ),
                  fit: BoxFit.cover,
                  alignment: const Alignment(0.12, -0.18),
                  opacity:
                      widget.selected || widget.role == AppButtonRole.primary
                      ? 0.19
                      : 0.13,
                  filterQuality: FilterQuality.medium,
                  isAntiAlias: true,
                )
              : null,
          borderRadius: BorderRadius.circular(visual.radius),
          border: ledgerSidebarDivider
              ? Border(
                  bottom: BorderSide(
                    color: visual.borderColor,
                    width: visual.borderWidth,
                  ),
                )
              : Border.all(
                  color: visual.borderColor,
                  width: visual.borderWidth,
                ),
          boxShadow: visual.shadows,
        ),
        child: _ButtonVisualLayers(
          tokens: tokens,
          visual: visual,
          role: widget.role,
          selected: widget.selected,
          showNavigationOrnament: widget.showNavigationOrnament,
          enabled: _enabled,
          hovered: _hovered,
          pressed: _pressed,
          focused: _focused,
          child: Padding(
            padding: tokens.isSakuraNightGarden
                ? contentPadding
                : EdgeInsets.zero,
            child: Center(
              widthFactor: 1,
              heightFactor: 1,
              child: IconTheme(
                data: IconThemeData(color: visual.foreground, size: 17),
                child: DefaultTextStyle(
                  style: tokens.typography.button.copyWith(
                    color: visual.foreground,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  child: widget.child,
                ),
              ),
            ),
          ),
        ),
      );
      final supportsEffects =
          tokens.motion.supportsButtonEffects &&
          (widget.role == AppButtonRole.sidebarNavigation ||
              widget.role == AppButtonRole.modeSelector);
      if (!supportsEffects ||
          effects == null ||
          effects.settings.effect == 'quiet') {
        return material;
      }
      final effectInset = visual.borderWidth;
      final effectRadius = (visual.radius - effectInset).clamp(
        0.0,
        visual.radius,
      );
      return Stack(
        fit: StackFit.expand,
        clipBehavior: Clip.hardEdge,
        children: <Widget>[
          material,
          Positioned.fill(
            left: effectInset,
            top: effectInset,
            right: effectInset,
            bottom: effectInset,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(effectRadius),
              clipBehavior: Clip.antiAlias,
              child: IgnorePointer(
                child: RepaintBoundary(
                  child: CustomPaint(
                    foregroundPainter: ButtonEffectPainter.animated(
                      settings: effects.settings,
                      clock: effects.clock,
                      active:
                          widget.selected ||
                          widget.role == AppButtonRole.primary ||
                          widget.role == AppButtonRole.completion,
                    ),
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    }

    Widget result = Semantics(
      button: true,
      enabled: _enabled,
      selected: widget.selected,
      label: widget.semanticLabel,
      child: FocusableActionDetector(
        enabled: _enabled,
        focusNode: _focusNode,
        autofocus: widget.autofocus,
        mouseCursor: _enabled
            ? SystemMouseCursors.click
            : SystemMouseCursors.forbidden,
        onShowHoverHighlight: _setHovered,
        onShowFocusHighlight: _setFocused,
        shortcuts: const <ShortcutActivator, Intent>{
          SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
        },
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: _keyboardActivate,
          ),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: _enabled
              ? (_) {
                  _focusNode.requestFocus();
                  _setPressed(true);
                }
              : null,
          onTapUp: _enabled ? (_) => _setPressed(false) : null,
          onTapCancel: _enabled ? () => _setPressed(false) : null,
          onTap: _enabled ? _activate : null,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minWidth: minSize.width,
              minHeight: minSize.height,
            ),
            child: materialInset == EdgeInsets.zero
                ? buildMaterial()
                : Padding(padding: materialInset, child: buildMaterial()),
          ),
        ),
      ),
    );
    if (widget.tooltip case final message?) {
      result = Tooltip(message: message, child: result);
    }
    return result;
  }

  Size _defaultMinimumSize(ThemeSpec tokens) {
    if (tokens.usesDenseSplitLayout) {
      return switch (widget.role) {
        AppButtonRole.icon => const Size(46, 38),
        AppButtonRole.completion => const Size.square(46),
        _ => const Size(0, 38),
      };
    }
    return switch (widget.role) {
      AppButtonRole.sidebarNavigation => const Size(0, 52),
      AppButtonRole.modeSelector => const Size(0, 46),
      AppButtonRole.infoChip => const Size.square(20),
      AppButtonRole.icon => const Size(46, 38),
      AppButtonRole.completion => const Size.square(48),
      _ => const Size(0, 38),
    };
  }

  EdgeInsetsGeometry _defaultPadding(ThemeSpec tokens) {
    if (tokens.usesDenseSplitLayout) {
      return switch (widget.role) {
        AppButtonRole.icon => const EdgeInsets.symmetric(
          horizontal: 11,
          vertical: 8,
        ),
        AppButtonRole.completion => EdgeInsets.zero,
        _ => const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      };
    }
    return switch (widget.role) {
      AppButtonRole.sidebarNavigation => const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 11,
      ),
      AppButtonRole.modeSelector => const EdgeInsets.symmetric(
        horizontal: 18,
        vertical: 10,
      ),
      AppButtonRole.optionPill => const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 7,
      ),
      AppButtonRole.infoChip => EdgeInsets.zero,
      AppButtonRole.icon => const EdgeInsets.symmetric(
        horizontal: 11,
        vertical: 8,
      ),
      AppButtonRole.completion => EdgeInsets.zero,
      _ => const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
    };
  }
}

class _ButtonVisualLayers extends StatelessWidget {
  const _ButtonVisualLayers({
    required this.tokens,
    required this.visual,
    required this.role,
    required this.selected,
    required this.showNavigationOrnament,
    required this.enabled,
    required this.hovered,
    required this.pressed,
    required this.focused,
    required this.child,
  });

  final ThemeSpec tokens;
  final _AppButtonVisual visual;
  final AppButtonRole role;
  final bool selected;
  final bool showNavigationOrnament;
  final bool enabled;
  final bool hovered;
  final bool pressed;
  final bool focused;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final ledger = tokens.isIlluminatedLedger;
    final sakura = tokens.isSakuraNightGarden;
    Widget content = child;
    if (tokens.isStandard &&
        role == AppButtonRole.sidebarNavigation &&
        selected) {
      final standard = context.standardVisual;
      content = Stack(
        fit: StackFit.passthrough,
        children: <Widget>[
          content,
          Align(
            alignment: Alignment.centerLeft,
            child: Container(
              width: 4,
              height: 28,
              decoration: BoxDecoration(
                color: StandardSpec.accentBrush(
                  standard.accentHue,
                  alpha: .78,
                  neon: standard.neon,
                ),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
        ],
      );
    }
    Widget result;
    if (ledger && role == AppButtonRole.completion) {
      result = SizedBox.expand(
        child: CustomPaint(
          painter: LedgerWaxSealPainter(
            enabled: enabled,
            hovered: hovered,
            pressed: pressed,
            focused: focused,
          ),
          child: Center(child: content),
        ),
      );
    } else if (sakura) {
      final detailed =
          role != AppButtonRole.infoChip &&
          role != AppButtonRole.completion &&
          (role != AppButtonRole.sidebarNavigation || selected);
      final accented = selected || role == AppButtonRole.primary;
      result = CustomPaint(
        painter: detailed
            ? SakuraPlumMaterialPainter(
                radius: visual.radius,
                strength: pressed
                    ? .62
                    : accented
                    ? .92
                    : .72,
                drawInnerRule: true,
                depressed: pressed,
                accented: accented,
              )
            : null,
        foregroundPainter: detailed
            ? SakuraSurfaceToolingPainter(
                tone: _surfaceToneForRole(role),
                statusRail: false,
                cornerTooling: true,
              )
            : null,
        child: content,
      );
    } else {
      result = content;
      if (ledger &&
          role == AppButtonRole.navigation &&
          selected &&
          showNavigationOrnament) {
        result = CustomPaint(
          foregroundPainter: LedgerNavigationRibbonPainter(
            trim: tokens.palette.trimBright,
            lapisLight: tokens.palette.primaryBright,
            lapisDeep: tokens.palette.canvasDeep,
          ),
          child: result,
        );
      }
    }
    return result;
  }

  AppSurfaceTone _surfaceToneForRole(AppButtonRole role) => switch (role) {
    AppButtonRole.danger => AppSurfaceTone.danger,
    AppButtonRole.completion => AppSurfaceTone.success,
    AppButtonRole.infoChip => AppSurfaceTone.info,
    _ => AppSurfaceTone.neutral,
  };
}

@immutable
final class _AppButtonVisual {
  const _AppButtonVisual({
    required this.gradient,
    required this.foreground,
    required this.borderColor,
    required this.borderWidth,
    required this.radius,
    required this.shadows,
    required this.toolingColor,
  });

  final LinearGradient gradient;
  final Color foreground;
  final Color borderColor;
  final double borderWidth;
  final double radius;
  final List<BoxShadow> shadows;
  final Color toolingColor;

  static _AppButtonVisual resolve({
    required ThemeSpec spec,
    required StandardVisualSettings standard,
    required ButtonEffectVisualSettings? effects,
    required AppButtonRole role,
    required bool selected,
    required bool enabled,
    required bool hovered,
    required bool pressed,
    required bool focused,
  }) {
    final manuscript = spec.isIlluminatedLedger;
    final sakura = spec.isSakuraNightGarden;
    final activePrimary =
        role == AppButtonRole.primary ||
        (manuscript && role == AppButtonRole.optionPill && selected) ||
        ((role == AppButtonRole.navigation ||
                role == AppButtonRole.sidebarNavigation ||
                (!manuscript && role == AppButtonRole.modeSelector)) &&
            selected);
    late LinearGradient gradient;
    late Color foreground;
    late Color border;
    var borderWidth = 1.0;

    if (manuscript) {
      if (role == AppButtonRole.modeSelector) {
        gradient = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[Color(0xFF174D7E), Color(0xFF0A2744)],
        );
        foreground = selected
            ? const Color(0xFFFFF1BD)
            : const Color(0xFFD9BE78);
        border = selected ? _ledgerAccentBorder : _ledgerInactiveBorder;
      } else if (activePrimary) {
        gradient = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[Color(0xFF174D7E), Color(0xFF0A2744)],
        );
        foreground = const Color(0xFFF8EAC8);
        border = _ledgerAccentBorder;
      } else if (role == AppButtonRole.sidebarNavigation) {
        gradient = const LinearGradient(
          colors: <Color>[Colors.transparent, Colors.transparent],
        );
        foreground = spec.palette.text;
        border = const Color(0x687A5B2A);
      } else if (role == AppButtonRole.infoChip) {
        gradient = const LinearGradient(
          colors: <Color>[Color(0xFF123D69), Color(0xFF123D69)],
        );
        foreground = const Color(0xFFF7EAC7);
        border = _ledgerAccentBorder;
      } else if (role == AppButtonRole.danger) {
        gradient = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            _lighten(spec.palette.danger, 18),
            _darken(spec.palette.danger, 30),
          ],
        );
        foreground = const Color(0xFFF8EAC8);
        border = spec.palette.danger;
      } else if (role == AppButtonRole.completion) {
        gradient = const LinearGradient(
          colors: <Color>[Colors.transparent, Colors.transparent],
        );
        foreground = const Color(0xFFF8EAC8);
        border = Colors.transparent;
      } else {
        gradient = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[Color(0xFFF8EAC8), Color(0xFFD8BC83)],
        );
        foreground = spec.palette.text;
        border = _ledgerInactiveBorder;
      }
    } else if (sakura) {
      switch (role) {
        case AppButtonRole.primary:
          gradient = SakuraNightGardenSpec.sakuraLacquerGradient;
          foreground = SakuraNightGardenSpec.warmIvory;
          border = SakuraNightGardenSpec.dustySakura.withAlpha(196);
          borderWidth = 1.15;
        case AppButtonRole.completion:
          gradient = SakuraNightGardenSpec.mossGradient;
          foreground = SakuraNightGardenSpec.warmIvory;
          border = SakuraNightGardenSpec.mutedMoss.withAlpha(218);
        case AppButtonRole.sidebarNavigation:
          gradient = selected
              ? const LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: <Color>[
                    Color(0xFF422630),
                    Color(0xFF2B1B23),
                    Color(0xFF171116),
                  ],
                  stops: <double>[0, .58, 1],
                )
              : const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: <Color>[Color(0x5C241D23), Color(0x36100E12)],
                );
          foreground = selected
              ? SakuraNightGardenSpec.warmIvory
              : SakuraNightGardenSpec.mutedText;
          border = selected
              ? SakuraNightGardenSpec.dustySakura.withAlpha(184)
              : SakuraNightGardenSpec.rosewood.withAlpha(84);
          if (selected) borderWidth = 1.15;
        case AppButtonRole.navigation:
          gradient = selected
              ? SakuraNightGardenSpec.sakuraLacquerGradient
              : SakuraNightGardenSpec.raisedSurfaceGradient;
          foreground = selected
              ? SakuraNightGardenSpec.warmIvory
              : SakuraNightGardenSpec.mutedText;
          border = selected
              ? SakuraNightGardenSpec.dustySakura.withAlpha(184)
              : SakuraNightGardenSpec.rosewood.withAlpha(138);
          if (selected) borderWidth = 1.15;
        case AppButtonRole.modeSelector:
          gradient = selected
              ? SakuraNightGardenSpec.sakuraLacquerGradient
              : const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: <Color>[
                    Color(0xFF30232C),
                    Color(0xFF211920),
                    Color(0xFF100D12),
                  ],
                  stops: <double>[0, .45, 1],
                );
          foreground = selected
              ? SakuraNightGardenSpec.warmIvory
              : SakuraNightGardenSpec.mutedText;
          border = selected
              ? SakuraNightGardenSpec.paleBlossom.withAlpha(178)
              : SakuraNightGardenSpec.rosewood.withAlpha(132);
          if (selected) borderWidth = 1.15;
        case AppButtonRole.optionPill:
          gradient = selected
              ? const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: <Color>[
                    Color(0xFF452A35),
                    Color(0xFF2C1C25),
                    Color(0xFF171117),
                  ],
                  stops: <double>[0, .56, 1],
                )
              : const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: <Color>[
                    Color(0xFF2C222A),
                    Color(0xFF191419),
                    Color(0xFF0F0C11),
                  ],
                  stops: <double>[0, .58, 1],
                );
          foreground = selected
              ? SakuraNightGardenSpec.warmIvory
              : SakuraNightGardenSpec.mutedText;
          border =
              (selected
                      ? SakuraNightGardenSpec.dustySakura
                      : SakuraNightGardenSpec.rosewood)
                  .withAlpha(selected ? 196 : 128);
        case AppButtonRole.ingredientToggle:
          gradient = const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[
              Color(0xFF2A2026),
              Color(0xFF181419),
              Color(0xFF100E12),
            ],
            stops: <double>[0, .58, 1],
          );
          foreground = const Color(0xFFE2C2AD);
          border = SakuraNightGardenSpec.rosewood.withAlpha(154);
        case AppButtonRole.infoChip:
          gradient = const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[Color(0xFF442833), Color(0xFF20151D)],
          );
          foreground = SakuraNightGardenSpec.paleBlossom;
          border = SakuraNightGardenSpec.barkCopper.withAlpha(194);
        case AppButtonRole.danger:
          gradient = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[
              Color(0xFF633044),
              Color(0xFF432231),
              Color(0xFF24151D),
            ],
            stops: <double>[0, .58, 1],
          );
          foreground = SakuraNightGardenSpec.warmIvory;
          border = SakuraNightGardenSpec.emberBerry.withAlpha(232);
        case AppButtonRole.secondary || AppButtonRole.icon:
          gradient = SakuraNightGardenSpec.raisedSurfaceGradient;
          foreground = SakuraNightGardenSpec.warmIvory;
          border = SakuraNightGardenSpec.rosewood.withAlpha(176);
      }
    } else {
      final accent = StandardSpec.accentBrush(
        standard.accentHue,
        neon: standard.neon,
      );
      Color accentBorder(double alpha) => StandardSpec.accentBrush(
        standard.accentHue,
        alpha: alpha,
        neon: standard.neon,
      );
      switch (role) {
        case AppButtonRole.primary || AppButtonRole.completion:
          final fill = accent.withAlpha((.86 * 255).round());
          gradient = LinearGradient(colors: <Color>[fill, fill]);
          foreground = const Color(0xFF03120E);
          border = accentBorder(.72);
        case AppButtonRole.sidebarNavigation:
          gradient = selected
              ? _effectFill(standard, effects, active: true)
              : StandardSpec.accentGlass(
                  standard.accentHue,
                  topAlpha: 70,
                  bottomAlpha: 22,
                  neon: standard.neon,
                );
          foreground = selected
              ? const Color(0xFFF3FFF0)
              : const Color(0xFFFFF0D0);
          border = selected
              ? _effectBorder(standard, effects, active: true)
              : accentBorder(.3);
          if (selected && effects?.effect == 'orbit') borderWidth = 2;
        case AppButtonRole.modeSelector:
          final selectedOnlyEffect =
              selected &&
              effects != null &&
              effects.activeOnly &&
              effects.effect != 'quiet' &&
              effects.intensity > 0;
          gradient = selected
              ? selectedOnlyEffect
                    ? _effectFill(standard, effects, active: true)
                    : StandardSpec.accentGlass(
                        standard.accentHue,
                        topAlpha: 82,
                        bottomAlpha: 28,
                        neon: standard.neon,
                      )
              : StandardSpec.accentGlass(
                  standard.accentHue,
                  topAlpha: 66,
                  bottomAlpha: 18,
                  neon: standard.neon,
                );
          foreground = selected
              ? const Color(0xFFF3FFF0)
              : const Color(0xFFF7E4B7);
          border = selected
              ? selectedOnlyEffect
                    ? _effectBorder(standard, effects, active: true)
                    : accentBorder(.46)
              : accentBorder(.32);
        case AppButtonRole.optionPill:
          gradient = StandardSpec.accentGlass(
            standard.accentHue,
            topAlpha: selected ? 96 : 44,
            bottomAlpha: selected ? 32 : 14,
            neon: standard.neon,
          );
          foreground = const Color(0xFFFFF4D8);
          border = accentBorder(selected ? .56 : .22);
        case AppButtonRole.ingredientToggle:
          gradient = const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[
              Color.fromARGB(56, 16, 48, 36),
              Color.fromARGB(18, 5, 19, 15),
              Color.fromARGB(20, 1, 6, 7),
            ],
            stops: <double>[0, .55, 1],
          );
          foreground = const Color(0xFFF1D68A);
          border = const Color(0x77536F58);
        case AppButtonRole.infoChip:
          gradient = const LinearGradient(
            colors: <Color>[Color(0x7A35D6AD), Color(0x7A35D6AD)],
          );
          foreground = const Color(0xFFFFF4C8);
          border = Colors.transparent;
        case AppButtonRole.navigation when selected:
          final fill = accent.withAlpha((.86 * 255).round());
          gradient = LinearGradient(colors: <Color>[fill, fill]);
          foreground = const Color(0xFF03120E);
          border = accentBorder(.72);
        case AppButtonRole.danger:
          gradient = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[
              spec.palette.danger.withAlpha(164),
              const Color.fromARGB(92, 48, 13, 18),
            ],
          );
          foreground = const Color(0xFFFFF4D4);
          border = spec.palette.danger.withAlpha(214);
        case AppButtonRole.secondary ||
            AppButtonRole.navigation ||
            AppButtonRole.icon:
          gradient = StandardSpec.accentGlass(
            standard.accentHue,
            topAlpha: 70,
            bottomAlpha: 22,
            neon: standard.neon,
          );
          foreground = const Color(0xFFFFF4D4);
          border = accentBorder(.3);
      }
    }

    if (hovered && enabled) {
      gradient = _mapGradient(gradient, (color) => _lighten(color, 18));
      border = _lighten(border, 34);
    }
    if (pressed && enabled) {
      gradient = _mapGradient(gradient, (color) => _darken(color, 34));
      border = _darken(border, 20);
    }
    if (!enabled) {
      gradient = _mapGradient(
        gradient,
        (color) =>
            Color.alphaBlend(spec.palette.surfaceInset.withAlpha(178), color),
      );
      foreground = spec.palette.textMuted.withAlpha(118);
      border = spec.palette.trim.withAlpha(76);
    }

    final navigation =
        role == AppButtonRole.navigation ||
        role == AppButtonRole.sidebarNavigation ||
        role == AppButtonRole.modeSelector;
    final radius = manuscript && role == AppButtonRole.completion
        ? 999.0
        : role == AppButtonRole.infoChip
        ? 999.0
        : spec.isStandard && role == AppButtonRole.optionPill
        ? 999.0
        : spec.isStandard && role == AppButtonRole.ingredientToggle
        ? 8.0
        : manuscript && role == AppButtonRole.sidebarNavigation && !selected
        ? 0.0
        : navigation
        ? spec.geometry.navigationRadius
        : spec.geometry.buttonRadius;
    final waxSeal = manuscript && role == AppButtonRole.completion;
    return _AppButtonVisual(
      gradient: gradient,
      foreground: foreground,
      borderColor: focused && enabled
          ? manuscript || sakura
                ? spec.palette.primaryBright
                : StandardSpec.accentBrush(
                    standard.accentHue,
                    neon: standard.neon,
                  )
          : border,
      borderWidth: waxSeal
          ? 0
          : focused && enabled && sakura
          ? 2
          : borderWidth,
      radius: radius,
      shadows: manuscript
          ? waxSeal ||
                    (role == AppButtonRole.sidebarNavigation && !selected) ||
                    !enabled
                ? const <BoxShadow>[]
                : _ledgerButtonShellShadow
          : sakura &&
                enabled &&
                !(role == AppButtonRole.sidebarNavigation && !selected)
          ? _sakuraButtonShellShadow
          : const <BoxShadow>[],
      toolingColor: (focused ? spec.palette.trimBright : border).withAlpha(132),
    );
  }

  static LinearGradient _effectFill(
    StandardVisualSettings standard,
    ButtonEffectVisualSettings? settings, {
    required bool active,
  }) {
    if (settings == null ||
        settings.effect == 'quiet' ||
        (settings.activeOnly && !active)) {
      return StandardSpec.accentGlass(
        standard.accentHue,
        topAlpha: 78,
        bottomAlpha: 24,
        neon: standard.neon,
      );
    }
    final hue = standard.accentHue;
    final intensity = settings.intensity.clamp(0.0, 1.0);
    final alpha = .45 + intensity * .2;
    final neon = settings.neon;
    if (settings.effect == 'sweep') {
      return LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: <Color>[
          _hsl(hue - 18, .55, .35, alpha * .66),
          _hsl(hue, neon ? .92 : .72, neon ? .65 : .53, alpha),
          _hsl(hue + 22, .58, .38, alpha * .72),
        ],
        stops: const <double>[0, .58, 1],
      );
    }
    final fill = switch (settings.effect) {
      'embers' => _hsl(hue, neon ? .95 : .7, neon ? .58 : .44, alpha),
      'frost' => _hsl(hue, neon ? .9 : .55, neon ? .66 : .52, alpha),
      'fireflies' => _hsl(hue, neon ? .92 : .66, neon ? .62 : .48, alpha),
      'sigil' => _hsl(hue, neon ? .92 : .62, neon ? .62 : .46, alpha),
      _ => _hsl(hue, neon ? .92 : .62, neon ? .64 : .48, alpha),
    };
    return LinearGradient(colors: <Color>[fill, fill]);
  }

  static Color _effectBorder(
    StandardVisualSettings standard,
    ButtonEffectVisualSettings? settings, {
    required bool active,
  }) {
    if (settings == null ||
        settings.effect == 'quiet' ||
        (settings.activeOnly && !active)) {
      return const Color(0x4F6EA083);
    }
    return _hsl(
      standard.accentHue,
      settings.neon ? .98 : .68,
      settings.neon ? .72 : .62,
      .72,
    );
  }

  static LinearGradient _mapGradient(
    LinearGradient gradient,
    Color Function(Color color) transform,
  ) => LinearGradient(
    begin: gradient.begin,
    end: gradient.end,
    stops: gradient.stops,
    transform: gradient.transform,
    tileMode: gradient.tileMode,
    colors: gradient.colors.map(transform).toList(growable: false),
  );

  static Color _hsl(
    double hue,
    double saturation,
    double lightness,
    double alpha,
  ) => HSLColor.fromAHSL(
    alpha.clamp(0, 1).toDouble(),
    ((hue % 360) + 360) % 360,
    saturation.clamp(0, 1).toDouble(),
    lightness.clamp(0, 1).toDouble(),
  ).toColor();

  static Color _lighten(Color color, int alpha) =>
      Color.alphaBlend(Color.fromARGB(alpha, 255, 255, 255), color);

  static Color _darken(Color color, int alpha) =>
      Color.alphaBlend(Color.fromARGB(alpha, 0, 0, 0), color);
}
