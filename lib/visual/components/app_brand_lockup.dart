import 'package:flutter/material.dart';

import '../foundations/theme_spec.dart';
import '../illuminated_ledger/ledger_spec.dart';
import '../sakura_night_garden/sakura_botanical_assets.dart';
import '../sakura_night_garden/sakura_spec.dart';
import '../standard/standard_spec.dart';
import 'retained_asset_image.dart';

/// Theme-owned product identity used by the persistent workspace rail.
class AppBrandLockup extends StatelessWidget {
  const AppBrandLockup({super.key});

  static const Key ledgerDropCapKey = ValueKey<String>('ledger-brand-drop-cap');
  static const Key ledgerDropCapFailureKey = ValueKey<String>(
    'ledger-brand-drop-cap-failure',
  );
  static const Key ledgerOuterSpacingKey = ValueKey<String>(
    'ledger-brand-outer-spacing',
  );
  static const Key ledgerInnerSpacingKey = ValueKey<String>(
    'ledger-brand-inner-spacing',
  );
  static const Key ledgerTitleKey = ValueKey<String>('ledger-brand-title');
  static const Key ledgerDividerKey = ValueKey<String>('ledger-brand-divider');
  static const Key sakuraTitleKey = ValueKey<String>('sakura-brand-title');
  static const Key sakuraRuleKey = ValueKey<String>('sakura-brand-rule');

  @override
  Widget build(BuildContext context) {
    final spec = context.visualTheme;
    return Semantics(
      container: true,
      label: 'Black Spirit Life',
      child: ExcludeSemantics(
        child: switch (spec.family) {
          RetainedVisualFamily.illuminatedLedger => _LedgerBrand(spec: spec),
          RetainedVisualFamily.sakuraNightGarden => _SakuraBrand(spec: spec),
          RetainedVisualFamily.standard => _StandardBrand(spec: spec),
        },
      ),
    );
  }
}

class _StandardBrand extends StatelessWidget {
  const _StandardBrand({required this.spec});

  final ThemeSpec spec;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(8, 10, 6, 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const Text(
          'BLACK DESERT',
          style: TextStyle(
            color: Color(0xFFD9C57D),
            fontFamily: 'Segoe UI',
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Black Spirit\nLife',
          maxLines: 2,
          style: TextStyle(
            color: Color(0xFFFFF8D4),
            fontFamily: 'Georgia',
            fontSize: 34,
            fontWeight: FontWeight.w700,
            height: 31 / 34,
          ),
        ),
        const SizedBox(height: 4),
        _BrandRule(spec: spec),
      ],
    ),
  );
}

class _LedgerBrand extends StatelessWidget {
  const _LedgerBrand({required this.spec});

  final ThemeSpec spec;

  @override
  Widget build(BuildContext context) => Padding(
    key: AppBrandLockup.ledgerOuterSpacingKey,
    padding: const EdgeInsets.fromLTRB(7, 10, 6, 5),
    child: Padding(
      key: AppBrandLockup.ledgerInnerSpacingKey,
      padding: const EdgeInsets.fromLTRB(5, 6, 5, 5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              SizedBox(
                width: 52,
                height: 86,
                child: RetainedAssetImage(
                  assetPath: IlluminatedLedgerSpec.dropCapAssetPath,
                  assetLabel: 'Illuminated B drop cap',
                  imageKey: AppBrandLockup.ledgerDropCapKey,
                  failureKey: AppBrandLockup.ledgerDropCapFailureKey,
                  fit: BoxFit.contain,
                  background: spec.palette.primary,
                  foreground: spec.palette.trimBright,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const Text(
                      'BLACK DESERT',
                      maxLines: 1,
                      style: TextStyle(
                        color: Color(0xFF6F501F),
                        fontFamily: 'Georgia',
                        fontSize: 9.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Text(
                      'BLACK SPIRIT\nLIFE',
                      key: AppBrandLockup.ledgerTitleKey,
                      maxLines: 2,
                      softWrap: false,
                      style: TextStyle(
                        color: Color(0xFF352516),
                        fontFamily: 'Georgia',
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        height: 19 / 17,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          _BrandRule(spec: spec),
          const SizedBox(height: 10),
        ],
      ),
    ),
  );
}

class _SakuraBrand extends StatelessWidget {
  const _SakuraBrand({required this.spec});

  final ThemeSpec spec;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(7, 10, 6, 5),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          'BLACK DESERT',
          maxLines: 1,
          style: spec.typography.label.copyWith(
            color: const Color(0xFFD8B7AD),
            fontFamily: 'Georgia',
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: .25,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          'Black Spirit\nLife',
          key: AppBrandLockup.sakuraTitleKey,
          maxLines: 2,
          softWrap: false,
          style: spec.typography.display.copyWith(
            color: SakuraNightGardenSpec.warmIvory,
            fontFamily: 'Georgia',
            fontSize: 34,
            fontWeight: FontWeight.w700,
            letterSpacing: -.35,
            height: 31 / 34,
          ),
        ),
        const SizedBox(height: 4),
        _BrandRule(spec: spec),
      ],
    ),
  );
}

class _BrandRule extends StatelessWidget {
  const _BrandRule({required this.spec});

  final ThemeSpec spec;

  @override
  Widget build(BuildContext context) {
    return switch (spec.family) {
      RetainedVisualFamily.standard => Builder(
        builder: (context) {
          final standard = context.standardVisual;
          return Container(
            width: 112,
            height: 3,
            margin: const EdgeInsets.only(left: 1, top: 8),
            decoration: BoxDecoration(
              gradient: StandardSpec.accentGlass(
                standard.accentHue,
                topAlpha: 190,
                bottomAlpha: 80,
                neon: standard.neon,
              ),
              borderRadius: BorderRadius.circular(999),
            ),
          );
        },
      ),
      RetainedVisualFamily.sakuraNightGarden => const SizedBox(
        key: AppBrandLockup.sakuraRuleKey,
        width: 172,
        height: 18,
        child: SakuraSectionRuleAsset(),
      ),
      RetainedVisualFamily.illuminatedLedger => FractionallySizedBox(
        widthFactor: .78,
        child: Container(
          key: AppBrandLockup.ledgerDividerKey,
          height: 1,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: <Color>[
                spec.palette.primaryBright,
                spec.palette.trimBright,
                spec.palette.trim.withAlpha(20),
              ],
            ),
          ),
        ),
      ),
    };
  }
}
