import 'dart:ui' as ui;

import 'package:bdo_craft_planner_flutter/visual/illuminated_ledger/ledger_ornament_painters.dart';
import 'package:bdo_craft_planner_flutter/visual/visual.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('atmosphere styles retain distinct authored geometry', () async {
    final images = <String, Uint8List>{};
    for (final style in const <String>[
      'fumes',
      'stars',
      'embers',
      'snow',
      'leaves',
      'petals',
      'bubbles',
      'fireflies',
    ]) {
      images[style] = await _paintAtmosphere(style);
    }

    expect(images.values.map(_signature).toSet(), hasLength(images.length));
    expect(listEquals(images['snow'], images['stars']), isFalse);
    expect(listEquals(images['leaves'], images['petals']), isFalse);
    final firefly = images['fireflies']!;
    expect(
      _containsPixel(
        firefly,
        (r, g, b, a) => a > 24 && r < 75 && g < 75 && b < 75,
      ),
      isTrue,
      reason: 'fireflies retain a dark body rather than a luminous dot',
    );
    expect(
      _containsPixel(
        firefly,
        (r, g, b, a) => a > 24 && r > 80 && g > 80 && b > 65 && b * 10 > g * 6,
      ),
      isTrue,
      reason: 'fireflies retain pale wings and a warm abdomen core',
    );
  });

  test('button effects paint distinct multi-layer treatments', () async {
    final images = <String, Uint8List>{};
    for (final effect in const <String>[
      'glow',
      'orbit',
      'sweep',
      'sigil',
      'embers',
      'frost',
      'fireflies',
    ]) {
      images[effect] = await _paintButtonEffect(effect);
    }

    expect(images.values.map(_signature).toSet(), hasLength(images.length));
    final fireflies = images['fireflies']!;
    expect(
      _containsPixel(
        fireflies,
        (r, g, b, a) => a > 18 && r < 75 && g < 75 && b < 75,
      ),
      isTrue,
    );
    expect(
      _containsPixel(
        fireflies,
        (r, g, b, a) => a > 18 && r > 70 && g > 70 && b > 55 && b * 10 > g * 6,
      ),
      isTrue,
    );
  });

  testWidgets(
    'Ledger brand, clean active row, and wax completion are authored',
    (tester) async {
      var completions = 0;
      const spec = RetainedThemeRegistry.illuminatedLedger;
      await tester.pumpWidget(
        MaterialApp(
          theme: spec.materialTheme(),
          home: ThemeSpecScope(
            spec: spec,
            child: Scaffold(
              body: Column(
                children: <Widget>[
                  const SizedBox(width: 228, child: AppBrandLockup()),
                  SizedBox(
                    width: 210,
                    height: 48,
                    child: AppButton.label(
                      'Planner',
                      role: AppButtonRole.sidebarNavigation,
                      selected: true,
                      onPressed: () {},
                    ),
                  ),
                  AppCompletionControl(
                    completed: false,
                    semanticLabel: 'Done with Purified Water',
                    onPressed: () => completions++,
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      final dropCap = tester.widget<Image>(
        find.byKey(AppBrandLockup.ledgerDropCapKey),
      );
      expect(dropCap.image, isA<AssetImage>());
      expect(
        (dropCap.image as AssetImage).assetName,
        IlluminatedLedgerSpec.dropCapAssetPath,
      );
      final customPaints = tester.widgetList<CustomPaint>(
        find.byType(CustomPaint),
      );
      expect(
        customPaints
            .map((paint) => paint.foregroundPainter)
            .whereType<LedgerNavigationRibbonPainter>(),
        isEmpty,
      );
      expect(
        customPaints
            .map((paint) => paint.painter)
            .whereType<LedgerWaxSealPainter>(),
        isNotEmpty,
      );

      await tester.tap(find.bySemanticsLabel('Done with Purified Water'));
      expect(completions, 1);
    },
  );

  test('Ledger adapts dialog, tooltip, and menu families', () {
    final spec = RetainedThemeRegistry.illuminatedLedger;
    final theme = spec.materialTheme();
    expect(theme.dialogTheme.barrierColor, spec.materials.modalScrim);
    expect(theme.dialogTheme.backgroundColor, Colors.transparent);
    expect(theme.tooltipTheme.decoration, isA<BoxDecoration>());
    expect(theme.popupMenuTheme.shape, isA<RoundedRectangleBorder>());
    expect(
      theme.dropdownMenuTheme.menuStyle!.backgroundColor!.resolve(
        <WidgetState>{},
      ),
      spec.palette.surfaceRaised,
    );
    expect(theme.menuTheme.style, isNotNull);
  });

  test('retained themes keep scrollbar chrome hidden', () {
    for (final spec in RetainedThemeRegistry.themes) {
      final scrollbar = spec.materialTheme().scrollbarTheme;
      expect(
        scrollbar.thumbVisibility!.resolve(<WidgetState>{}),
        false,
        reason: spec.displayName,
      );
      expect(
        scrollbar.trackVisibility!.resolve(<WidgetState>{}),
        false,
        reason: spec.displayName,
      );
      expect(scrollbar.interactive, false, reason: spec.displayName);
      expect(
        scrollbar.thickness!.resolve(<WidgetState>{}),
        0,
        reason: spec.displayName,
      );
      expect(
        scrollbar.thumbColor!.resolve(<WidgetState>{}),
        Colors.transparent,
        reason: spec.displayName,
      );
    }
  });
}

Future<Uint8List> _paintAtmosphere(String style) async {
  final recorder = ui.PictureRecorder();
  StandardAtmospherePainter(
    settings: AtmosphereVisualSettings(
      style: style,
      density: .18,
      opacity: .92,
      minimumSize: 1.15,
      maximumSize: 1.7,
      blur: .08,
      speed: .55,
      strength: .65,
      hue: style == 'embers' ? 28 : 88,
      rainbow: false,
      neon: false,
      animated: true,
    ),
    progress: .37,
  ).paint(Canvas(recorder), const Size(180, 120));
  return _pictureBytes(recorder.endRecording(), 180, 120);
}

Future<Uint8List> _paintButtonEffect(String effect) async {
  final recorder = ui.PictureRecorder();
  ButtonEffectPainter(
    settings: ButtonEffectVisualSettings(
      effect: effect,
      intensity: .82,
      speed: .64,
      blur: .18,
      activeOnly: false,
      hue: effect == 'embers' ? 28 : 88,
      rainbow: false,
      neon: false,
    ),
    progress: .37,
    active: true,
  ).paint(Canvas(recorder), const Size(180, 48));
  return _pictureBytes(recorder.endRecording(), 180, 48);
}

Future<Uint8List> _pictureBytes(
  ui.Picture picture,
  int width,
  int height,
) async {
  final image = await picture.toImage(width, height);
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  final bytes = data!.buffer.asUint8List();
  image.dispose();
  picture.dispose();
  return bytes;
}

int _signature(Uint8List bytes) {
  var hash = 0x811C9DC5;
  for (final byte in bytes) {
    hash = ((hash ^ byte) * 0x01000193) & 0xFFFFFFFF;
  }
  return hash;
}

bool _containsPixel(Uint8List bytes, bool Function(int, int, int, int) match) {
  for (var index = 0; index < bytes.length; index += 4) {
    if (match(
      bytes[index],
      bytes[index + 1],
      bytes[index + 2],
      bytes[index + 3],
    )) {
      return true;
    }
  }
  return false;
}
