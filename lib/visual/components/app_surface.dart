import 'package:flutter/material.dart';

import '../foundations/theme_spec.dart';
import '../illuminated_ledger/ledger_ornament_painters.dart';
import '../sakura_night_garden/sakura_botanical_assets.dart';
import '../sakura_night_garden/sakura_material_painters.dart';
import '../sakura_night_garden/sakura_spec.dart';
import '../standard/standard_spec.dart';

enum AppSurfaceRole {
  layout,
  panel,
  commandBand,
  card,
  row,
  modal,
  popup,
  tooltip,
}

/// Shared layered material surface. Interaction belongs to the wrapped child;
/// all ornament is paint-only.
class AppSurface extends StatelessWidget {
  const AppSurface({
    required this.child,
    this.spec,
    this.role = AppSurfaceRole.panel,
    this.tone = AppSurfaceTone.neutral,
    this.padding,
    this.semanticLabel,
    this.ornamentIndex,
    this.clipBehavior = Clip.none,
    super.key,
  });

  final Widget child;
  final ThemeSpec? spec;
  final AppSurfaceRole role;
  final AppSurfaceTone tone;
  final EdgeInsetsGeometry? padding;
  final String? semanticLabel;
  final int? ornamentIndex;
  final Clip clipBehavior;

  static const Key materialKey = ValueKey<String>('app-surface-material');

  @override
  Widget build(BuildContext context) {
    final tokens = spec ?? context.visualTheme;
    if (tokens.isSakuraNightGarden) {
      return _withSemantics(_buildSakura(tokens));
    }
    final manuscript = tokens.isIlluminatedLedger;
    if (!manuscript) {
      return _withSemantics(_buildStandard(context, tokens));
    }
    if (role == AppSurfaceRole.layout) {
      // Avalonia's LayoutFrame is deliberately transparent. Painting the
      // normal Ledger panel material here boxed each Planner column from the
      // section heading to the bottom of the page and made the center fold
      // read as a much wider allocated gutter than it really is.
      return _withSemantics(
        Container(
          key: materialKey,
          color: Colors.transparent,
          child: ClipRect(
            clipBehavior: clipBehavior,
            child: Padding(
              padding: padding ?? EdgeInsets.zero,
              child: DefaultTextStyle.merge(
                style: tokens.typography.body.copyWith(
                  color: tokens.palette.text,
                ),
                child: child,
              ),
            ),
          ),
        ),
      );
    }

    final contentPadding = padding ?? _padding(tokens);
    final decoration = _ledgerDecoration(tokens);
    final content = Padding(
      padding: contentPadding,
      child: DefaultTextStyle.merge(
        style: tokens.typography.body.copyWith(color: tokens.palette.text),
        child: child,
      ),
    );

    final result = Container(
      key: materialKey,
      decoration: decoration,
      clipBehavior: clipBehavior,
      child: _ledgerHasTooling
          ? CustomPaint(
              foregroundPainter: LedgerSurfaceToolingPainter(
                trim: tokens.palette.trim.withAlpha(96),
              ),
              child: content,
            )
          : content,
    );
    return _withSemantics(result);
  }

