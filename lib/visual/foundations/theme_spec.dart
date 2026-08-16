import 'package:flutter/material.dart';

/// Complete visual identities. Feature widgets should consume semantic tokens
/// and layout capabilities from [ThemeSpec]; only visual primitives should
/// branch on a family to select family-owned material and ornament.
enum RetainedVisualFamily { standard, illuminatedLedger, sakuraNightGarden }

/// Screen geometry is independent from material identity.
///
/// Sakura deliberately reuses the corrected Ledger workstation fit without
/// inheriting manuscript surfaces, typography, folds, or ornament.
enum ThemeLayoutProfile { standardWorkspace, denseSplitWorkspace }

enum AppSurfaceTone { neutral, info, success, warning, danger }

@immutable
final class ThemePalette {
  const ThemePalette({
    required this.canvas,
    required this.canvasDeep,
    required this.surface,
    required this.surfaceRaised,
    required this.surfaceInset,
    required this.primary,
    required this.primaryBright,
    required this.secondary,
    required this.trim,
    required this.trimBright,
    required this.text,
    required this.textMuted,
    required this.success,
    required this.warning,
    required this.danger,
    required this.shadow,
    required this.specular,
  });

  final Color canvas;
  final Color canvasDeep;
  final Color surface;
  final Color surfaceRaised;
  final Color surfaceInset;
  final Color primary;
  final Color primaryBright;
  final Color secondary;
  final Color trim;
  final Color trimBright;
  final Color text;
  final Color textMuted;
  final Color success;
  final Color warning;
  final Color danger;
  final Color shadow;
  final Color specular;

  Color forTone(AppSurfaceTone tone) => switch (tone) {
    AppSurfaceTone.neutral => surfaceRaised,
    AppSurfaceTone.info => primary,
    AppSurfaceTone.success => success,
    AppSurfaceTone.warning => warning,
    AppSurfaceTone.danger => danger,
  };
}

@immutable
final class ThemeTypography {
  const ThemeTypography({
    required this.display,
    required this.section,
    required this.body,
    required this.meta,
    required this.label,
    required this.button,
  });

  final TextStyle display;
  final TextStyle section;
  final TextStyle body;
  final TextStyle meta;
  final TextStyle label;
  final TextStyle button;
}

@immutable
final class ThemeGeometry {
  const ThemeGeometry({
    required this.titleStripHeight,
    required this.workspacePadding,
    required this.sidebarWidth,
    required this.contentGap,
    required this.panelRadius,
    required this.commandRadius,
    required this.cardRadius,
    required this.buttonRadius,
    required this.navigationRadius,
    required this.fieldRadius,
    required this.compactBreakpoint,
    required this.minimumWindowSize,
  });

  final double titleStripHeight;
  final EdgeInsets workspacePadding;
  final double sidebarWidth;
  final double contentGap;
  final double panelRadius;
  final double commandRadius;
  final double cardRadius;
  final double buttonRadius;
  final double navigationRadius;
  final double fieldRadius;
  final Size compactBreakpoint;
  final Size minimumWindowSize;
}

@immutable
final class ThemeMaterials {
  const ThemeMaterials({
    required this.canvas,
    required this.surface,
    required this.surfaceRaised,
    required this.primary,
    required this.secondary,
    required this.modalScrim,
    required this.lowShadow,
    required this.highShadow,
  });

  final Gradient canvas;
  final Gradient surface;
  final Gradient surfaceRaised;
  final Gradient primary;
  final Gradient secondary;
  final Color modalScrim;
  final List<BoxShadow> lowShadow;
  final List<BoxShadow> highShadow;
}

@immutable
final class ThemeMotionCapabilities {
  const ThemeMotionCapabilities({
    required this.interactionDuration,
    required this.supportsAtmosphere,
    required this.supportsButtonEffects,
    required this.supportsOrnament,
  });

