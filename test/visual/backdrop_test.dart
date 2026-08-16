import 'package:bdo_craft_planner_flutter/visual/components/retained_asset_image.dart';
import 'package:bdo_craft_planner_flutter/visual/illuminated_ledger/ledger_backdrop.dart';
import 'package:bdo_craft_planner_flutter/visual/illuminated_ledger/ledger_spec.dart';
import 'package:bdo_craft_planner_flutter/visual/standard/standard_backdrop.dart';
import 'package:bdo_craft_planner_flutter/visual/standard/standard_spec.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Standard scene selects its retained asset', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SizedBox(
          width: 800,
          height: 500,
          child: StandardBackdrop(backgroundId: 'orrery'),
        ),
      ),
    );

    final image = tester.widget<Image>(find.byKey(StandardBackdrop.imageKey));
    expect(image.image, isA<AssetImage>());
    expect(
      (image.image as AssetImage).assetName,
      'assets/scenes/backdrop-moon-orrery.png',
    );
    final tone = tester.widget<DecoratedBox>(
      find.byKey(StandardBackdrop.toneKey),
    );
    expect(
      (tone.decoration as BoxDecoration).gradient,
      StandardSpec.backdropTone,
    );
    final backgroundStack = tester.widget<Stack>(
      find.byKey(StandardBackdrop.sceneStackKey),
    );
    expect(
      backgroundStack.children,
      hasLength(3),
      reason:
          'scene uses only backing, retained image, and Avalonia tone layer',
    );
  });

  testWidgets(
    'plain Standard runtime retains Greenhouse under the common tone',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: StandardBackdrop(backgroundId: 'plain-cobalt')),
      );

      expect(find.byKey(StandardBackdrop.plainKey), findsOneWidget);
      final image = tester.widget<Image>(find.byKey(StandardBackdrop.imageKey));
      expect(image.image, isA<AssetImage>());
      expect(
        (image.image as AssetImage).assetName,
        'assets/scenes/backdrop-alchemy-greenhouse.png',
      );
      expect(image.opacity, isNotNull);
      expect(image.opacity!.value, .32);
      expect(find.byKey(StandardBackdrop.toneKey), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is CustomPaint &&
              widget.painter is StandardBackdropTexturePainter,
        ),
        findsNothing,
        reason: 'plain gradients/grain are thumbnail-only treatments',
      );
    },
  );

  testWidgets('missing retained artwork produces an explicit failure surface', (
    tester,
  ) async {
    const failureKey = ValueKey<String>('missing-retained-art');
    await tester.pumpWidget(
      const MaterialApp(
        home: SizedBox(
          width: 280,
          height: 160,
          child: RetainedAssetImage(
            assetPath: 'assets/scenes/does-not-exist.png',
            assetLabel: 'Missing scene test',
            failureKey: failureKey,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(failureKey), findsOneWidget);
    expect(find.text('Artwork unavailable'), findsOneWidget);
    expect(find.text('Missing scene test'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('manuscript decorations never intercept child input', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox.expand(
          child: LedgerBackdrop(
            child: Center(
              child: GestureDetector(
                key: const ValueKey<String>('ledger-action'),
                behavior: HitTestBehavior.opaque,
                onTap: () => taps++,
                child: const SizedBox(width: 120, height: 48),
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.byKey(LedgerBackdrop.leatherKey), findsOneWidget);
    expect(find.byKey(LedgerBackdrop.vellumKey), findsOneWidget);
    expect(find.byKey(LedgerBackdrop.marginaliaKey), findsOneWidget);
    final leatherOpacity = tester.widget<Opacity>(
      find.ancestor(
        of: find.byKey(LedgerBackdrop.leatherKey),
        matching: find.byType(Opacity),
      ),
    );
    final vellumOpacity = tester.widget<Opacity>(
      find.ancestor(
        of: find.byKey(LedgerBackdrop.vellumKey),
        matching: find.byType(Opacity),
      ),
    );
    expect(leatherOpacity.opacity, 0.54);
    expect(vellumOpacity.opacity, 0.34);
    final cover = tester.widget<DecoratedBox>(
      find.byKey(LedgerBackdrop.coverGradientKey),
    );
    final coverGradient = (cover.decoration as BoxDecoration).gradient;
    expect(
      coverGradient,
      const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: <Color>[
          Color(0xFF06182C),
          Color(0xFF123E68),
          Color(0xFF071A2E),
        ],
        stops: <double>[0, 0.43, 1],
      ),
    );
    expect(
      (tester.widget<Image>(find.byKey(LedgerBackdrop.leatherKey)).image
              as AssetImage)
          .assetName,
      IlluminatedLedgerSpec.leatherAssetPath,
    );

    await tester.tap(find.byKey(const ValueKey<String>('ledger-action')));
    expect(taps, 1);
  });

  test(
    'Ledger vellum starts inside the body, below the separate title strip',
    () {
      final page = ledgerPageRect(const Size(1500, 900));

      expect(page, const Rect.fromLTRB(16, 8, 1484, 884));
    },
  );

  test('Ledger backdrop retains the exact Avalonia vellum and glow recipe', () {
    expect(LedgerPageBasePainter.pageGradientColors, const <Color>[
      Color(0xFFCFAF73),
      Color(0xFFE6CE98),
      Color(0xFFF1E0B7),
      Color(0xFFE9D3A2),
      Color(0xFFC9A96F),
    ]);
    expect(LedgerPageBasePainter.pageGradientStops, const <double>[
      0,
      0.08,
      0.32,
      0.73,
      1,
    ]);
    expect(
      LedgerBookDetailPainter.pageGlowRelativeCenter,
      const Offset(0.48, 0.36),
    );
    expect(LedgerBookDetailPainter.pageGlowRadiusX, 0.82);
    expect(LedgerBookDetailPainter.pageGlowRadiusY, 0.82);
    expect(LedgerBookDetailPainter.sidebarFoldWidth, 13);
  });

  test('book detail painter only repaints for structural changes', () {
    const original = LedgerBookDetailPainter(
      showSidebarFold: true,
      showCenterFold: true,
      centerFoldX: null,
      centerFoldRatio: 0.575,
      centerFoldWidth: 30,
    );
    const sameValues = LedgerBookDetailPainter(
      showSidebarFold: true,
      showCenterFold: true,
      centerFoldX: null,
      centerFoldRatio: 0.575,
      centerFoldWidth: 30,
    );
    const changed = LedgerBookDetailPainter(
      showSidebarFold: false,
      showCenterFold: true,
      centerFoldX: null,
      centerFoldRatio: 0.575,
      centerFoldWidth: 30,
    );

    expect(original.shouldRepaint(sameValues), isFalse);
    expect(original.shouldRepaint(changed), isTrue);
  });
}
