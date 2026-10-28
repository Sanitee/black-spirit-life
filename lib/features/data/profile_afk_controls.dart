import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../domain/formatting/planner_formatters.dart';
import '../../domain/state/planner_state.dart';
import '../../visual/visual.dart';
import '../shared/profile_game_icon.dart';
import 'profile_presentation.dart';

/// The caller retains each input's controller, validation and commit behavior.
/// Only its visible label and the surrounding control track live here.
typedef ProfileAfkFieldBuilder =
    Widget Function({
      required Key fieldKey,
      required String label,
      required String value,
      required ValueChanged<String> onCommit,
    });

/// Native presentation of the existing AFK profile; no settings are stored here.
class ProfileAfkControls extends StatelessWidget {
  const ProfileAfkControls({
    required this.profile,
    required this.onMaximumWeightCommitted,
    required this.onCurrentWeightCommitted,
    required this.onSafetyBufferCommitted,
    required this.onFeatheryStepsChanged,
    required this.fieldBuilder,
    super.key,
  });

  final AfkWeightProfile profile;
  final ValueChanged<String> onMaximumWeightCommitted;
  final ValueChanged<String> onCurrentWeightCommitted;
  final ValueChanged<String> onSafetyBufferCommitted;
  final ValueChanged<int> onFeatheryStepsChanged;
  final ProfileAfkFieldBuilder fieldBuilder;

