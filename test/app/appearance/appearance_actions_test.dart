import 'package:bdo_craft_planner_flutter/app/appearance/appearance_actions.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/domain/state/planner_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Sakura is the canonical appearance default for every mode', () {
    for (final mode in CraftMode.values) {
      final appearance = AppearanceSettings.defaultsFor(mode);
      expect(appearance.background, 'sakura-night-garden');
      expect(appearance.particleStyle, 'petals');
      expect(appearance.accentHue, 341);
    }
  });

  test('visible particle choices use Avalonia canonical IDs and order', () {
    expect(
      AppearanceActions.visibleParticleStyles,
      orderedEquals(const <String>[
        'embers',
        'snow',
        'bubbles',
        'fireflies',
        'petals',
      ]),
    );
    final source = AppearanceSettings.defaultsFor(CraftMode.alchemy);
    expect(
      AppearanceActions.particleStyle(source, 'petals').particleStyle,
      'petals',
    );
    expect(
      identical(AppearanceActions.particleStyle(source, 'leaves'), source),
      isTrue,
    );
  });

  test('shared retained backgrounds update every mode and scene defaults', () {
    final initial = _document();
    final ledger = AppearanceActions.selectSharedBackground(
      initial,
      'illuminated-ledger',
    );
    for (final mode in CraftMode.values) {
      expect(ledger.forMode(mode).appearance.background, 'illuminated-ledger');
      expect(ledger.forMode(mode).appearance.accentHue, 211);
    }

    final plain = AppearanceActions.selectSharedBackground(
      ledger,
      'plain-cobalt',
    );
    for (final mode in CraftMode.values) {
      expect(plain.forMode(mode).appearance.background, 'plain-cobalt');
      expect(plain.forMode(mode).appearance.particleStyle, 'bubbles');
      expect(plain.forMode(mode).appearance.accentHue, 194);
    }
  });

  test('Sakura applies to every mode and resets cleanly to Standard', () {
    final initial = _document();
    final sakura = AppearanceActions.selectSharedBackground(
      initial,
      'sakura-night-garden',
    );

    for (final mode in CraftMode.values) {
      final appearance = sakura.forMode(mode).appearance;
      expect(appearance.background, 'sakura-night-garden');
      expect(appearance.particleStyle, 'petals');
      expect(appearance.accentHue, 341);
      expect(appearance.particleHue, 341);
      expect(appearance.buttonEffectHue, 341);
    }

    final standard = AppearanceActions.selectSharedBackground(
      sakura,
      'greenhouse',
    );
    for (final mode in CraftMode.values) {
      final appearance = standard.forMode(mode).appearance;
      expect(appearance.background, 'greenhouse');
      expect(appearance.particleStyle, 'fumes');
      expect(appearance.accentHue, 158);
      expect(appearance.particleHue, 158);
      expect(appearance.buttonEffectHue, 158);
    }
  });

  test('excluded or unknown theme IDs cannot be selected', () {
    final initial = _document();
    expect(
      identical(
        AppearanceActions.selectSharedBackground(initial, 'abyssal-tideglass'),
        initial,
      ),
      isTrue,
    );
    expect(
      identical(
        AppearanceActions.selectSharedBackground(
          initial,
          'moonstone-astrarium',
        ),
        initial,
      ),
      isTrue,
    );
  });

  test('color modes synchronize defaults, rainbow, and custom hue', () {
    final source = AppearanceSettings.defaultsFor(CraftMode.alchemy);
    final custom = AppearanceActions.particleHue(source, 360);
    expect(custom.particleHue, 0);
    expect(custom.particleCustomColor, isTrue);
    expect(custom.particleRainbow, isFalse);

    final rainbow = AppearanceActions.particleRainbow(custom, true);
    expect(rainbow.particleCustomColor, isFalse);
    expect(rainbow.particleHue, source.accentHue);

    final reset = AppearanceActions.particleDefault(rainbow);
    expect(reset.particleRainbow, isFalse);
    expect(reset.particleNeon, isFalse);
    expect(reset.particleHue, reset.accentHue);
  });

  test('size and unit controls enforce their domains', () {
    final source = AppearanceSettings.defaultsFor(CraftMode.alchemy);
    final raised = AppearanceActions.particleMinimum(source, 2.2);
    expect(raised.particleMinSize, 2.2);
    expect(raised.particleMaxSize, 2.2);
    final lowered = AppearanceActions.particleMaximum(raised, .45);
    expect(lowered.particleMinSize, .45);
    expect(lowered.particleMaxSize, .45);
    expect(
      AppearanceActions.copyAppearance(source, backdropBlur: 4).backdropBlur,
      1,
    );
  });

  test('transition normalization keeps off distinct from animated choices', () {
    final source = AppearanceSettings.defaultsFor(CraftMode.alchemy);
    final off = AppearanceActions.transition(source, 'OFF');
    expect(off.tabFade, isFalse);
    expect(off.tabTransition, 'off');
    expect(off.tabTransitionSpeed, 'normal');
    final lift = AppearanceActions.transition(off, 'lift');
    expect(lift.tabFade, isTrue);
    expect(lift.tabTransition, 'lift');
    final slow = AppearanceActions.transitionSpeed(lift, ' SLOW ');
    expect(slow.tabTransition, 'lift');
    expect(slow.tabFade, isTrue);
    expect(slow.tabTransitionSpeed, 'slow');
    final normalized = AppearanceActions.transitionSpeed(off, 'unknown');
    expect(normalized.tabFade, isFalse);
    expect(normalized.tabTransition, 'off');
    expect(normalized.tabTransitionSpeed, 'normal');
  });
}

PlannerState _document() => PlannerState(
  applicationVersion: 'test',
  lastSuccessfulWriteUtc: DateTime.utc(2026),
  alchemy: _mode(CraftMode.alchemy),
  cooking: _mode(CraftMode.cooking),
  processing: _mode(CraftMode.processing),
  processingYields: const {'defaultYield': 2.5},
  marketTax: MarketTax(),
);

ModeState _mode(CraftMode mode) => ModeState(
  target: mode.label,
  bonusTarget: mode.label,
  market: MarketState(),
  appearance: AppearanceSettings.defaultsFor(mode),
);
