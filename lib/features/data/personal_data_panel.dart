import 'package:flutter/material.dart';

import '../../visual/visual.dart';
import 'profile_presentation.dart';

/// A read-only summary of the active profile location, not a storage policy.
class PersonalDataPanel extends StatelessWidget {
  const PersonalDataPanel({
    required this.activePath,
    required this.onOpenFolder,
    required this.onChangeLocation,
    this.moving = false,
    super.key,
  });

  final String? activePath;
  final VoidCallback? onOpenFolder;
  final VoidCallback? onChangeLocation;
  final bool moving;

  static const _categories = <(String, IconData)>[
    ('Inventory', Icons.inventory_2_outlined),
    ('Character & mastery', Icons.person_outline_rounded),
    ('App settings', Icons.settings_outlined),
    ('Favourites', Icons.star_outline_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    final palette = context.visualTheme.palette;
    final path = activePath?.trim();
    final available = path != null && path.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const _FolderInlay(),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('BS Life App', style: ProfileTypography.group(context)),
                  const SizedBox(height: 4),
                  SelectableText(
                    available ? path : 'Folder unavailable',
                    key: const ValueKey('data-personal-data-path'),
                    style: ProfileTypography.label(context),
                  ),
                ],
              ),
            ),
          ],
        ),
        Container(
          margin: const EdgeInsets.only(top: 19),
          padding: const EdgeInsets.symmetric(vertical: 17),
          decoration: BoxDecoration(
            border: Border.symmetric(
              horizontal: BorderSide(
                color: palette.trim.withValues(alpha: .55),
              ),
            ),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final scale = MediaQuery.textScalerOf(context).scale(13) / 13;
              final wide = constraints.maxWidth >= 500 * scale;
              Widget row(int start, int end) => IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var index = start; index < end; index++) ...[
                      if (index > start) const SizedBox(width: 10),
                      Expanded(
                        flex: wide && index == 1 ? 15 : 10,
                        child: _CategoryTile(
                          label: _categories[index].$1,
                          icon: _categories[index].$2,
                        ),
                      ),
                    ],
                  ],
                ),
              );
              return wide
                  ? row(0, 4)
                  : Column(
                      children: [
                        row(0, 2),
                        const SizedBox(height: 10),
                        row(2, 4),
                      ],
                    );
            },
          ),
        ),
        const SizedBox(height: 14),
        Wrap(
          alignment: WrapAlignment.end,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 14,
          runSpacing: 8,
          children: [
            TextButton(
              key: const ValueKey('data-personal-data-browse'),
              onPressed: moving ? null : onChangeLocation,
              style: TextButton.styleFrom(
                foregroundColor: ProfileTypography.secondary(context),
                textStyle: ProfileTypography.label(context),
                minimumSize: const Size(0, 36),
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              ),
              child: Text(moving ? 'Moving…' : 'Change location'),
            ),
            AppButton(
              key: const ValueKey('data-personal-data-open'),
              role: AppButtonRole.primary,
              semanticLabel: 'Open personal data folder',
              onPressed: available && !moving ? onOpenFolder : null,
              minimumSize: const Size(0, 36),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 7,
                children: [
                  const Icon(Icons.folder_open_outlined, size: 18),
                  const Text('Open folder'),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

LinearGradient _copperGradient(BuildContext context) {
  final palette = context.visualTheme.palette;
  final warm = Color.lerp(palette.trimBright, palette.warning, .3)!;
  return LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color.lerp(warm, palette.surfaceRaised, .15)!,
      Color.lerp(palette.trim, palette.surfaceRaised, .34)!,
      Color.lerp(palette.trim, palette.surfaceInset, .22)!,
      Color.lerp(warm, palette.trim, .4)!,
    ],
    stops: const [0, .25, .67, 1],
  );
}

class _FolderInlay extends StatelessWidget {
  const _FolderInlay();

  @override
  Widget build(BuildContext context) {
    final palette = context.visualTheme.palette;
    return Container(
      key: const ValueKey('data-personal-data-folder-inlay'),
      width: 52,
      height: 52,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: _copperGradient(context),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: palette.trimBright),
        boxShadow: [
          BoxShadow(
            color: palette.shadow.withValues(alpha: .3),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Color.lerp(palette.surfaceInset, palette.surface, .25),
          border: Border.all(color: palette.trimBright.withValues(alpha: .6)),
          borderRadius: BorderRadius.circular(3),
        ),
        child: Icon(Icons.folder_open_outlined, size: 27, color: palette.text),
      ),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({required this.label, required this.icon});
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final palette = context.visualTheme.palette;
    return Semantics(
      label: label,
      child: ExcludeSemantics(
        child: DecoratedBox(
          key: ValueKey('data-category:$label'),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color.lerp(palette.surfaceRaised, palette.trimBright, .12)!,
                palette.surface,
                palette.surfaceInset,
              ],
            ),
            border: Border.all(color: palette.trimBright.withValues(alpha: .7)),
            boxShadow: [
              BoxShadow(
                color: palette.shadow.withValues(alpha: .25),
                blurRadius: 3,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(1),
            child: Column(
              children: [
                Container(
                  height: 35,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    gradient: _copperGradient(context),
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(3),
                    ),
                    border: Border(
                      bottom: BorderSide(color: palette.trimBright),
                    ),
                  ),
                  child: Icon(icon, size: 22, color: palette.text),
                ),
                Expanded(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 42),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 8,
                      ),
                      child: Center(
                        child: Text(
                          label,
                          textAlign: TextAlign.center,
                          style: ProfileTypography.supporting(context).copyWith(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            height: 19 / 13,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
