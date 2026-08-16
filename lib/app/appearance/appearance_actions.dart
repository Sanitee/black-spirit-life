import '../../domain/state/planner_state.dart';
import '../../domain/state/state_copy.dart';
import '../../visual/foundations/theme_registry.dart';
import '../../visual/illuminated_ledger/ledger_spec.dart';
import '../../visual/sakura_night_garden/sakura_spec.dart';
import '../../visual/standard/standard_spec.dart';

abstract final class AppearanceActions {
  static const particleSwatches = <double>[18, 38, 88, 146, 188, 218, 264, 318];
  static const visibleParticleStyles = <String>{
    'embers',
    'snow',
    'bubbles',
    'fireflies',
    'petals',
  };
  static const buttonEffects = <String>{
    'quiet',
    'glow',
    'orbit',
    'sweep',
    'embers',
    'frost',
    'fireflies',
  };

  static PlannerState selectSharedBackground(
    PlannerState document,
    String backgroundId,
  ) {
    if (!RetainedThemeRegistry.isKnownBackground(backgroundId)) return document;
    ModeState apply(ModeState mode) => mode.copyWith(
      appearance: applySceneDefaults(mode.appearance, backgroundId),
    );
    return document.copyWith(
      alchemy: apply(document.alchemy),
      cooking: apply(document.cooking),
      processing: apply(document.processing),
    );
  }

  static AppearanceSettings applySceneDefaults(
    AppearanceSettings source,
    String backgroundId,
  ) {
    final particleStyle = _sceneParticleStyle(backgroundId);
    final accentHue = _sceneAccentHue(backgroundId);
    return copyAppearance(
      source,
      background: backgroundId,
      particleStyle: particleStyle,
      accentHue: accentHue,
      particleHue: !source.particleCustomColor && !source.particleRainbow
          ? accentHue
          : source.particleHue,
      buttonEffectHue:
          !source.buttonEffectCustomColor && !source.buttonEffectRainbow
          ? accentHue
          : source.buttonEffectHue,
    );
  }

  static AppearanceSettings transition(
    AppearanceSettings source,
    String value,
  ) {
    final normalized = value.trim().toLowerCase();
    if (normalized == 'off') {
      return copyAppearance(source, tabFade: false, tabTransition: 'off');
    }
    final selected = const {'fade', 'slide', 'lift'}.contains(normalized)
        ? normalized
        : 'slide';
    return copyAppearance(source, tabFade: true, tabTransition: selected);
  }

  static AppearanceSettings transitionSpeed(
    AppearanceSettings source,
    String value,
  ) {
    final normalized = value.trim().toLowerCase();
    final selected = const {'slow', 'normal', 'fast'}.contains(normalized)
        ? normalized
        : 'normal';
    return copyAppearance(source, tabTransitionSpeed: selected);
  }

  static AppearanceSettings particleStyle(
    AppearanceSettings source,
    String value,
  ) => visibleParticleStyles.contains(value)
      ? copyAppearance(source, particleStyle: value)
      : source;

  static AppearanceSettings particleHue(
    AppearanceSettings source,
    double hue,
  ) => copyAppearance(
    source,
    particleHue: _hue(hue),
    particleCustomColor: true,
    particleRainbow: false,
  );

  static AppearanceSettings particleDefault(AppearanceSettings source) =>
      copyAppearance(
        source,
        particleHue: source.accentHue,
        particleCustomColor: false,
        particleRainbow: false,
        particleNeon: false,
      );

  static AppearanceSettings particleRainbow(
    AppearanceSettings source,
    bool value,
  ) => copyAppearance(
    source,
    particleRainbow: value,
    particleCustomColor: value ? false : source.particleCustomColor,
    particleHue: value ? source.accentHue : source.particleHue,
  );

  static AppearanceSettings particleMinimum(
    AppearanceSettings source,
    double value,
  ) {
    final minimum = value.clamp(.45, 2.2);
    return copyAppearance(
      source,
      particleMinSize: minimum,
      particleMaxSize: source.particleMaxSize < minimum
          ? minimum
          : source.particleMaxSize,
    );
  }

  static AppearanceSettings particleMaximum(
    AppearanceSettings source,
    double value,
  ) {
    final maximum = value.clamp(.45, 2.2);
    return copyAppearance(
      source,
      particleMaxSize: maximum,
      particleMinSize: source.particleMinSize > maximum
          ? maximum
          : source.particleMinSize,
    );
  }

  static AppearanceSettings buttonEffect(
    AppearanceSettings source,
    String value,
  ) => buttonEffects.contains(value)
      ? copyAppearance(source, buttonEffect: value)
      : source;

  static AppearanceSettings buttonHue(AppearanceSettings source, double hue) =>
      copyAppearance(
        source,
        buttonEffectHue: _hue(hue),
        buttonEffectCustomColor: true,
        buttonEffectRainbow: false,
      );

  static AppearanceSettings buttonDefault(AppearanceSettings source) =>
      copyAppearance(
        source,
        buttonEffectHue: source.accentHue,
        buttonEffectCustomColor: false,
        buttonEffectRainbow: false,
        buttonEffectNeon: false,
      );

