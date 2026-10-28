import 'package:bdo_craft_planner_flutter/domain/state/planner_state.dart';
import 'package:bdo_craft_planner_flutter/features/data/profile_afk_controls.dart';
import 'package:bdo_craft_planner_flutter/features/data/profile_presentation.dart';
import 'package:bdo_craft_planner_flutter/visual/visual.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('inlays align to equal input tracks and the rank control row', (
    tester,
  ) async {
    await _pump(tester, width: 1000);

    final weight = tester.getRect(
      find.byKey(const ValueKey('profile-inlay:weight')),
    );
    final maximum = tester.getRect(
      find.byKey(const ValueKey('profile-afk-control-track:maximum')),
    );
    final current = tester.getRect(
      find.byKey(const ValueKey('profile-afk-control-track:current')),
    );
    final free = tester.getRect(
      find.byKey(const ValueKey('profile-afk-control-track:free')),
    );
    expect(weight.size, const Size(52, 52));
    expect(weight.center.dy, closeTo(maximum.center.dy, .01));
    expect(maximum.top, closeTo(current.top, .01));
    expect(maximum.top, closeTo(free.top, .01));
    expect(maximum.width, closeTo(current.width, .01));
    expect(maximum.width, closeTo(free.width, .01));
    expect(maximum.width, lessThan(200));

    final fairy = tester.getRect(
      find.byKey(const ValueKey('profile-inlay:featherySteps')),
    );
    final ranks = tester.getRect(
      find.byKey(const ValueKey('profile-afk-rank-track')),
    );
    expect(fairy.size, const Size(52, 52));
    expect(fairy.left, weight.left);
    expect(fairy.center.dy, closeTo(ranks.center.dy, .01));
    expect(ranks.left, maximum.left);

    final inputs = tester.getRect(
      find.byKey(const ValueKey('profile-afk-inputs')),
    );
    final summary = tester.getRect(
      find.byKey(const ValueKey('profile-afk-result-frame')),
    );
    expect(summary.left, greaterThan(inputs.right));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'weight results retain the existing profile maths and type roles',
    (tester) async {
      await _pump(tester, width: 1000);
      final room = tester.widget<Text>(
        find.byKey(const ValueKey('profile-afk-room-value')),
      );
      final limit = tester.widget<Text>(
        find.byKey(const ValueKey('profile-afk-limit-value')),
      );
      expect(room.textSpan!.toPlainText(), '1.850 LT');
      expect(limit.textSpan!.toPlainText(), '1.975 LT');
      expect(room.style!.fontSize, 26);
      expect(room.style!.fontWeight, FontWeight.w700);
      expect(limit.style!.fontSize, 14);
      expect(
        tester.widget<Text>(find.text('Room for ingredients')).style!.fontSize,
        12,
      );
      expect(
        tester.widget<Text>(find.text('Feathery Steps')).style!.fontSize,
        15,
      );
      expect(find.text('Character weight'), findsNothing);
      expect(find.text('Done'), findsNothing);
      expect(find.byKey(const ValueKey('data-afk-load-toggle')), findsNothing);
    },
  );

  testWidgets('callbacks retain every rank and unmodified locale input', (
    tester,
  ) async {
    final ranks = <int>[];
    final commits = <String>[];
    await _pump(tester, width: 1000, onRank: ranks.add, onMaximum: commits.add);
    for (var rank = 0; rank <= 5; rank++) {
      await tester.tap(find.byKey(ValueKey('data-afk-feathery-steps:$rank')));
      await tester.pumpAndSettle();
    }
    expect(ranks, [0, 1, 2, 3, 4, 5]);

    final maximum = find.descendant(
      of: find.byKey(const ValueKey('data-afk-maximum-weight')),
      matching: find.byType(TextField),
    );
    await tester.enterText(maximum, '123.456,75');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    expect(commits, ['123.456,75']);
    expect(tester.widget<TextField>(maximum).maxLength, isNull);
  });

  testWidgets('unconfigured weight keeps existing useful empty results', (
    tester,
  ) async {
    await _pump(tester, width: 500, profile: AfkWeightProfile());
    expect(find.text('Enter Max LT'), findsOneWidget);
    expect(find.text('Not calculated'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('selected Ledger rank inherits its button state foreground', (
    tester,
  ) async {
    await _pump(
      tester,
      width: 1000,
      spec: RetainedThemeRegistry.illuminatedLedger,
    );
    final rank = find.descendant(
      of: find.byKey(const ValueKey('data-afk-feathery-steps:5')),
      matching: find.text('V'),
    );
    final label = tester.widget<Text>(rank);
    final inherited = DefaultTextStyle.of(tester.element(rank)).style;
    expect(label.style!.inherit, isTrue);
    expect(label.style!.color, isNull);
    expect(label.style!.fontFamily, isNull);
    expect(label.style!.fontSize, 12);
    expect(label.style!.fontWeight, FontWeight.w600);
    expect(label.style!.height, 16 / 12);
    expect(inherited.merge(label.style).color, inherited.color);
    expect(
      inherited.color,
      isNot(RetainedThemeRegistry.illuminatedLedger.palette.text),
    );
    expect(inherited.color!.computeLuminance(), greaterThan(.7));
    expect(
      tester
          .widget<AppButton>(
            find.byKey(const ValueKey('data-afk-feathery-steps:5')),
          )
          .selected,
      isTrue,
    );
  });

  for (final spec in [
    RetainedThemeRegistry.standard,
    RetainedThemeRegistry.illuminatedLedger,
    RetainedThemeRegistry.sakuraNightGarden,
  ]) {
    for (final scenario in <(double, double)>[
      (320, 1),
      (500, 1),
      (500, 1.5),
      (500, 2),
    ]) {
      testWidgets(
        'AFK inlays remain bounded in ${spec.id} at ${scenario.$1}px/${scenario.$2}x',
        (tester) async {
          await _pump(
            tester,
            width: scenario.$1,
            textScale: scenario.$2,
            spec: spec,
          );
          final bounds = tester.getRect(
            find.byKey(const ValueKey('profile-afk-controls')),
          );
          for (final suffix in ['maximum', 'current', 'free']) {
            final track = tester.getRect(
              find.byKey(ValueKey('profile-afk-control-track:$suffix')),
            );
            expect(track.left, greaterThanOrEqualTo(bounds.left));
            expect(track.right, lessThanOrEqualTo(bounds.right + .01));
            expect(track.height, greaterThanOrEqualTo(52));
          }
          final summary = tester.getRect(
            find.byKey(const ValueKey('profile-afk-result-frame')),
          );
          final ranks = tester.getRect(
            find.byKey(const ValueKey('profile-afk-rank-track')),
          );
          expect(summary.top, greaterThan(ranks.bottom));
          expect(summary.left, bounds.left);
          expect(summary.right, closeTo(bounds.right, .01));
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}

Future<void> _pump(
  WidgetTester tester, {
  required double width,
  double textScale = 1,
  ThemeSpec spec = RetainedThemeRegistry.sakuraNightGarden,
  AfkWeightProfile? profile,
  ValueChanged<int>? onRank,
  ValueChanged<String>? onMaximum,
}) async {
  tester.view.physicalSize = Size(width + 40, 1400);
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  await tester.pumpWidget(
    MaterialApp(
      theme: spec.materialTheme(),
      home: ThemeSpecScope(
        spec: spec,
        child: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ProfileAfkControls(
              profile:
                  profile ??
                  AfkWeightProfile(
                    maximumWeightLt: 1600,
                    currentCarriedWeightLt: 125,
                    safetyBufferLt: 25,
                    featheryStepsLevel: 5,
                  ),
              onMaximumWeightCommitted: onMaximum ?? (_) {},
              onCurrentWeightCommitted: (_) {},
              onSafetyBufferCommitted: (_) {},
              onFeatheryStepsChanged: onRank ?? (_) {},
              fieldBuilder:
                  ({
                    required Key fieldKey,
                    required String label,
                    required String value,
                    required ValueChanged<String> onCommit,
                  }) => Builder(
                    builder: (context) => TextFormField(
                      key: fieldKey,
                      initialValue: value,
                      onFieldSubmitted: onCommit,
                      style: ProfileTypography.input(context),
                      decoration: InputDecoration(
                        isDense: true,
                        contentPadding: const EdgeInsets.all(10),
                        suffixText: 'LT',
                        suffixStyle: ProfileTypography.label(context),
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
