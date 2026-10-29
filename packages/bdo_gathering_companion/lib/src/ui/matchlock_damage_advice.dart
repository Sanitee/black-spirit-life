import 'package:flutter/material.dart';

import '../domain/matchlock_advice.dart';
import '../services/native_bridge.dart';
import 'hover_pinned_details.dart';
import 'theme.dart';

/// Matchlock reference details never modify the preparation profile.
class MatchlockDamageAdvice extends StatelessWidget {
  const MatchlockDamageAdvice({super.key});

  @override
  Widget build(BuildContext context) => Column(
    key: const ValueKey('matchlock-damage-advice'),
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Wrap(
        spacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text('Damage setup', style: Theme.of(context).textTheme.titleSmall),
          GatheringQuietIconButton(
            key: const ValueKey('matchlock-damage-info'),
            tooltip: 'Matchlock damage tips',
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => const _DamageDialog(),
            ),
            icon: Icon(
              Icons.info_outline,
              size: 19,
              color: context.gatheringColors.muted,
            ),
          ),
        ],
      ),
      const SizedBox(height: 2),
      Text(
        'Example crystals',
        style: TextStyle(color: context.gatheringColors.muted, fontSize: 13),
      ),
      const SizedBox(height: 10),
      Wrap(
        spacing: 9,
        runSpacing: 9,
        children: [
          for (final entry in matchlockCrystalAdvice) _CrystalChip(entry),
        ],
      ),
    ],
  );
}

class _CrystalChip extends StatelessWidget {
  const _CrystalChip(this.entry);

  final MatchlockAdviceEntry entry;

  @override
  Widget build(BuildContext context) => HoverPinnedDetails(
    hoverKey: ValueKey('matchlock-crystal-hover-${entry.id}'),
    cardBuilder: (_) => _CrystalDetails(entry),
    onPin: () => showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        key: ValueKey('matchlock-crystal-dialog-${entry.id}'),
        insetPadding: const EdgeInsets.all(16),
        child: _CrystalDetails(entry, pinned: true),
      ),
    ),
    targetBuilder: (context, pin) => Semantics(
      label: '${entry.name}, ${entry.count} crystals. Details',
      button: true,
      child: GlassControl(
        radius: 8,
        child: InkWell(
          key: ValueKey('matchlock-crystal-${entry.id}'),
          onTap: pin,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(5, 4, 10, 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                GameIcon(entry.icon, size: 36),
                const SizedBox(width: 7),
                Text(
                  '×${entry.count}',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: context.gatheringColors.accent,
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.info_outline,
                  size: 16,
                  color: context.gatheringColors.muted,
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _DamageDialog extends StatelessWidget {
  const _DamageDialog();

  @override
  Widget build(BuildContext context) => Dialog(
    key: const ValueKey('matchlock-damage-dialog'),
    insetPadding: const EdgeInsets.all(16),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 640, maxHeight: 780),
      child: GlassSurface(
        reading: true,
        radius: 16,
        child: _ReadingScroll(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _DetailHeading(
                title: 'Matchlock damage setup',
                closeKey: const ValueKey('matchlock-close-damage-details'),
                icon: GlassArtworkWell(
                  tool: true,
                  child: const GameIcon(
                    'assets/icons/tools/hunting_matchlock.webp',
                    size: 36,
                    backgroundColor: Colors.transparent,
                  ),
                ),
              ),
              const SizedBox(height: 18),
              LayoutBuilder(
                builder: (context, constraints) {
                  final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
                  final columns = constraints.maxWidth >= 550 * scale ? 2 : 1;
                  final width =
                      (constraints.maxWidth - (columns - 1) * 24) / columns;
                  return Wrap(
                    key: const ValueKey('matchlock-damage-sections'),
                    spacing: 24,
                    runSpacing: 22,
                    children: [
                      for (final section in matchlockDamageSections)
                        SizedBox(width: width, child: _AdviceSection(section)),
                    ],
                  );
                },
              ),
              const SizedBox(height: 16),
              const _Sources(
                id: 'matchlock-damage',
                sources: matchlockAdviceSources,
              ),
              const SizedBox(height: 8),
              Text(
                'Tips only. Your stats and estimates stay unchanged.',
                style: TextStyle(
                  color: context.gatheringColors.muted,
                  fontSize: 13,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _CrystalDetails extends StatelessWidget {
  const _CrystalDetails(this.entry, {this.pinned = false});

  final MatchlockAdviceEntry entry;
  final bool pinned;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 380, maxHeight: 620),
    child: GlassSurface(
      reading: true,
      radius: 14,
      child: _ReadingScroll(
        selectable: pinned,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _DetailHeading(
              title: entry.name,
              icon: GameIcon(entry.icon, size: 36),
              closeKey: pinned
                  ? ValueKey('matchlock-close-crystal-${entry.id}')
                  : null,
            ),
            const SizedBox(height: 14),
            Text(
              entry.benefit,
              style: TextStyle(
                color: context.gatheringColors.accent,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                height: 1.35,
              ),
            ),
            if (entry.notes.isNotEmpty) const SizedBox(height: 12),
            for (final note in entry.notes)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  note,
                  style: const TextStyle(fontSize: 14, height: 1.4),
                ),
              ),
            _Sources(
              id: 'matchlock-crystal-${entry.id}',
              sources: entry.sources,
            ),
          ],
        ),
      ),
    ),
  );
}

class _DetailHeading extends StatelessWidget {
  const _DetailHeading({
    required this.title,
    required this.icon,
    this.closeKey,
  });

  final String title;
  final Widget icon;
  final Key? closeKey;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      icon,
      const SizedBox(width: 10),
      Expanded(
        child: Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              height: 1.2,
            ),
          ),
        ),
      ),
      if (closeKey != null) ...[
        const SizedBox(width: 4),
        GatheringQuietIconButton(
          key: closeKey,
          tooltip: 'Close',
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.close, size: 20),
        ),
      ],
    ],
  );
}