  static AppearanceSettings buttonRainbow(
    AppearanceSettings source,
    bool value,
  ) => copyAppearance(
    source,
    buttonEffectRainbow: value,
    buttonEffectCustomColor: value ? false : source.buttonEffectCustomColor,
    buttonEffectHue: value ? source.accentHue : source.buttonEffectHue,
  );

  static AppearanceSettings copyAppearance(
    AppearanceSettings source, {
    String? background,
    bool? liveBackdrop,
    double? motionIntensity,
    double? motionSpeed,
    String? particleStyle,
    double? particleDensity,
    double? particleOpacity,
    double? particleMinSize,
    double? particleMaxSize,
    double? particleSize,
    double? particleBlur,
    bool? particleCustomColor,
    double? particleHue,
    bool? particleRainbow,
    bool? particleNeon,
    String? buttonEffect,
    double? buttonEffectIntensity,
    double? buttonEffectSpeed,
    double? buttonEffectBlur,
    bool? buttonEffectActiveOnly,
    bool? buttonEffectCustomColor,
    double? buttonEffectHue,
    bool? buttonEffectRainbow,
    bool? buttonEffectNeon,
    double? accentHue,
    bool? rainbow,
    bool? neon,
    double? backdropBlur,
    bool? tabFade,
    String? tabTransition,
    String? tabTransitionSpeed,
  }) => AppearanceSettings(
    background: background ?? source.background,
    liveBackdrop: liveBackdrop ?? source.liveBackdrop,
    motionIntensity: _unit(motionIntensity ?? source.motionIntensity),
    motionSpeed: _unit(motionSpeed ?? source.motionSpeed),
    particleStyle: particleStyle ?? source.particleStyle,
    particleDensity: _unit(particleDensity ?? source.particleDensity),
    particleOpacity: _unit(particleOpacity ?? source.particleOpacity),
    particleMinSize: particleMinSize ?? source.particleMinSize,
    particleMaxSize: particleMaxSize ?? source.particleMaxSize,
    particleSize: particleSize ?? source.particleSize,
    particleBlur: _unit(particleBlur ?? source.particleBlur),
    particleCustomColor: particleCustomColor ?? source.particleCustomColor,
    particleHue: _hue(particleHue ?? source.particleHue),
    particleRainbow: particleRainbow ?? source.particleRainbow,
    particleNeon: particleNeon ?? source.particleNeon,
    buttonEffect: buttonEffect ?? source.buttonEffect,
    buttonEffectIntensity: _unit(
      buttonEffectIntensity ?? source.buttonEffectIntensity,
    ),
    buttonEffectSpeed: _unit(buttonEffectSpeed ?? source.buttonEffectSpeed),
    buttonEffectBlur: _unit(buttonEffectBlur ?? source.buttonEffectBlur),
    buttonEffectActiveOnly:
        buttonEffectActiveOnly ?? source.buttonEffectActiveOnly,
    buttonEffectCustomColor:
        buttonEffectCustomColor ?? source.buttonEffectCustomColor,
    buttonEffectHue: _hue(buttonEffectHue ?? source.buttonEffectHue),
    buttonEffectRainbow: buttonEffectRainbow ?? source.buttonEffectRainbow,
    buttonEffectNeon: buttonEffectNeon ?? source.buttonEffectNeon,
    accentHue: _hue(accentHue ?? source.accentHue),
    rainbow: rainbow ?? source.rainbow,
    neon: neon ?? source.neon,
    backdropBlur: _unit(backdropBlur ?? source.backdropBlur),
    tabFade: tabFade ?? source.tabFade,
    tabTransition: tabTransition ?? source.tabTransition,
    tabTransitionSpeed: tabTransitionSpeed ?? source.tabTransitionSpeed,
    presets: source.presets,
    extensions: source.extensions,
  );
}

String _sceneParticleStyle(String backgroundId) {
  if (backgroundId == IlluminatedLedgerSpec.backgroundId) return 'petals';
  if (backgroundId == SakuraNightGardenSpec.backgroundId) return 'petals';
  final scene = StandardSpec.scenes[backgroundId];
  if (scene != null) return scene.defaultParticleId;
  return switch (backgroundId) {
    'plain-amber' || 'plain-rose' => 'embers',
    'plain-violet' => 'stars',
    'plain-verdant' => 'fireflies',
    'plain-cobalt' => 'bubbles',
    _ => 'petals',
  };
}

double _sceneAccentHue(String backgroundId) {
  if (backgroundId == IlluminatedLedgerSpec.backgroundId) return 211;
  if (backgroundId == SakuraNightGardenSpec.backgroundId) return 341;
  final scene = StandardSpec.scenes[backgroundId];
  if (scene != null) return scene.accentHue;
  return switch (backgroundId) {
    'plain-amber' => 38,
    'plain-violet' => 228,
    'plain-verdant' => 142,
    'plain-cobalt' => 194,
    'plain-rose' => 344,
    _ => 158,
  };
}

double _unit(double value) => value.clamp(0, 1).toDouble();
double _hue(double value) => value.isFinite ? value % 360 : 0;
