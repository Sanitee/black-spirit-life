import 'package:flutter/material.dart';

import '../../visual/illuminated_ledger/ledger_ornament_painters.dart';
import '../../visual/visual.dart';

/// Stable hooks for the app-owned copy confirmation surface.
abstract final class ApplicationCopyToastKeys {
  static const overlay = ValueKey<String>('application-copy-toast');
  static const surface = ValueKey<String>('application-copy-toast-surface');
  static const ledgerSeal = ValueKey<String>(
    'application-copy-toast-ledger-seal',
  );
}

/// The compact copy confirmation used by the retained Avalonia interface.
///
/// Placement is intentionally owned by this full-window overlay: Standard
/// places the pill twelve pixels below the title strip, while Illuminated
/// Ledger centers it inside that strip. The overlay never participates in hit
/// testing, so a transient confirmation cannot steal title-bar or workspace
/// input.
class ApplicationCopyToastOverlay extends StatelessWidget {
  const ApplicationCopyToastOverlay({
    required this.message,
    required this.spec,
    required this.standardSettings,
    super.key,
  });

  final String message;
  final ThemeSpec spec;
  final StandardVisualSettings standardSettings;

  @override
  Widget build(BuildContext context) {
    final ledger = spec.family == RetainedVisualFamily.illuminatedLedger;
    final surface = _CopyToastSurface(
      message: message,
      spec: spec,
      standardSettings: standardSettings,
    );

    return IgnorePointer(
      child: Semantics(
        key: ApplicationCopyToastKeys.overlay,
        container: true,
        liveRegion: true,
        label: message,
        child: ExcludeSemantics(
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              if (ledger)
                Align(
                  alignment: Alignment.topCenter,
                  child: SizedBox(
                    height: spec.geometry.titleStripHeight,
                    child: Center(child: surface),
                  ),
                )
              else
                Positioned(
                  top: spec.geometry.titleStripHeight + 12,
                  left: 0,
                  right: 0,
                  child: Center(child: surface),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CopyToastSurface extends StatelessWidget {
  const _CopyToastSurface({
    required this.message,
    required this.spec,
    required this.standardSettings,
  });

  final String message;
  final ThemeSpec spec;
  final StandardVisualSettings standardSettings;

  @override
  Widget build(BuildContext context) {
    final ledger = spec.family == RetainedVisualFamily.illuminatedLedger;
    final sakura = spec.family == RetainedVisualFamily.sakuraNightGarden;
    final effectiveHue = spec.family == RetainedVisualFamily.standard
        ? standardSettings.rainbow
              ? (standardSettings.accentHue +
                        DateTime.now().toUtc().millisecondsSinceEpoch /
                            1000 *
                            24)
                    .remainder(360)
              : standardSettings.accentHue
        : null;
    final decoration = switch (spec.family) {
      RetainedVisualFamily.illuminatedLedger => BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[Color(0xFF174D7E), Color(0xFF0A2744)],
        ),
        borderRadius: BorderRadius.circular(2),
        border: Border.all(color: const Color(0xFFD2B15A), width: 1.5),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x69352516),
            blurRadius: 9,
            offset: Offset(0, 3),
          ),
        ],
      ),
      RetainedVisualFamily.sakuraNightGarden => BoxDecoration(
        gradient: SakuraNightGardenSpec.raisedSurfaceGradient,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(
          color: SakuraNightGardenSpec.rosewood.withAlpha(224),
        ),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x85000000),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      RetainedVisualFamily.standard => BoxDecoration(
        gradient: StandardSpec.accentGlass(
          effectiveHue!,
          topAlpha: 156,
          bottomAlpha: 58,
          neon: standardSettings.neon,
        ),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: StandardSpec.accentBrush(
            effectiveHue,
            alpha: .72,
            neon: standardSettings.neon,
          ),
        ),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x66000000),
            blurRadius: 24,
            offset: Offset(0, 8),
          ),
        ],
      ),
    };

    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (ledger)
          const SizedBox.square(
            key: ApplicationCopyToastKeys.ledgerSeal,
            dimension: 24,
            child: CustomPaint(
              painter: LedgerWaxSealPainter(
                enabled: true,
                hovered: false,
                pressed: false,
                focused: false,
              ),
              child: Center(
                child: AppVectorGlyph(
                  'check',
                  size: 10.08,
                  color: Color(0xFFFFF1BD),
                  tightBounds: true,
                ),
              ),
            ),
          )
        else if (sakura)
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              gradient: SakuraNightGardenSpec.mossGradient,
              borderRadius: BorderRadius.circular(5),
              border: Border.all(
                color: SakuraNightGardenSpec.copperHighlight.withAlpha(172),
              ),
            ),
            child: const Center(
              child: AppVectorGlyph(
                'check',
                size: 11,
                color: SakuraNightGardenSpec.warmIvory,
                tightBounds: true,
              ),
            ),
          )
        else
          const AppVectorGlyph('check', size: 14, color: Color(0xFFEFFFF0)),
        const SizedBox(width: 7),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 340),
          child: Text(
            message,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: switch (spec.family) {
                RetainedVisualFamily.illuminatedLedger => const Color(
                  0xFFF7EAC7,
                ),
                RetainedVisualFamily.sakuraNightGarden =>
                  SakuraNightGardenSpec.warmIvory,
                RetainedVisualFamily.standard => const Color(0xFFFFF7D8),
              },
              fontFamily: ledger ? 'Georgia' : 'Segoe UI',
              fontSize: 13,
              fontWeight: sakura ? FontWeight.w600 : FontWeight.w700,
            ),
          ),
        ),
      ],
    );

    final surface = Container(
      key: ApplicationCopyToastKeys.surface,
      padding: switch (spec.family) {
        RetainedVisualFamily.illuminatedLedger => const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 6,
        ),
        RetainedVisualFamily.sakuraNightGarden => const EdgeInsets.symmetric(
          horizontal: 13,
          vertical: 7,
        ),
        RetainedVisualFamily.standard => const EdgeInsets.symmetric(
          horizontal: 13,
          vertical: 8,
        ),
      },
      decoration: decoration,
      child: content,
    );
    if (!sakura) return surface;
    return CustomPaint(
      foregroundPainter: const SakuraSurfaceToolingPainter(
        statusRail: false,
        cornerTooling: true,
      ),
      child: CustomPaint(
        foregroundPainter: const SakuraPlumMaterialPainter(
          radius: 5,
          strength: .45,
        ),
        child: surface,
      ),
    );
  }
}
