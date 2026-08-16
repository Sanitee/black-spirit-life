import 'package:bdo_craft_planner_flutter/visual/visual.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const settings = ButtonEffectVisualSettings(
    effect: 'glow',
    intensity: .6,
    speed: .5,
    blur: .1,
    activeOnly: false,
    hue: 158,
    rainbow: false,
    neon: false,
  );

  testWidgets('Classic ignores stored button effects', (tester) async {
    const spec = RetainedThemeRegistry.standard;
    const navigationKey = ValueKey<String>('effect-navigation');
    await tester.pumpWidget(
      MaterialApp(
        theme: spec.materialTheme(),
        home: ThemeSpecScope(
          spec: spec,
          child: ButtonEffectHost(
            settings: settings,
            reduceMotion: true,
            child: Column(
              children: <Widget>[
                SizedBox(
                  width: 240,
                  height: 52,
                  child: AppButton.label(
                    'Planner',
                    key: navigationKey,
                    role: AppButtonRole.sidebarNavigation,
                    selected: true,
                    onPressed: () {},
                  ),
                ),
                AppButton.label('Build', onPressed: () {}),
              ],
            ),
          ),
        ),
      ),
    );

    final effectPaints = find.descendant(
      of: find.byKey(navigationKey),
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is CustomPaint &&
            widget.foregroundPainter is ButtonEffectPainter,
      ),
    );
    final material = find.descendant(
      of: find.byKey(navigationKey),
      matching: find.byKey(AppButton.materialKey),
    );
    expect(effectPaints, findsNothing);
    expect(
      tester.getRect(material),
      tester.getRect(find.byKey(navigationKey)),
      reason: 'the material must own the complete button hit surface',
    );
  });

  test('active-only painter remains a stable no-op for inactive buttons', () {
    const activeOnly = ButtonEffectVisualSettings(
      effect: 'glow',
      intensity: 1,
      speed: 1,
      blur: 0,
      activeOnly: true,
      hue: 0,
      rainbow: false,
      neon: false,
    );
    const first = ButtonEffectPainter(
      settings: activeOnly,
      progress: 0,
      active: false,
    );
    const second = ButtonEffectPainter(
      settings: activeOnly,
      progress: .5,
      active: false,
    );
    expect(second.shouldRepaint(first), isTrue);
  });

  test('effect settings notify only for visual value changes', () {
    const equalCopy = ButtonEffectVisualSettings(
      effect: 'glow',
      intensity: .6,
      speed: .5,
      blur: .1,
      activeOnly: false,
      hue: 158,
      rainbow: false,
      neon: false,
    );
    const changed = ButtonEffectVisualSettings(
      effect: 'orbit',
      intensity: .6,
      speed: .5,
      blur: .1,
      activeOnly: false,
      hue: 158,
      rainbow: false,
      neon: false,
    );
    final clock = const AlwaysStoppedAnimation<double>(0);

    expect(settings, equalCopy);
    expect(settings.hashCode, equalCopy.hashCode);
    expect(settings, isNot(changed));

    final oldScope = ButtonEffectScope(
      settings: settings,
      clock: clock,
      child: const SizedBox(),
    );
    final equalScope = ButtonEffectScope(
      settings: equalCopy,
      clock: clock,
      child: const SizedBox(),
    );
    final changedScope = ButtonEffectScope(
      settings: changed,
      clock: clock,
      child: const SizedBox(),
    );
    expect(equalScope.updateShouldNotify(oldScope), isFalse);
    expect(changedScope.updateShouldNotify(oldScope), isTrue);
  });
}