  Widget _buildSakura(ThemeSpec tokens) {
    if (role == AppSurfaceRole.layout) {
      return Container(
        key: materialKey,
        color: Colors.transparent,
        child: ClipRect(
          clipBehavior: clipBehavior,
          child: Padding(
            padding: padding ?? EdgeInsets.zero,
            child: DefaultTextStyle.merge(
              style: tokens.typography.body.copyWith(
                color: tokens.palette.text,
              ),
              child: child,
            ),
          ),
        ),
      );
    }

    final radius = _sakuraRadius(tokens);
    final content = Padding(
      padding: padding ?? _padding(tokens),
      child: DefaultTextStyle.merge(
        style: tokens.typography.body.copyWith(color: tokens.palette.text),
        child: child,
      ),
    );
    final ornamentedContent =
        role == AppSurfaceRole.card && ornamentIndex != null
        ? Stack(
            fit: StackFit.passthrough,
            clipBehavior: Clip.hardEdge,
            children: <Widget>[
              content,
              Positioned(
                right: 0,
                bottom: 0,
                child: SakuraQueueCornerAsset.fromIndex(ornamentIndex!),
              ),
            ],
          )
        : content;
    final materialPainter =
        role == AppSurfaceRole.panel || role == AppSurfaceRole.commandBand
        ? SakuraCedarGrainPainter(
            density: role == AppSurfaceRole.commandBand ? .36 : .48,
            highlight: const Color(0x127F625C),
            shadow: const Color(0x21000000),
          )
        : SakuraPlumMaterialPainter(
            radius: radius,
            strength: role == AppSurfaceRole.tooltip ? .45 : .72,
            drawInnerRule: role != AppSurfaceRole.tooltip,
          );
    final tooling = _sakuraHasTooling
        ? SakuraSurfaceToolingPainter(
            tone: tone,
            statusRail:
                role == AppSurfaceRole.card || role == AppSurfaceRole.row,
            cornerTooling: role != AppSurfaceRole.card || ornamentIndex == null,
          )
        : null;

    final decoration = _sakuraDecoration(tokens);
    // BoxDecoration.border contributes its dimensions to Container's implicit
    // padding. Keep the rosewood rule paint-only so Sakura retains the exact
    // dense Ledger-format measurements instead of growing every surface by
    // two pixels.
    final border = decoration.border! as Border;
    return Container(
      key: materialKey,
      decoration: decoration.copyWith(border: _sakuraLayoutBorder(border.top)),
      clipBehavior: clipBehavior,
      child: CustomPaint(
        foregroundPainter: _SakuraSurfaceBorderPainter(
          side: border.top,
          radius: radius,
        ),
        child: CustomPaint(
          painter: materialPainter,
          foregroundPainter: tooling,
          child: ornamentedContent,
        ),
      ),
    );
  }

  BoxBorder _sakuraLayoutBorder(BorderSide paintedSide) {
    final invisible = paintedSide.copyWith(color: Colors.transparent);
    return role == AppSurfaceRole.commandBand
        ? Border(left: invisible, right: invisible)
        : Border.fromBorderSide(invisible);
  }