  static const _bay = 52.0;
  static const _gap = 12.0;
  static const _fields = <(String, String, String)>[
    ('maximum', 'Maximum weight', 'data-afk-maximum-weight'),
    ('current', 'Current weight', 'data-afk-current-weight'),
    ('free', 'Keep free', 'data-afk-safety-buffer'),
  ];

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    final values = <double>[
      profile.maximumWeightLt,
      profile.currentCarriedWeightLt,
      profile.safetyBufferLt,
    ];
    final commits = <ValueChanged<String>>[
      onMaximumWeightCommitted,
      onCurrentWeightCommitted,
      onSafetyBufferCommitted,
    ];
    final labelStyle = ProfileTypography.label(context);
    final numberStyle = ProfileTypography.input(context);
    final valueWidth =
        <String>['99.999', for (final value in values) formatQuantity(value)]
            .map((text) => _measure(context, text, numberStyle).width)
            .reduce(math.max);
    final labelWidth = _fields
        .map((field) => _measure(context, field.$2, labelStyle).width)
        .reduce(math.max);
    final fieldWidth = math.max(
      124.0,
      math.max(
        labelWidth,
        valueWidth + _measure(context, 'LT', labelStyle).width + 30,
      ),
    );
    final controlHeight = math.max(_bay, scaler.scale(22) + 22);
    final fullControlsWidth = _bay + _gap + fieldWidth * 3 + _gap * 2;
    final summaryWidth = math.max(
      184.0,
      _measure(context, 'Maximum you can carry', labelStyle).width + 28,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide =
            constraints.maxWidth >= fullControlsWidth + 18 + summaryWidth;
        final controlsWidth = wide
            ? constraints.maxWidth - 18 - summaryWidth
            : constraints.maxWidth;
        return Wrap(
          key: const ValueKey('profile-afk-controls'),
          spacing: 18,
          runSpacing: 16,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: controlsWidth,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _weightInputs(
                    context,
                    controlsWidth: controlsWidth,
                    desiredFieldWidth: fieldWidth,
                    controlHeight: controlHeight,
                    values: values,
                    commits: commits,
                  ),
                  const SizedBox(height: 18),
                  _fairyControls(context),
                ],
              ),
            ),
            SizedBox(
              width: wide ? summaryWidth : constraints.maxWidth,
              child: _WeightSummary(profile: profile, allowHorizontal: !wide),
            ),
          ],
        );
      },
    );
  }

  Widget _weightInputs(
    BuildContext context, {
    required double controlsWidth,
    required double desiredFieldWidth,
    required double controlHeight,
    required List<double> values,
    required List<ValueChanged<String>> commits,
  }) {
    final available = math.max(0.0, controlsWidth - _bay - _gap);
    final columns = ((available + _gap) / (desiredFieldWidth + _gap))
        .floor()
        .clamp(1, 3)
        .toInt();
    final width = math.min(
      desiredFieldWidth,
      math.max(0.0, (available - _gap * (columns - 1)) / columns),
    );
    final labelHeight = _fields
        .map(
          (field) => _measure(
            context,
            field.$2,
            ProfileTypography.label(context),
            maxWidth: width,
          ).height,
        )
        .reduce(math.max);

    return Row(
      key: const ValueKey('profile-afk-inputs'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(top: labelHeight + 5),
          child: SizedBox(
            width: _bay,
            height: controlHeight,
            child: const Center(
              child: ProfileIconInlay(artwork: ProfileArtwork.weight),
            ),
          ),
        ),
        const SizedBox(width: _gap),
        Expanded(
          child: Wrap(
            spacing: _gap,
            runSpacing: 12,
            children: [
              for (var index = 0; index < _fields.length; index++)
                SizedBox(
                  key: ValueKey('profile-afk-field-cell:${_fields[index].$1}'),
                  width: width,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        height: labelHeight,
                        child: Text(
                          _fields[index].$2,
                          style: ProfileTypography.label(context),
                        ),
                      ),
                      const SizedBox(height: 5),
                      SizedBox(
                        key: ValueKey(
                          'profile-afk-control-track:${_fields[index].$1}',
                        ),
                        height: controlHeight,
                        child: Center(
                          child: fieldBuilder(
                            fieldKey: ValueKey(_fields[index].$3),
                            label: _fields[index].$2,
                            value: formatQuantity(values[index]),
                            onCommit: commits[index],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _fairyControls(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.only(left: _bay + _gap),
        child: Text('Feathery Steps', style: ProfileTypography.group(context)),
      ),
      const SizedBox(height: 5),
      Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const ProfileIconInlay(artwork: ProfileArtwork.featherySteps),
          const SizedBox(width: _gap),
          Expanded(
            child: ConstrainedBox(
              key: const ValueKey('profile-afk-rank-track'),
              constraints: const BoxConstraints(minHeight: _bay),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  key: const ValueKey('data-afk-feathery-steps'),
                  spacing: 4,
                  runSpacing: 4,
                  children: [
                    for (var level = 0; level <= 5; level++)
                      AppButton(
                        key: ValueKey('data-afk-feathery-steps:$level'),
                        role: AppButtonRole.optionPill,
                        selected: profile.featheryStepsLevel == level,
                        minimumSize: const Size(32, 32),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 5,
                        ),
                        semanticLabel:
                            'Feathery Steps ${_rankLabel(level)}, ${100 + level * 5}% weight threshold',
                        tooltip: '${100 + level * 5}% weight threshold',
                        onPressed: () => onFeatheryStepsChanged(level),
                        child: Text(
                          _rankLabel(level),
                          // State foreground belongs to AppButton, especially
                          // Ledger's cream text on its selected navy surface.
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            height: 16 / 12,
                            letterSpacing: 0,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    ],
  );
}

class _WeightSummary extends StatelessWidget {
  const _WeightSummary({required this.profile, required this.allowHorizontal});

  final AfkWeightProfile profile;
  final bool allowHorizontal;

  @override
  Widget build(BuildContext context) => ProfileResultFrame(
    key: const ValueKey('profile-afk-result-frame'),
    padding: const EdgeInsets.all(14),
    child: Semantics(
      liveRegion: true,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final horizontal =
              allowHorizontal &&
              constraints.maxWidth >=
                  MediaQuery.textScalerOf(context).scale(400);
          final separator = context.visualTheme.palette.trim.withValues(
            alpha: .5,
          );
          final room = _metric(
            context,
            label: 'Room for ingredients',
            value: profile.isConfigured
                ? formatQuantity(profile.safeLimitLt)
                : 'Enter Max LT',
            configured: profile.isConfigured,
            primary: true,
          );
          final safeStop = (profile.penaltyThresholdLt - profile.safetyBufferLt)
              .clamp(0, double.infinity)
              .toDouble();
          final limit = _metric(
            context,
            label: 'Maximum you can carry',
            value: profile.isConfigured
                ? formatQuantity(safeStop)
                : 'Not calculated',
            configured: profile.isConfigured,
          );
          if (horizontal) {
            return Row(
              children: [
                Expanded(child: room),
                const SizedBox(width: 20),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.only(left: 20),
                    decoration: BoxDecoration(
                      border: Border(left: BorderSide(color: separator)),
                    ),
                    child: limit,
                  ),
                ),
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              room,
              Container(
                margin: const EdgeInsets.only(top: 12),
                padding: const EdgeInsets.only(top: 10),
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: separator)),
                ),
                child: limit,
              ),
            ],
          );
        },
      ),
    ),
  );

  Widget _metric(
    BuildContext context, {
    required String label,
    required String value,
    required bool configured,
    bool primary = false,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(label, style: ProfileTypography.label(context)),
      SizedBox(height: primary ? 5 : 3),
      Text.rich(
        key: ValueKey(
          primary ? 'profile-afk-room-value' : 'profile-afk-limit-value',
        ),
        TextSpan(
          text: value,
          children: [
            if (configured)
              TextSpan(text: ' LT', style: ProfileTypography.label(context)),
          ],
        ),
        style: primary
            ? ProfileTypography.result(context)
            : ProfileTypography.supporting(context),
      ),
    ],
  );
}

String _rankLabel(int level) =>
    const ['None', 'I', 'II', 'III', 'IV', 'V'][level];

Size _measure(
  BuildContext context,
  String text,
  TextStyle style, {
  double maxWidth = double.infinity,
}) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
  )..layout(maxWidth: maxWidth);
  final size = painter.size;
  painter.dispose();
  return size;
}