class _AdviceSection extends StatelessWidget {
  const _AdviceSection(this.section);

  final MatchlockAdviceSection section;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        section.title,
        style: TextStyle(
          color: context.gatheringColors.accent,
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
      ),
      const SizedBox(height: 9),
      for (final line in section.lines)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(line, style: const TextStyle(fontSize: 14, height: 1.4)),
        ),
    ],
  );
}

class _ReadingScroll extends StatelessWidget {
  const _ReadingScroll({required this.child, this.selectable = true});

  final Widget child;
  final bool selectable;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(18),
        child: selectable ? SelectionArea(child: child) : child,
      ),
    ),
  );
}

class _Sources extends StatefulWidget {
  const _Sources({required this.id, required this.sources});

  final String id;
  final List<MatchlockAdviceSource> sources;

  @override
  State<_Sources> createState() => _SourcesState();
}

class _SourcesState extends State<_Sources> {
  String? _error;

  Future<void> _open(MatchlockAdviceSource source) async {
    var opened = false;
    try {
      opened = await NativeBridge.openExternal(source.url);
    } catch (_) {
      // Keep the advice available when the desktop cannot open a browser.
    }
    if (!mounted) return;
    setState(() => _error = opened ? null : 'Could not open ${source.label}.');
  }

  @override
  Widget build(BuildContext context) => widget.sources.isEmpty
      ? const SizedBox.shrink()
      : ExpansionTile(
          key: ValueKey('${widget.id}-sources'),
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(bottom: 6),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          title: const Text('Sources', style: TextStyle(fontSize: 13)),
          children: [
            for (var index = 0; index < widget.sources.length; index++)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  key: ValueKey('${widget.id}-source-$index'),
                  onPressed: () => _open(widget.sources[index]),
                  icon: const Icon(Icons.open_in_new, size: 16),
                  label: Text(widget.sources[index].label),
                ),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  _error!,
                  style: TextStyle(
                    fontSize: 13,
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ),
          ],
        );
}