  final Duration interactionDuration;
  final bool supportsAtmosphere;
  final bool supportsButtonEffects;
  final bool supportsOrnament;
}

/// Immutable visual contract shared by retained themes and primitives.
@immutable
final class ThemeSpec {
  const ThemeSpec({
    required this.id,
    required this.displayName,
    required this.family,
    required this.layoutProfile,
    required this.brightness,
    required this.palette,
    required this.typography,
    required this.geometry,
    required this.materials,
    required this.motion,
  });

  final String id;
  final String displayName;
  final RetainedVisualFamily family;
  final ThemeLayoutProfile layoutProfile;
  final Brightness brightness;
  final ThemePalette palette;
  final ThemeTypography typography;
  final ThemeGeometry geometry;
  final ThemeMaterials materials;
  final ThemeMotionCapabilities motion;

  bool get isStandard => family == RetainedVisualFamily.standard;
  bool get isIlluminatedLedger =>
      family == RetainedVisualFamily.illuminatedLedger;
  bool get isSakuraNightGarden =>
      family == RetainedVisualFamily.sakuraNightGarden;
  bool get usesDenseSplitLayout =>
      layoutProfile == ThemeLayoutProfile.denseSplitWorkspace;

  ThemeData materialTheme() {
    final ledger = isIlluminatedLedger;
    final sakura = isSakuraNightGarden;
    final fullTheme = ledger || sakura;
    final menuShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(ledger ? 2 : geometry.fieldRadius),
      side: BorderSide(
        color: fullTheme ? palette.trimBright : palette.trim,
        width: fullTheme ? 1.1 : .8,
      ),
    );
    final menuStyle = MenuStyle(
      backgroundColor: WidgetStatePropertyAll<Color>(palette.surfaceRaised),
      surfaceTintColor: const WidgetStatePropertyAll<Color>(Colors.transparent),
      shadowColor: WidgetStatePropertyAll<Color>(palette.shadow),
      elevation: WidgetStatePropertyAll<double>(fullTheme ? 12 : 8),
      shape: WidgetStatePropertyAll<OutlinedBorder>(menuShape),
      side: WidgetStatePropertyAll<BorderSide>(
        BorderSide(
          color: palette.trim.withAlpha(150),
          width: fullTheme ? 1 : .8,
        ),
      ),
      padding: const WidgetStatePropertyAll<EdgeInsetsGeometry>(
        EdgeInsets.symmetric(vertical: 5),
      ),
    );

