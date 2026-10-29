import 'package:flutter/material.dart';

import '../domain/gathering_crystals.dart';
import 'hover_pinned_details.dart';
import 'theme.dart';

/// A content-sized reference row; it has no calculator or selection callback.
class GatheringCrystalRecommendation extends StatelessWidget {
  const GatheringCrystalRecommendation({super.key});

  @override
  Widget build(BuildContext context) {
    const crystal = gatheringCrystalRecommendation;
    void pin() => showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        key: const ValueKey('gathering-crystal-pinned-card'),
        insetPadding: const EdgeInsets.all(16),
        child: const _CrystalDetails(pinned: true),
      ),
    );
    return Wrap(
      key: const ValueKey('gathering-setup-crystals'),
      spacing: 10,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          'Recommended crystals',
          style: TextStyle(fontSize: 13, color: context.gatheringColors.muted),
        ),
        HoverPinnedDetails(
          hoverKey: const ValueKey('gathering-crystal-hover-card'),
          cardBuilder: (context) => const _CrystalDetails(),
          onPin: pin,
          targetBuilder: (context, pinDetails) => Semantics(
            label: '${crystal.name}, up to ${crystal.maxCount}',
            button: true,
            child: Material(
              color: context.glass.row,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: BorderSide(color: context.glass.line),
              ),
              child: InkWell(
                key: const ValueKey('gathering-crystal-recommendation'),
                borderRadius: BorderRadius.circular(8),
                onTap: pinDetails,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(5, 4, 10, 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      GameIcon(crystal.icon, size: 36, grade: 4),
                      const SizedBox(width: 7),
                      Text(
                        '×${crystal.maxCount}',
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
        ),
      ],
    );
  }
}

class _CrystalDetails extends StatelessWidget {
  const _CrystalDetails({this.pinned = false});

  final bool pinned;

  @override
  Widget build(BuildContext context) {
    const crystal = gatheringCrystalRecommendation;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 380, maxHeight: 620),
      child: Material(
        color: context.glass.popup,
        elevation: pinned ? 0 : 12,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: context.glass.line),
        ),
        clipBehavior: Clip.antiAlias,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  GameIcon(crystal.icon, size: 36, grade: 4),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      crystal.name,
                      style: TextStyle(
                        color: context.gatheringColors.gold,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (pinned)
                    GatheringQuietIconButton(
                      key: const ValueKey('close-gathering-crystal-details'),
                      onPressed: () => Navigator.pop(context),
                      tooltip: 'Close',
                      icon: const Icon(Icons.close, size: 20),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              _heading('Per crystal'),
              _line('Life Skill Mastery +${crystal.masteryEach}'),
              _line('Life EXP +${crystal.lifeExpPercentEach}%'),
              const Divider(height: 18),
              _heading('Slots'),
              for (final note in crystal.slotNotes) _line(note),
              const Divider(height: 18),
              _heading('Budget alternative'),
              _line(crystal.budgetNote),
              const SizedBox(height: 5),
              Text(
                crystal.calculatorNote,
                style: TextStyle(
                  fontSize: 12,
                  color: context.gatheringColors.muted,
                  height: 1.25,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _heading(String text) => Builder(
    builder: (context) => Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 13,
          color: context.gatheringColors.accent,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
  );

  Widget _line(String text) => Builder(
    builder: (context) => Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 13.5,
          color: context.gatheringColors.ink,
          height: 1.25,
        ),
      ),
    ),
  );
}
