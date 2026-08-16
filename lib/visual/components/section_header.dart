import 'package:flutter/material.dart';

import '../foundations/theme_spec.dart';
import '../illuminated_ledger/ledger_ornament_painters.dart';
import '../sakura_night_garden/sakura_botanical_assets.dart';

/// Theme-aware section title with a restrained retained-system divider.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    required this.title,
    this.spec,
    this.meta,
    this.leading,
    this.trailing,
    this.padding = EdgeInsets.zero,
    super.key,
  });

  final String title;
  final ThemeSpec? spec;
  final String? meta;
  final Widget? leading;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  static const Key titleKey = ValueKey<String>('section-header-title');
  static const Key ruleKey = ValueKey<String>('section-header-rule');
  static const Key coreKey = ValueKey<String>('section-header-core');
  static const Key trailingKey = ValueKey<String>('section-header-trailing');

  @override
  Widget build(BuildContext context) {
    final tokens = spec ?? context.visualTheme;
    final manuscript = tokens.family == RetainedVisualFamily.illuminatedLedger;
    final sakura = tokens.family == RetainedVisualFamily.sakuraNightGarden;
    final displayTitle = manuscript ? title.toUpperCase() : title;
    final sectionFontSize = manuscript
        ? (tokens.typography.section.fontSize ?? 25)
        : sakura
        ? (tokens.typography.section.fontSize ?? 25)
        : 28.0;
    final textScale =
        MediaQuery.textScalerOf(context).scale(sectionFontSize) /
        sectionFontSize;
    final enlargedText = textScale > 1.25;

    Widget titleLabel() => Text(
      displayTitle,
      key: titleKey,
      // Avalonia's Ledger TextBlock is a single no-wrap row. Retain a second
      // line only for the enlarged-text responsive layout.
      maxLines: tokens.usesDenseSplitLayout && !enlargedText ? 1 : 2,
      overflow: TextOverflow.ellipsis,
      style: switch (tokens.family) {
        RetainedVisualFamily.illuminatedLedger =>
          tokens.typography.section.copyWith(color: tokens.palette.primary),
        RetainedVisualFamily.sakuraNightGarden =>
          tokens.typography.section.copyWith(
            color: tokens.palette.text,
            fontFamily: 'Georgia',
            fontWeight: FontWeight.w600,
          ),
        RetainedVisualFamily.standard => tokens.typography.section.copyWith(
          color: const Color(0xFFFFF1BB),
          fontFamily: 'Georgia',
          fontSize: 28,
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
          height: 1.08,
        ),
      },
    );

    Widget metaLabel(String value) => ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 220),
      child: Text(
        value,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.end,
        style: switch (tokens.family) {
          RetainedVisualFamily.illuminatedLedger =>
            tokens.typography.meta.copyWith(
              color: tokens.palette.text,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              fontStyle: FontStyle.normal,
            ),
          RetainedVisualFamily.sakuraNightGarden =>
            tokens.typography.meta.copyWith(
              color: tokens.palette.textMuted,
              fontFamily: 'Segoe UI',
              fontSize: 13,
              fontWeight: FontWeight.w600,
              fontStyle: FontStyle.normal,
            ),
          RetainedVisualFamily.standard => tokens.typography.meta.copyWith(
            color: const Color(0xFFAEEEDF),
            fontFamily: 'Segoe UI',
            fontSize: 13,
            fontWeight: FontWeight.w600,
            fontStyle: FontStyle.normal,
          ),
        },
      ),
    );

    final standardHeader = enlargedText && (meta != null || trailing != null)
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Row(
                children: <Widget>[
                  if (leading case final widget?) ...<Widget>[
                    widget,
                    const SizedBox(width: 9),
                  ],
                  Expanded(child: titleLabel()),
                ],
              ),
              const SizedBox(height: 6),
              SizedBox(
                width: double.infinity,
                child: Wrap(
                  alignment: WrapAlignment.end,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 12,
                  runSpacing: 6,
                  children: <Widget>[
                    if (meta case final value?) metaLabel(value),
                    ?trailing,
                  ],
                ),
              ),
            ],
          )
        : Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              if (leading case final widget?) ...<Widget>[
                widget,
                const SizedBox(width: 9),
              ],
              Expanded(child: titleLabel()),
              if (meta case final value?) ...<Widget>[
                const SizedBox(width: 12),
                metaLabel(value),
              ],
              if (trailing case final widget?) ...<Widget>[
                const SizedBox(width: 12),
                widget,
              ],
            ],
          );

    Widget ledgerTitleAndMeta() => enlargedText && meta != null
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Row(
                children: <Widget>[
                  if (leading case final widget?) ...<Widget>[
                    widget,
                    const SizedBox(width: 9),
                  ],
                  Expanded(child: titleLabel()),
                ],
              ),
              const SizedBox(height: 6),
              Align(alignment: Alignment.centerRight, child: metaLabel(meta!)),
            ],
          )
        : Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              if (leading case final widget?) ...<Widget>[
                widget,
                const SizedBox(width: 9),
              ],
              Expanded(child: titleLabel()),
              if (meta case final value?) ...<Widget>[
                const SizedBox(width: 12),
                metaLabel(value),
              ],
            ],
          );

    final ledgerCore = ConstrainedBox(
      key: coreKey,
      constraints: const BoxConstraints(minHeight: 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          ledgerTitleAndMeta(),
          const SizedBox(height: 2),
          SizedBox(
            key: ruleKey,
            height: 7,
            child: CustomPaint(
              painter: LedgerSectionRulePainter(
                trim: tokens.palette.trim.withAlpha(170),
              ),
            ),
          ),
        ],
      ),
    );

    final ledgerHeader = trailing == null
        ? ledgerCore
        : enlargedText
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              ledgerCore,
              const SizedBox(height: 10),
              Align(
                key: trailingKey,
                alignment: Alignment.centerRight,
                child: trailing,
              ),
            ],
          )
        : Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              Expanded(child: ledgerCore),
              const SizedBox(width: 10),
              KeyedSubtree(key: trailingKey, child: trailing!),
            ],
          );

    final sakuraRule = SizedBox(
      key: ruleKey,
      height: 18,
      child: const SakuraSectionRuleAsset(),
    );
    final sakuraHeader = ConstrainedBox(
      key: coreKey,
      constraints: const BoxConstraints(minHeight: 36),
      child: enlargedText
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    if (leading case final widget?) ...<Widget>[
                      widget,
                      const SizedBox(width: 9),
                    ],
                    Expanded(child: titleLabel()),
                  ],
                ),
                const SizedBox(height: 3),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: <Widget>[
                    Expanded(child: sakuraRule),
                    if (meta case final value?) ...<Widget>[
                      const SizedBox(width: 12),
                      metaLabel(value),
                    ],
                  ],
                ),
                if (trailing case final widget?) ...<Widget>[
                  const SizedBox(height: 6),
                  Align(
                    key: trailingKey,
                    alignment: Alignment.centerRight,
                    child: widget,
                  ),
                ],
              ],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                if (leading case final widget?) ...<Widget>[
                  widget,
                  const SizedBox(width: 9),
                ],
                // Preserve the full canonical "Craft Queue" lockup at the
                // 1500px acceptance size. The previous 3:5 split made the
                // decorative branch win a few pixels over the real heading,
                // causing a visible ellipsis even though the row had room.
                Flexible(flex: 4, fit: FlexFit.loose, child: titleLabel()),
                const SizedBox(width: 10),
                Expanded(flex: 5, child: sakuraRule),
                if (meta case final value?) ...<Widget>[
                  const SizedBox(width: 12),
                  metaLabel(value),
                ],
                if (trailing case final widget?) ...<Widget>[
                  const SizedBox(width: 12),
                  KeyedSubtree(key: trailingKey, child: widget),
                ],
              ],
            ),
    );

    return Semantics(
      header: true,
      child: Padding(
        padding: padding,
        child: switch (tokens.family) {
          RetainedVisualFamily.illuminatedLedger => ledgerHeader,
          RetainedVisualFamily.sakuraNightGarden => sakuraHeader,
          RetainedVisualFamily.standard => standardHeader,
        },
      ),
    );
  }
}