  BoxDecoration _sakuraDecoration(ThemeSpec tokens) {
    final radius = BorderRadius.circular(_sakuraRadius(tokens));
    final toneColor = tone == AppSurfaceTone.neutral
        ? SakuraNightGardenSpec.rosewood
        : tokens.palette.forTone(tone);
    switch (role) {
      case AppSurfaceRole.layout:
        return const BoxDecoration(color: Colors.transparent);
      case AppSurfaceRole.commandBand:
        return BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[
              Color(0xF2262025),
              Color(0xF01B171C),
              Color(0xF0121014),
            ],
            stops: <double>[0, .56, 1],
          ),
          image: _sakuraTexture(.14),
          borderRadius: radius,
          border: Border.all(color: const Color(0xA06B3C48)),
          boxShadow: const <BoxShadow>[
            BoxShadow(
              color: Color(0x73000000),
              blurRadius: 8,
              offset: Offset(0, 3),
            ),
          ],
        );
      case AppSurfaceRole.panel:
        return BoxDecoration(
          gradient: tokens.materials.surface,
          image: _sakuraTexture(.16),
          borderRadius: radius,
          border: Border.all(color: const Color(0x806B3C48)),
          boxShadow: tokens.materials.lowShadow,
        );
      case AppSurfaceRole.card || AppSurfaceRole.row:
        return BoxDecoration(
          gradient: _sakuraGradient(raised: false),
          image: _sakuraTexture(role == AppSurfaceRole.card ? .22 : .18),
          borderRadius: radius,
          border: Border.all(color: toneColor.withAlpha(176)),
          boxShadow: const <BoxShadow>[
            BoxShadow(
              color: Color(0x66000000),
              blurRadius: 5,
              offset: Offset(0, 2),
            ),
          ],
        );
      case AppSurfaceRole.modal ||
          AppSurfaceRole.popup ||
          AppSurfaceRole.tooltip:
        return BoxDecoration(
          gradient: _sakuraGradient(raised: true),
          image: _sakuraTexture(role == AppSurfaceRole.tooltip ? .12 : .2),
          borderRadius: radius,
          border: Border.all(
            color: toneColor.withAlpha(
              role == AppSurfaceRole.tooltip ? 132 : 194,
            ),
          ),
          boxShadow: tokens.materials.highShadow,
        );
    }
  }

  DecorationImage _sakuraTexture(double opacity) => DecorationImage(
    image: const AssetImage(
      'assets/sakura/materials/charcoal-plum-lacquer.png',
    ),
    fit: BoxFit.cover,
    filterQuality: FilterQuality.high,
    opacity: opacity,
  );

  Gradient _sakuraGradient({required bool raised}) {
    final LinearGradient base = raised
        ? SakuraNightGardenSpec.raisedSurfaceGradient
        : SakuraNightGardenSpec.surfaceGradient;
    if (tone == AppSurfaceTone.neutral) return base;
    final tint = switch (tone) {
      AppSurfaceTone.success => SakuraNightGardenSpec.mutedMoss,
      AppSurfaceTone.warning => const Color(0xFF9A654C),
      AppSurfaceTone.danger => SakuraNightGardenSpec.emberBerry,
      AppSurfaceTone.info => SakuraNightGardenSpec.paleBlossom,
      AppSurfaceTone.neutral => Colors.transparent,
    };
    final alpha = switch (tone) {
      AppSurfaceTone.danger => raised ? 18 : 14,
      AppSurfaceTone.success || AppSurfaceTone.warning => raised ? 16 : 11,
      AppSurfaceTone.info => raised ? 14 : 9,
      AppSurfaceTone.neutral => 0,
    };
    return LinearGradient(
      begin: base.begin,
      end: base.end,
      stops: base.stops,
      transform: base.transform,
      tileMode: base.tileMode,
      colors: base.colors
          .map((color) => Color.alphaBlend(tint.withAlpha(alpha), color))
          .toList(growable: false),
    );
  }

  bool get _sakuraHasTooling => switch (role) {
    AppSurfaceRole.card ||
    AppSurfaceRole.row ||
    AppSurfaceRole.modal ||
    AppSurfaceRole.popup => true,
    _ => false,
  };

  double _sakuraRadius(ThemeSpec tokens) => switch (role) {
    AppSurfaceRole.commandBand => tokens.geometry.commandRadius,
    AppSurfaceRole.card || AppSurfaceRole.row => tokens.geometry.cardRadius,
    AppSurfaceRole.tooltip => 4,
    _ => tokens.geometry.panelRadius,
  };

  BoxDecoration _ledgerDecoration(ThemeSpec tokens) {
    switch (role) {
      case AppSurfaceRole.layout:
        return const BoxDecoration(color: Colors.transparent);
      case AppSurfaceRole.commandBand:
        // Avalonia truncates the GlassBrush(56, 22) alpha conversion:
        // 0.639607... -> 163 (A3), 0.466274... -> 118 (76).
        return BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[Color(0xA3FFF7DF), Color(0x76E7D3AB)],
          ),
          borderRadius: BorderRadius.circular(4),
          border: const Border(
            left: BorderSide(color: Color(0x6FA77E2E)),
            right: BorderSide(color: Color(0x6FA77E2E)),
          ),
        );
      case AppSurfaceRole.panel:
        return BoxDecoration(
          gradient: tokens.materials.surface,
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: const Color(0x7EA77E2E)),
          boxShadow: const <BoxShadow>[
            BoxShadow(
              color: Color(0x30352516),
              blurRadius: 18,
              offset: Offset(0, 5),
            ),
          ],
        );
      case AppSurfaceRole.card || AppSurfaceRole.row:
        final fill = _ledgerToneFill;
        return BoxDecoration(
          color: fill,
          gradient: fill == null ? tokens.materials.surfaceRaised : null,
          borderRadius: BorderRadius.circular(2),
          border: Border.all(color: _ledgerToneBorder),
          boxShadow: const <BoxShadow>[
            BoxShadow(
              color: Color(0x40352516),
              blurRadius: 6,
              offset: Offset(0, 2),
            ),
          ],
        );
      case AppSurfaceRole.modal ||
          AppSurfaceRole.popup ||
          AppSurfaceRole.tooltip:
        final borderColor = tone == AppSurfaceTone.neutral
            ? tokens.palette.trim
            : tokens.palette.forTone(tone);
        return BoxDecoration(
          gradient: _gradient(tokens, true),
          borderRadius: BorderRadius.circular(_radius(tokens)),
          border: Border.all(color: borderColor.withAlpha(150), width: 1.1),
          boxShadow: tokens.materials.highShadow,
        );
    }
  }

  bool get _ledgerHasTooling => switch (role) {
    AppSurfaceRole.card ||
    AppSurfaceRole.row ||
    AppSurfaceRole.modal ||
    AppSurfaceRole.popup => true,
    _ => false,
  };

  Color? get _ledgerToneFill => switch (tone) {
    AppSurfaceTone.neutral => null,
    AppSurfaceTone.success => const Color(0xB8E3E2C9),
    AppSurfaceTone.warning => const Color(0xB8EADBB7),
    AppSurfaceTone.danger => const Color(0xC2E8CDC1),
    AppSurfaceTone.info => const Color(0xB8DFDAC7),
  };

  Color get _ledgerToneBorder => switch (tone) {
    AppSurfaceTone.neutral => const Color(0x7FA77E2E),
    AppSurfaceTone.success => const Color(0x82647B35),
    AppSurfaceTone.warning => const Color(0x8EB9903E),
    AppSurfaceTone.danger => const Color(0xA6A45648),
    AppSurfaceTone.info => const Color(0x786B765A),
  };

  Widget _buildStandard(BuildContext context, ThemeSpec tokens) {
    final visuals = context.standardVisual;
    final contentPadding = padding ?? _standardPadding;
    final radius = switch (role) {
      AppSurfaceRole.layout => 0.0,
      AppSurfaceRole.commandBand => tokens.geometry.commandRadius,
      AppSurfaceRole.card || AppSurfaceRole.row => tokens.geometry.cardRadius,
      _ => tokens.geometry.panelRadius,
    };

    final BoxDecoration decoration;
    switch (role) {
      case AppSurfaceRole.layout:
        decoration = const BoxDecoration(color: Colors.transparent);
      case AppSurfaceRole.panel:
        decoration = BoxDecoration(
          gradient: StandardSpec.glassGradient(topAlpha: 44, bottomAlpha: 16),
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: const Color(0x346B8B74)),
        );
      case AppSurfaceRole.commandBand:
        decoration = BoxDecoration(
          gradient: StandardSpec.glassGradient(topAlpha: 56, bottomAlpha: 22),
          borderRadius: BorderRadius.circular(radius),
        );
      case AppSurfaceRole.card:
        decoration = BoxDecoration(
          color: StandardSpec.plannerCardFill(visuals.backgroundId, tone),
          borderRadius: BorderRadius.circular(radius),
        );
      case AppSurfaceRole.row:
        decoration = BoxDecoration(
          color: StandardSpec.plannerCardFill(visuals.backgroundId, tone),
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: StandardSpec.plannerCardBorder(tone)),
        );
      case AppSurfaceRole.modal ||
          AppSurfaceRole.popup ||
          AppSurfaceRole.tooltip:
        final borderColor = tone == AppSurfaceTone.neutral
            ? tokens.palette.trimBright
            : tokens.palette.forTone(tone);
        decoration = BoxDecoration(
          gradient: _gradient(tokens, false),
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: borderColor.withAlpha(112), width: .8),
          boxShadow: tokens.materials.highShadow,
        );
    }

    return Container(
      key: materialKey,
      decoration: decoration,
      clipBehavior: clipBehavior,
      child: Padding(padding: contentPadding, child: child),
    );
  }

  Widget _withSemantics(Widget result) => semanticLabel == null
      ? result
      : Semantics(container: true, label: semanticLabel, child: result);

  double _radius(ThemeSpec spec) => switch (role) {
    AppSurfaceRole.commandBand => spec.geometry.commandRadius,
    AppSurfaceRole.card || AppSurfaceRole.row => spec.geometry.cardRadius,
    _ => spec.geometry.panelRadius,
  };

  EdgeInsets _padding(ThemeSpec spec) => switch (role) {
    AppSurfaceRole.commandBand => const EdgeInsets.symmetric(
      horizontal: 12,
      vertical: 9,
    ),
    AppSurfaceRole.row => const EdgeInsets.symmetric(
      horizontal: 10,
      vertical: 8,
    ),
    AppSurfaceRole.tooltip => const EdgeInsets.symmetric(
      horizontal: 10,
      vertical: 7,
    ),
    AppSurfaceRole.card => const EdgeInsets.all(10),
    _ => const EdgeInsets.all(14),
  };

  EdgeInsets get _standardPadding => switch (role) {
    AppSurfaceRole.layout => EdgeInsets.zero,
    AppSurfaceRole.commandBand => const EdgeInsets.all(12),
    AppSurfaceRole.row || AppSurfaceRole.card => EdgeInsets.all(
      tone == AppSurfaceTone.danger ? 12 : 14,
    ),
    AppSurfaceRole.tooltip => const EdgeInsets.symmetric(
      horizontal: 10,
      vertical: 7,
    ),
    _ => const EdgeInsets.all(14),
  };

  Gradient _gradient(ThemeSpec spec, bool manuscript) {
    final base = switch (role) {
      AppSurfaceRole.layout ||
      AppSurfaceRole.panel ||
      AppSurfaceRole.commandBand => spec.materials.surface,
      _ => spec.materials.surfaceRaised,
    };
    if (tone == AppSurfaceTone.neutral) return base;

    final tint = spec.palette.forTone(tone);
    final alpha = manuscript ? 36 : 58;
    Color mix(Color color) => Color.alphaBlend(tint.withAlpha(alpha), color);
    if (base is LinearGradient) {
      return LinearGradient(
        begin: base.begin,
        end: base.end,
        stops: base.stops,
        transform: base.transform,
        tileMode: base.tileMode,
        colors: base.colors.map(mix).toList(growable: false),
      );
    }
    return LinearGradient(
      colors: <Color>[
        mix(spec.palette.surfaceRaised),
        mix(spec.palette.surface),
      ],
    );
  }
}

final class _SakuraSurfaceBorderPainter extends CustomPainter {
  const _SakuraSurfaceBorderPainter({required this.side, required this.radius});

  final BorderSide side;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= side.width || size.height <= side.width) return;
    final bounds = Offset.zero & size;
    final outerInset = .65;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        bounds.deflate(outerInset),
        Radius.circular((radius - outerInset).clamp(0, radius)),
      ),
      Paint()
        ..color = const Color(0xB2070508)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.35,
    );

    final inset = 1.05;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        bounds.deflate(inset),
        Radius.circular((radius - inset).clamp(0, radius)),
      ),
      side.toPaint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    final innerInset = 2.15;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        bounds.deflate(innerInset),
        Radius.circular((radius - innerInset).clamp(0, radius)),
      ),
      Paint()
        ..color = Color.fromARGB(
          (side.color.a * 255 * .48).round().clamp(0, 255),
          232,
          176,
          191,
        )
        ..style = PaintingStyle.stroke
        ..strokeWidth = .55,
    );
  }

  @override
  bool? hitTest(Offset position) => false;

  @override
  bool shouldRepaint(covariant _SakuraSurfaceBorderPainter oldDelegate) =>
      oldDelegate.side != side || oldDelegate.radius != radius;
}
