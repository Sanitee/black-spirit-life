import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../domain/models/craft_mode.dart';
import '../../visual/visual.dart';
import '../shared/profile_game_icon.dart';
import 'profile_presentation.dart';

typedef ProfileMasteryFieldBuilder =
    Widget Function(CraftMode mode, String value);

/// Presentation only: yields and mastery commits stay in the existing controller.
class ProfileMasteryControls extends StatelessWidget {
  const ProfileMasteryControls({
    required this.alchemyMastery,
    required this.cookingMastery,
    required this.processingMastery,
    required this.alchemyYield,
    required this.massBatch,
    required this.useMassProcessing,
    required this.onMassProcessingChanged,
    required this.fieldBuilder,
    super.key,
  });

  final String alchemyMastery;
  final String cookingMastery;
  final String processingMastery;
  final String alchemyYield;
  final int massBatch;
  final bool useMassProcessing;
  final VoidCallback onMassProcessingChanged;
  final ProfileMasteryFieldBuilder fieldBuilder;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
      const gap = 18.0;
      final minimumGroupWidth = 64 + 100 * scale;
      final columns = ((constraints.maxWidth + gap) / (minimumGroupWidth + gap))
          .floor()
          .clamp(1, 3);
      final groupWidth = (constraints.maxWidth - gap * (columns - 1)) / columns;
      final groups = [
        (CraftMode.alchemy, 'Alchemy', ProfileArtwork.alchemy, alchemyMastery),
        (CraftMode.cooking, 'Cooking', ProfileArtwork.cooking, cookingMastery),
        (
          CraftMode.processing,
          'Processing',
          ProfileArtwork.processing,
          processingMastery,
        ),
      ];
      final resultCells = <Widget>[
        _MasteryResult(
          artwork: ProfileArtwork.alchemy,
          label: 'Expected output',
          value: alchemyYield,
          unit: '/ craft',
        ),
        _MasteryResult(
          artwork: ProfileArtwork.processing,
          label: 'Mass batch',
          value: useMassProcessing ? '$massBatch' : 'Off',
          unit: useMassProcessing ? 'recipes' : '',
          control: FocusTraversalOrder(
            order: const NumericFocusOrder(4),
            child: InkWell(
              key: const ValueKey<String>('D05'),
              onTap: onMassProcessingChanged,
              child: Semantics(
                label: 'Mass processing stone',
                checked: useMassProcessing,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Icon(
                        useMassProcessing
                            ? Icons.check_box_outlined
                            : Icons.check_box_outline_blank,
                        size: 18,
                        color: context.visualTheme.palette.primaryBright,
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          'Mass processing stone',
                          style: ProfileTypography.label(context),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ];
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: gap,
            runSpacing: 18,
            children: [
              for (var index = 0; index < groups.length; index++)
                SizedBox(
                  width: groupWidth,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      if (index % columns != 0)
                        Positioned(
                          left: -9,
                          top: 0,
                          bottom: 0,
                          child: ColoredBox(
                            color: context.visualTheme.palette.trim.withValues(
                              alpha: .65,
                            ),
                            child: const SizedBox(width: 1),
                          ),
                        ),
                      _MasteryGroup(
                        title: groups[index].$2,
                        artwork: groups[index].$3,
                        child: FocusTraversalOrder(
                          order: NumericFocusOrder((index + 1).toDouble()),
                          child: fieldBuilder(
                            groups[index].$1,
                            groups[index].$4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 18),
          ProfileResultFrame(
            key: const ValueKey('profile-mastery-results'),
            child: LayoutBuilder(
              builder: (context, resultConstraints) {
                if (resultConstraints.maxWidth < 380 * scale) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      resultCells[0],
                      const SizedBox(height: 18),
                      resultCells[1],
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: resultCells[0]),
                    const SizedBox(width: 24),
                    Expanded(child: resultCells[1]),
                  ],
                );
              },
            ),
          ),
        ],
      );
    },
  );
}

class _MasteryGroup extends StatelessWidget {
  const _MasteryGroup({
    required this.title,
    required this.artwork,
    required this.child,
  });

  final String title;
  final ProfileArtwork artwork;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    return Column(
      key: ValueKey('craft-skill:$title'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 64),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: ProfileTypography.group(context)),
              const SizedBox(height: 5),
              Text('Mastery', style: ProfileTypography.label(context)),
            ],
          ),
        ),
        const SizedBox(height: 5),
        SizedBox(
          height: math.max(52, scaler.scale(16) * 22 / 16 + 16),
          child: Row(
            children: [
              ProfileIconInlay(artwork: artwork),
              const SizedBox(width: 12),
              Flexible(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: scaler.scale(124)),
                  child: child,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MasteryResult extends StatelessWidget {
  const _MasteryResult({
    required this.artwork,
    required this.label,
    required this.value,
    required this.unit,
    this.control,
  });

  final ProfileArtwork artwork;
  final String label;
  final String value;
  final String unit;
  final Widget? control;

  @override
  Widget build(BuildContext context) => Column(
    key: ValueKey('profile-output:${artwork.name}'),
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.only(left: 47),
        child: Text(label, style: ProfileTypography.label(context)),
      ),
      const SizedBox(height: 3),
      Row(
        key: ValueKey('profile-result:${artwork.name}'),
        children: [
          ProfileIcon(artwork: artwork, size: 36),
          const SizedBox(width: 11),
          Expanded(
            child: Text.rich(
              TextSpan(
                text: value,
                children: [
                  if (unit.isNotEmpty)
                    TextSpan(
                      text: ' $unit',
                      style: ProfileTypography.label(context),
                    ),
                ],
              ),
              style: ProfileTypography.result(context),
            ),
          ),
        ],
      ),
      if (control != null)
        Padding(
          padding: const EdgeInsets.only(left: 47, top: 3),
          child: control,
        ),
    ],
  );
}