    return ThemeData(
      brightness: brightness,
      scaffoldBackgroundColor: palette.canvas,
      canvasColor: palette.surfaceRaised,
      dividerColor: palette.trim.withAlpha(104),
      highlightColor: palette.primary.withAlpha(ledger ? 42 : 54),
      colorScheme: ColorScheme.fromSeed(
        seedColor: palette.primary,
        brightness: brightness,
        primary: palette.primary,
        secondary: palette.secondary,
        error: palette.danger,
        surface: palette.surface,
      ),
      textTheme: TextTheme(
        headlineLarge: typography.display,
        headlineMedium: typography.section,
        bodyMedium: typography.body,
        bodySmall: typography.meta,
        labelMedium: typography.label,
        labelLarge: typography.button,
      ),
      iconTheme: IconThemeData(color: palette.text, size: 18),
      focusColor: palette.primaryBright.withAlpha(72),
      hoverColor: palette.primaryBright.withAlpha(28),
      splashFactory: NoSplash.splashFactory,
      scrollbarTheme: ScrollbarThemeData(
        thumbVisibility: const WidgetStatePropertyAll<bool?>(false),
        trackVisibility: const WidgetStatePropertyAll<bool?>(false),
        interactive: false,
        radius: Radius.zero,
        minThumbLength: 34,
        thickness: const WidgetStatePropertyAll<double?>(0),
        thumbColor: const WidgetStatePropertyAll<Color?>(Colors.transparent),
        trackColor: const WidgetStatePropertyAll<Color?>(Colors.transparent),
        trackBorderColor: const WidgetStatePropertyAll<Color?>(
          Colors.transparent,
        ),
        crossAxisMargin: 0,
        mainAxisMargin: 0,
      ),
      tooltipTheme: TooltipThemeData(
        constraints: const BoxConstraints(minHeight: 28, maxWidth: 320),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        margin: const EdgeInsets.all(6),
        verticalOffset: 9,
        waitDuration: const Duration(milliseconds: 420),
        showDuration: const Duration(seconds: 4),
        decoration: BoxDecoration(
          gradient: fullTheme ? materials.surfaceRaised : materials.surface,
          borderRadius: BorderRadius.circular(
            ledger ? 2 : geometry.fieldRadius,
          ),
          border: Border.all(
            color: fullTheme ? palette.trimBright : palette.trim,
            width: fullTheme ? 1.1 : .8,
          ),
          boxShadow: materials.highShadow,
        ),
        textStyle: typography.meta.copyWith(
          color: palette.text,
          fontStyle: fullTheme ? FontStyle.normal : typography.meta.fontStyle,
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        shadowColor: palette.shadow,
        elevation: fullTheme ? 16 : 12,
        barrierColor: materials.modalScrim,
        shape: menuShape,
        titleTextStyle: typography.section,
        contentTextStyle: typography.body,
        clipBehavior: Clip.antiAlias,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: palette.surfaceRaised,
        surfaceTintColor: Colors.transparent,
        shadowColor: palette.shadow,
        elevation: fullTheme ? 12 : 8,
        shape: menuShape,
        menuPadding: const EdgeInsets.symmetric(vertical: 5),
        textStyle: typography.body,
        labelTextStyle: WidgetStateProperty.resolveWith<TextStyle?>((states) {
          final disabled = states.contains(WidgetState.disabled);
          return typography.body.copyWith(
            color: disabled ? palette.textMuted.withAlpha(112) : palette.text,
          );
        }),
        iconColor: ledger
            ? palette.primary
            : sakura
            ? palette.primaryBright
            : palette.text,
      ),
      dropdownMenuTheme: DropdownMenuThemeData(
        textStyle: typography.body,
        disabledColor: palette.textMuted.withAlpha(112),
        menuStyle: menuStyle,
        inputDecorationTheme: InputDecorationThemeData(
          filled: true,
          fillColor: palette.surfaceInset,
          labelStyle: typography.label,
          hintStyle: typography.meta,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(geometry.fieldRadius),
            borderSide: BorderSide(color: palette.trim),
          ),
        ),
      ),
      menuTheme: MenuThemeData(style: menuStyle),
      menuButtonTheme: MenuButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStatePropertyAll<Color>(palette.text),
          overlayColor: WidgetStatePropertyAll<Color>(
            palette.primary.withAlpha(fullTheme ? 38 : 46),
          ),
          textStyle: WidgetStatePropertyAll<TextStyle>(typography.body),
        ),
      ),
    );
  }
}

/// Supplies a retained [ThemeSpec] without tying visual primitives to global
/// application state.
class ThemeSpecScope extends InheritedTheme {
  const ThemeSpecScope({required this.spec, required super.child, super.key});

  final ThemeSpec spec;

  static ThemeSpec of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<ThemeSpecScope>();
    assert(scope != null, 'No ThemeSpecScope found above this widget.');
    return scope!.spec;
  }

  static ThemeSpec? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ThemeSpecScope>()?.spec;

  @override
  Widget wrap(BuildContext context, Widget child) =>
      ThemeSpecScope(spec: spec, child: child);

  @override
  bool updateShouldNotify(ThemeSpecScope oldWidget) => oldWidget.spec != spec;
}

extension ThemeSpecContext on BuildContext {
  ThemeSpec get visualTheme => ThemeSpecScope.of(this);
}
