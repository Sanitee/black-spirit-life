import 'package:bdo_craft_planner_flutter/visual/foundations/theme_registry.dart';
import 'package:bdo_craft_planner_flutter/visual/foundations/theme_spec.dart';
import 'package:bdo_craft_planner_flutter/visual/illuminated_ledger/ledger_spec.dart';
import 'package:bdo_craft_planner_flutter/visual/sakura_night_garden/sakura_spec.dart';
import 'package:bdo_craft_planner_flutter/visual/standard/standard_spec.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('retained theme registry', () {
    test('resolves the manuscript identity and all Standard backgrounds', () {
      expect(
        RetainedThemeRegistry.resolve(
          backgroundId: IlluminatedLedgerSpec.backgroundId,
        ),
        same(RetainedThemeRegistry.illuminatedLedger),
      );

      for (final id in <String>{
        ...StandardSpec.scenes.keys,
        ...StandardSpec.plainBackgrounds.keys,
      }) {
        expect(
          RetainedThemeRegistry.resolve(backgroundId: id),
          same(RetainedThemeRegistry.standard),
        );
        expect(RetainedThemeRegistry.isKnownBackground(id), isTrue);
      }
      expect(
        RetainedThemeRegistry.resolve(backgroundId: 'unrecognized'),
        same(RetainedThemeRegistry.sakuraNightGarden),
      );
      expect(RetainedThemeRegistry.isKnownBackground('unrecognized'), isFalse);
    });

    test('publishes complete immutable scene and plain registries', () {
      expect(StandardSpec.scenes, hasLength(8));
      expect(StandardSpec.plainBackgrounds, hasLength(6));
      expect(
        StandardSpec.scenes['greenhouse']!.assetPath,
        'assets/scenes/backdrop-alchemy-greenhouse.png',
      );
      expect(StandardSpec.scenes['orrery']!.defaultParticleId, 'stars');
      expect(StandardSpec.scenes['hearth']!.accentHue, 28);
      expect(
        StandardSpec.plainBackgrounds['plain-dark']!.left,
        const Color.fromARGB(214, 7, 14, 18),
      );

      expect(
        () => StandardSpec.scenes['new-id'] =
            StandardSpec.scenes[StandardSpec.defaultBackgroundId]!,
        throwsUnsupportedError,
      );
      expect(
        () => RetainedThemeRegistry.themes.add(StandardSpec.theme),
        throwsUnsupportedError,
      );
    });

    test('keeps component geometry and material capabilities theme-owned', () {
      const standard = StandardSpec.theme;
      const ledger = IlluminatedLedgerSpec.theme;
      const sakura = SakuraNightGardenSpec.theme;

      expect(standard.family, RetainedVisualFamily.standard);
      expect(ledger.family, RetainedVisualFamily.illuminatedLedger);
      expect(sakura.family, RetainedVisualFamily.sakuraNightGarden);
      expect(standard.geometry.panelRadius, 11);
      expect(ledger.geometry.panelRadius, 2);
      expect(sakura.geometry.panelRadius, 6);
      expect(standard.motion.supportsAtmosphere, isTrue);
      expect(ledger.motion.supportsAtmosphere, isFalse);
      expect(sakura.motion.supportsAtmosphere, isFalse);
      expect(standard.motion.supportsButtonEffects, isFalse);
      expect(ledger.motion.supportsButtonEffects, isFalse);
      expect(sakura.motion.supportsButtonEffects, isFalse);
      expect(standard.motion.supportsOrnament, isFalse);
      expect(ledger.motion.supportsOrnament, isTrue);
      expect(sakura.motion.supportsOrnament, isTrue);
      expect(standard.palette.primary, const Color(0xFF2F9E7A));
      expect(ledger.palette.primary, const Color(0xFF123D69));
      expect(sakura.palette.primary, SakuraNightGardenSpec.dustySakura);
    });

    test('registers Sakura as its own dense full-interface family', () {
      const sakura = SakuraNightGardenSpec.theme;

      expect(RetainedThemeRegistry.themes, hasLength(3));
      expect(
        RetainedThemeRegistry.themes,
        orderedEquals(const <ThemeSpec>[
          RetainedThemeRegistry.sakuraNightGarden,
          RetainedThemeRegistry.illuminatedLedger,
          RetainedThemeRegistry.standard,
        ]),
      );
      expect(
        RetainedThemeRegistry.byId('unrecognized'),
        same(RetainedThemeRegistry.sakuraNightGarden),
      );
      expect(
        RetainedThemeRegistry.resolve(
          backgroundId: SakuraNightGardenSpec.backgroundId,
        ),
        same(RetainedThemeRegistry.sakuraNightGarden),
      );
      expect(
        RetainedThemeRegistry.byId(SakuraNightGardenSpec.backgroundId),
        same(RetainedThemeRegistry.sakuraNightGarden),
      );
      expect(
        RetainedThemeRegistry.isKnownBackground(
          SakuraNightGardenSpec.backgroundId,
        ),
        isTrue,
      );
      expect(sakura.id, 'sakura-night-garden');
      expect(sakura.displayName, 'Sakura Night Garden');
      expect(sakura.layoutProfile, ThemeLayoutProfile.denseSplitWorkspace);
      expect(sakura.usesDenseSplitLayout, isTrue);
      expect(sakura.isSakuraNightGarden, isTrue);
      expect(sakura.isStandard, isFalse);
      expect(sakura.isIlluminatedLedger, isFalse);
      expect(sakura.geometry.titleStripHeight, 40);
      expect(
        sakura.geometry.workspacePadding,
        const EdgeInsets.fromLTRB(20, 20, 24, 18),
      );
      expect(sakura.geometry.sidebarWidth, 226);
      expect(sakura.geometry.contentGap, 14);
      expect(sakura.motion.supportsButtonEffects, isFalse);
    });

    test('resolves Standard fallback and exact material helpers', () {
      final fallback = StandardSpec.resolveBackdrop('unrecognized');
      expect(fallback.family, StandardBackdropFamily.atmospheric);
      expect(fallback.id, StandardSpec.defaultBackgroundId);

      final glass = StandardSpec.glassGradient(topAlpha: 140, bottomAlpha: 170);
      expect(glass.colors, const <Color>[
        Color.fromARGB(140, 16, 48, 36),
        Color.fromARGB(102, 5, 19, 15),
        Color.fromARGB(170, 1, 6, 7),
      ]);
      expect(
        StandardSpec.plainBackgrounds['plain-rose']!.gradient.stops,
        const <double>[0, 0.55, 1],
      );

      final defaultGlass = StandardSpec.glassGradient();
      expect(defaultGlass.begin, Alignment.topLeft);
      expect(defaultGlass.end, Alignment.bottomRight);
      expect(defaultGlass.colors, const <Color>[
        Color.fromARGB(44, 16, 48, 36),
        Color.fromARGB(10, 5, 19, 15),
        Color.fromARGB(16, 1, 6, 7),
      ]);

      final accent = StandardSpec.accentGlass(
        158,
        topAlpha: 70,
        bottomAlpha: 22,
      );
      expect(accent.colors.map((color) => color.toARGB32() >>> 24), <int>[
        70,
        24,
        22,
      ]);
      expect(accent.stops, const <double>[0, .58, 1]);
      expect(
        StandardSpec.plannerCardFill('hearth', AppSurfaceTone.neutral),
        const Color.fromARGB(148, 58, 37, 23),
      );
      expect(
        StandardSpec.plannerCardFill('orrery', AppSurfaceTone.success),
        const Color.fromARGB(148, 26, 39, 61),
      );
      expect(
        StandardSpec.plannerCardBorder(AppSurfaceTone.danger),
        const Color(0x50A05C52),
      );
      expect(StandardSpec.titleStripGradient('orrery').colors, const <Color>[
        Color.fromARGB(224, 8, 22, 43),
        Color.fromARGB(182, 7, 18, 39),
        Color.fromARGB(212, 5, 12, 28),
      ]);
    });

    testWidgets('Standard visual scope exposes live scene material values', (
      tester,
    ) async {
      StandardVisualSettings? resolved;
      await tester.pumpWidget(
        StandardVisualScope(
          settings: const StandardVisualSettings(
            backgroundId: 'hearth',
            accentHue: 28,
            rainbow: true,
            neon: true,
          ),
          child: Builder(
            builder: (context) {
              resolved = context.standardVisual;
              return const SizedBox();
            },
          ),
        ),
      );

      expect(resolved!.backgroundId, 'hearth');
      expect(resolved!.accentHue, 28);
      expect(resolved!.rainbow, isTrue);
      expect(resolved!.neon, isTrue);
    });

    test('Standard visual settings notify only for material value changes', () {
      const first = StandardVisualSettings(
        backgroundId: 'hearth',
        accentHue: 28,
        rainbow: true,
        neon: true,
      );
      const equalCopy = StandardVisualSettings(
        backgroundId: 'hearth',
        accentHue: 28,
        rainbow: true,
        neon: true,
      );
      const changed = StandardVisualSettings(
        backgroundId: 'orrery',
        accentHue: 218,
        rainbow: true,
        neon: true,
      );

      expect(first, equalCopy);
      expect(first.hashCode, equalCopy.hashCode);
      expect(first, isNot(changed));

      const oldScope = StandardVisualScope(settings: first, child: SizedBox());
      const equalScope = StandardVisualScope(
        settings: equalCopy,
        child: SizedBox(),
      );
      const changedScope = StandardVisualScope(
        settings: changed,
        child: SizedBox(),
      );
      expect(equalScope.updateShouldNotify(oldScope), isFalse);
      expect(changedScope.updateShouldNotify(oldScope), isTrue);
    });
  });
}
