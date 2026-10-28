import 'package:flutter/material.dart';

import '../../visual/visual.dart';
import '../shared/profile_game_icon.dart';

/// The approved profile hierarchy, using the active Appearance's reading colors.
abstract final class ProfileTypography {
  static Color secondary(BuildContext context) {
    final palette = context.visualTheme.palette;
    return Color.lerp(palette.textMuted, palette.text, .18)!;
  }

  static TextStyle _style(
    BuildContext context,
    double size,
    FontWeight weight,
    double lineHeight, {
    bool muted = false,
  }) => context.visualTheme.typography.body.copyWith(
    color: muted ? secondary(context) : context.visualTheme.palette.text,
    fontSize: size,
    fontWeight: weight,
    height: lineHeight / size,
    letterSpacing: 0,
    leadingDistribution: TextLeadingDistribution.even,
  );

  static TextStyle section(BuildContext context) =>
      _style(context, 19, FontWeight.w700, 26);
  static TextStyle group(BuildContext context) =>
      _style(context, 15, FontWeight.w600, 20);
  static TextStyle label(BuildContext context) =>
      _style(context, 12, FontWeight.w400, 16, muted: true);
  static TextStyle input(BuildContext context) =>
      _style(context, 16, FontWeight.w600, 22);
  static TextStyle result(BuildContext context) =>
      _style(context, 26, FontWeight.w700, 36);
  static TextStyle supporting(BuildContext context) =>
      _style(context, 14, FontWeight.w600, 20);
}

/// Stationary warm inlay and recessed icon well; no effect touches map rendering.
class ProfileIconInlay extends StatelessWidget {
  const ProfileIconInlay({required this.artwork, super.key});

  final ProfileArtwork artwork;

  @override
  Widget build(BuildContext context) {
    final palette = context.visualTheme.palette;
    final warm = Color.lerp(palette.trimBright, palette.warning, .14)!;
    final edge = Color.lerp(palette.trim, palette.surfaceInset, .35)!;
    return Container(
      key: ValueKey('profile-inlay:${artwork.name}'),
      width: 52,
      height: 52,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(warm, palette.surfaceRaised, .15)!,
            Color.lerp(palette.trim, palette.surfaceRaised, .34)!,
            Color.lerp(palette.trim, palette.surfaceInset, .22)!,
            Color.lerp(warm, palette.trim, .4)!,
          ],
          stops: const [0, .25, .67, 1],
        ),
        border: Border.all(color: Color.lerp(warm, edge, .25)!),
        boxShadow: [
          BoxShadow(
            color: palette.shadow.withValues(alpha: .32),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(3),
          color: Color.lerp(palette.surfaceInset, palette.surface, .25),
          border: Border.all(color: palette.trimBright.withValues(alpha: .6)),
        ),
        child: ProfileIcon(artwork: artwork, size: 32),
      ),
    );
  }
}

/// The same inset surface family as the approved Market Sales result.
class ProfileResultFrame extends StatelessWidget {
  const ProfileResultFrame({
    required this.child,
    this.padding = const EdgeInsets.all(16),
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) =>
      AppSurface(role: AppSurfaceRole.panel, padding: padding, child: child);
}
