import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/features/shell/shell.dart';
import 'package:bdo_craft_planner_flutter/visual/components/app_button.dart';
import 'package:bdo_craft_planner_flutter/visual/components/button_effect_scope.dart';
import 'package:bdo_craft_planner_flutter/visual/foundations/theme_spec.dart';
import 'package:bdo_craft_planner_flutter/visual/standard/standard_spec.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _allTabsEffect = ButtonEffectVisualSettings(
  effect: 'glow',
  intensity: .6,
  speed: .5,
  blur: .1,
  activeOnly: false,
  hue: 158,
  rainbow: false,
  neon: false,
);

const _selectedTabsEffect = ButtonEffectVisualSettings(
  effect: 'sweep',
  intensity: 1,
  speed: .5,
  blur: .1,
  activeOnly: true,
  hue: 158,
  rainbow: false,
  neon: false,
);

void main() {
  testWidgets(
    'workstation clicks update selection without leaving a visible name',
    (tester) async {
      final semantics = tester.ensureSemantics();
      await _setWindowSize(tester, const Size(1500, 940));
      await tester.pumpWidget(
        const _WorkstationHarness(settings: _allTabsEffect),
      );

      final selector = find.byKey(ShellActionKeys.modeSelector);
      expect(
        find.descendant(of: selector, matching: find.byType(Tooltip)),
        findsNothing,
      );
      expect(find.bySemanticsLabel('Switch to Cooking'), findsOneWidget);

      await tester.tap(find.byKey(ShellActionKeys.mode(CraftMode.cooking)));
      await tester.pump();

      expect(
        tester.widget<Semantics>(selector).properties.value,
        CraftMode.cooking.label,
      );
      expect(
        tester
            .widget<AppButton>(
              find.byKey(ShellActionKeys.mode(CraftMode.cooking)),
            )
            .selected,
        isTrue,
      );
      expect(
        tester
            .widget<AppButton>(
              find.byKey(ShellActionKeys.mode(CraftMode.alchemy)),
            )
            .selected,
        isFalse,
      );

      await tester.pump(const Duration(seconds: 5));
      expect(find.text('Cooking'), findsNothing);
      expect(find.bySemanticsLabel('Switch to Cooking'), findsOneWidget);
      semantics.dispose();
    },
  );

  testWidgets(
    'default workstation selection is subtle when effects apply to all tabs',
    (tester) async {
      for (final viewport in <Size>[
        const Size(1500, 940),
        const Size(1200, 752),
      ]) {
        await _setWindowSize(tester, viewport);
        await tester.pumpWidget(
          const _WorkstationHarness(settings: _allTabsEffect),
        );

        final selected = _decorationFor(tester, CraftMode.alchemy);
        final inactive = _decorationFor(tester, CraftMode.cooking);
        final selectedAlpha = _gradientAlpha(selected);
        final inactiveAlpha = _gradientAlpha(inactive);

        expect(selectedAlpha, <int>[82, 36, 28]);
        expect(inactiveAlpha, <int>[66, 24, 18]);
        expect(
          selectedAlpha.first - inactiveAlpha.first,
          lessThanOrEqualTo(20),
          reason: '$viewport should retain only a quiet default lift',
        );

        final selectedBorder = selected.border! as Border;
        final inactiveBorder = inactive.border! as Border;
        expect(_alpha(selectedBorder.top.color), 117);
        expect(_alpha(inactiveBorder.top.color), 82);
      }
    },
  );

  testWidgets('Classic ignores saved effects and keeps a quiet selected edge', (
    tester,
  ) async {
    await _setWindowSize(tester, const Size(1500, 940));
    await tester.pumpWidget(
      const _WorkstationHarness(settings: _selectedTabsEffect),
    );

    final selected = _decorationFor(tester, CraftMode.alchemy);
    final inactive = _decorationFor(tester, CraftMode.cooking);
    final selectedAlpha = _gradientAlpha(selected);

    expect(selectedAlpha, <int>[82, 36, 28]);
    expect(_gradientAlpha(inactive), <int>[66, 24, 18]);
    expect(_alpha((selected.border! as Border).top.color), 117);
    expect(_alpha((inactive.border! as Border).top.color), 82);

    expect(
      find.descendant(
        of: find.byKey(ShellActionKeys.modeSelector),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is CustomPaint &&
              widget.foregroundPainter is ButtonEffectPainter,
        ),
      ),
      findsNothing,
    );
  });
}

class _WorkstationHarness extends StatefulWidget {
  const _WorkstationHarness({required this.settings});

  final ButtonEffectVisualSettings settings;

  @override
  State<_WorkstationHarness> createState() => _WorkstationHarnessState();
}

class _WorkstationHarnessState extends State<_WorkstationHarness> {
  CraftMode mode = CraftMode.alchemy;

  @override
  Widget build(BuildContext context) => MaterialApp(
    theme: StandardSpec.theme.materialTheme(),
    home: ThemeSpecScope(
      spec: StandardSpec.theme,
      child: ButtonEffectHost(
        settings: widget.settings,
        reduceMotion: true,
        child: WorkspaceShell(
          mode: mode,
          destination: ShellDestination.planner,
          onModeChanged: (value) => setState(() => mode = value),
          onDestinationChanged: (_) {},
          child: const SizedBox.expand(),
        ),
      ),
    ),
  );
}

BoxDecoration _decorationFor(WidgetTester tester, CraftMode mode) {
  final material = find.descendant(
    of: find.byKey(ShellActionKeys.mode(mode)),
    matching: find.byKey(AppButton.materialKey),
  );
  return tester.widget<AnimatedContainer>(material).decoration!
      as BoxDecoration;
}

List<int> _gradientAlpha(BoxDecoration decoration) =>
    (decoration.gradient! as LinearGradient).colors.map(_alpha).toList();

int _alpha(Color color) => color.toARGB32() >>> 24;

Future<void> _setWindowSize(WidgetTester tester, Size size) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
}
