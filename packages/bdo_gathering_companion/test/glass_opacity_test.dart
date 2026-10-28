import 'package:bdo_gathering_companion/src/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'expedition materials retain distinct gradient faces and artwork wells',
    () {
      final glass = CompanionGlassTheme.fromPercent(100);
      final theme = companionTheme(opacityPercent: 100);
      expect(canvasColor, const Color(0xFF141218));
      expect(glass.panel, const Color(0xFF25212A));
      expect(glass.row, const Color(0xFF342B32));
      expect(glass.popup, const Color(0xFF1B171E));
      expect(glass.iconWell, const Color(0xFF393039));
      expect(glass.toolPlate, const Color(0xFF6B5A57));
      expect(glass.toolPlateSelected, const Color(0xFF7A6260));
      expect(accent, const Color(0xFFE1B5B1));
      expect(positive, const Color(0xFF9DC4AA));
      // The broad satin shoulder replaces the old flat two/three-stop faces.
      // Keep the original .52 surface-alpha knot as well as the new RGB knots.
      expect(glass.surfaceGradient.stops, const [0, .16, .52, .55, 1]);
      expect(glass.controlGradient.stops, const [0, .16, .55, 1]);
      expect(glass.selectedGradient.stops, const [0, .16, .55, 1]);
      expect(
        glass.surfaceGradient.colors.first,
        Color.alphaBlend(ink.withAlpha(20), const Color(0xFF3B3038)),
      );
      expect(
        glass.surfaceGradient.colors.last,
        Color.lerp(const Color(0xFF1C1820), const Color(0xFF251F28), .70),
      );
      expect(
        glass.controlGradient.colors.first,
        Color.alphaBlend(ink.withAlpha(20), const Color(0xFF342B32)),
      );
      expect(
        glass.selectedGradient.colors.first,
        Color.alphaBlend(ink.withAlpha(8), const Color(0xFF51343D)),
      );
      for (final face in [
        glass.surfaceGradient,
        glass.controlGradient,
        glass.selectedGradient,
      ]) {
        expect(face.colors.every((color) => color.a == 1), isTrue);
        for (var i = 1; i < face.colors.length; i++) {
          expect(
            face.colors[i - 1].computeLuminance(),
            greaterThan(face.colors[i].computeLuminance()),
          );
        }
      }
      for (final well in [glass.iconWellGradient, glass.toolWellGradient]) {
        expect(well.begin, Alignment.topCenter);
        expect(well.end, Alignment.bottomCenter);
        expect(well.stops, const [0, .32, 1]);
        expect(
          well.colors.last.computeLuminance(),
          greaterThan(well.colors.first.computeLuminance()),
          reason: 'Artwork wells have a darker recess and a lit lower lip.',
        );
      }
      expect(glass.primaryGradient.colors, const [
        Color(0xFFE1B5B1),
        Color(0xFFC58C92),
      ]);
      expect(glass.controlGradient.begin, Alignment.topCenter);
      expect(glass.selectedGradient.begin, Alignment.topLeft);
      expect(glass.headerGradient.colors, isNot(glass.surfaceGradient.colors));
      expect(
        glass.iconWell.computeLuminance(),
        greaterThan(glass.panel.computeLuminance()),
      );
      expect(
        glass.toolPlate.computeLuminance(),
        greaterThan(glass.iconWell.computeLuminance()),
      );
      expect(
        glass.toolPlateSelected.computeLuminance(),
        greaterThan(glass.toolPlate.computeLuminance()),
      );
      expect(HSLColor.fromColor(accent).hue, inInclusiveRange(0, 10));
      expect(theme.chipTheme.labelStyle?.color, ink);
      expect(theme.chipTheme.secondaryLabelStyle?.color, ink);
      expect(theme.chipTheme.checkmarkColor, accent);
      for (final surface in [
        glass.panel,
        glass.row,
        glass.popup,
        glass.active,
        glass.hover,
        glass.group,
        glass.iconWell,
        ...glass.surfaceGradient.colors,
        ...glass.headerGradient.colors,
        ...glass.controlGradient.colors,
        ...glass.hoverGradient.colors,
        ...glass.selectedGradient.colors,
        ...glass.iconWellGradient.colors,
      ]) {
        for (final foreground in [ink, muted, accent, positive]) {
          expect(_contrast(foreground, surface), greaterThanOrEqualTo(4.5));
        }
      }
      expect(
        _contrast(theme.colorScheme.onPrimary, accent),
        greaterThanOrEqualTo(4.5),
      );
      for (final face in glass.primaryGradient.colors) {
        expect(
          _contrast(theme.colorScheme.onPrimary, face),
          greaterThanOrEqualTo(4.5),
        );
      }
      expect(theme.colorScheme.onPrimary, const Color(0xFF22191C));
      // Grade frames identify game rarity, not the application palette.
      expect(itemGradeColor(2), const Color(0xFF04B3F1));
      expect(itemGradeColor(3), const Color(0xFFF6C232));
      expect(itemGradeColor(4), const Color(0xFFFF7C00));
    },
  );

  testWidgets(
    'artwork backing can be supplied without changing the original image',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: companionTheme(),
          home: const Row(
            children: [
              GameIcon(
                'assets/icons/tools/sniper_rifle.webp',
                key: ValueKey('default-artwork'),
              ),
              GameIcon(
                'assets/icons/tools/sniper_rifle.webp',
                key: ValueKey('clear-artwork'),
                backgroundColor: Colors.transparent,
              ),
            ],
          ),
        ),
      );
      BoxDecoration backing(String key) =>
          tester
                  .widget<Container>(
                    find
                        .descendant(
                          of: find.byKey(ValueKey(key)),
                          matching: find.byType(Container),
                        )
                        .first,
                  )
                  .decoration!
              as BoxDecoration;
      expect(
        backing('default-artwork').gradient,
        CompanionGlassTheme.fromPercent(60).iconWellGradient,
      );
      expect(backing('clear-artwork').color, Colors.transparent);
      expect(backing('clear-artwork').gradient, isNull);
      for (final image in tester.widgetList<Image>(find.byType(Image))) {
        expect(
          (image.image as AssetImage).assetName,
          'assets/icons/tools/sniper_rifle.webp',
        );
        expect(image.color, isNull);
      }
    },
  );

  test('default opacity preserves the saved Fish Map-aligned preference', () {
    expect(defaultGlassOpacityPercent, 60);
    expect(normalizeGlassOpacity(null), 60);
    // The saved material opacity is not the modal dimming strength.
    expect(
      CompanionGlassTheme.fromPercent(60).backdropOpacity,
      closeTo(.60, .00001),
    );
  });

  test('frost and clearcoat stay subtle and preserve text contrast', () {
    final glass = CompanionGlassTheme.fromPercent(defaultGlassOpacityPercent);
    expect(glassBlurSigma, 14);
    expect(glass.clearcoatGradient.colors.first.a, closeTo(.00359, .0001));
    expect(
      glass.clearcoatGradient.colors.first.a,
      greaterThan(glass.clearcoatGradient.colors[1].a),
    );
    for (final percent in [defaultGlassOpacityPercent, 100]) {
      final material = CompanionGlassTheme.fromPercent(percent);
      for (final tint in [
        ...material.surfaceGradient.colors,
        material.row,
        material.active,
        material.hover,
      ]) {
        final surface = Color.alphaBlend(tint, const Color(0xFF27212A));
        final coated = Color.alphaBlend(
          material.clearcoatGradient.colors.first,
          surface,
        );
        for (final foreground in [ink, muted, accent, positive]) {
          expect(
            _contrast(foreground, coated),
            greaterThanOrEqualTo(4.5),
            reason: '$percent% foreground $foreground over coated tint $tint',
          );
        }
      }
    }
    expect(
      CompanionGlassTheme.fromPercent(0).clearcoatGradient.colors.first.a,
      lessThan(.002),
    );
  });

  testWidgets('glass blurs the backdrop, not content or button interactions', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: companionTheme(),
        builder: companionBackdropBuilder,
        home: Center(
          child: GlassSurface(
            child: Material(
              color: Colors.transparent,
              child: GlassSheen(
                child: InkWell(
                  onTap: () => taps++,
                  child: const Padding(
                    padding: EdgeInsets.all(20),
                    child: Text('Readable glass'),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.byType(BackdropFilter), findsOneWidget);
    final label = find.text('Readable glass');
    expect(
      find.ancestor(of: label, matching: find.byType(ImageFiltered)),
      findsNothing,
    );
    await tester.tap(label);
    await tester.pumpAndSettle();
    expect(taps, 1);
    expect(tester.takeException(), isNull);
  });

  test(
    'zero map opacity preserves translucent controls but protects popup text',
    () {
      final glass = CompanionGlassTheme.fromPercent(0);
      final theme = companionTheme(opacityPercent: 0);
      final tooltip = theme.tooltipTheme.decoration! as BoxDecoration;

      expect(glass.surfaceOpacity, closeTo(.02, .0001));
      expect(glass.panel.a, closeTo(glass.surfaceOpacity, .0001));
      expect(glass.row.a, closeTo(glass.controlOpacity, .0001));
      expect(glass.popup.a, greaterThanOrEqualTo(.98));
      expect(glass.iconWell.a, lessThan(.03));
      expect(glass.toolPlate.a, lessThan(.03));
      expect(glass.toolPlateSelected.a, lessThan(1));
      expect(glass.group.a, lessThan(.03));
      expect(tooltip.color!.a, closeTo(glass.popup.a, .0001));
      expect(theme.shadowColor.a, closeTo(glass.shadowOpacity, .0001));
      expect(
        theme.dialogTheme.barrierColor!.a,
        closeTo(glass.backdropOpacity, .0001),
      );
    },
  );

  testWidgets(
    'semantic faces preserve child sizing and enabled button actions',
    (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: companionTheme(),
          home: Scaffold(
            body: Column(
              children: [
                GlassControl(
                  key: const ValueKey('sized-control'),
                  selected: true,
                  child: InkWell(
                    onTap: () => taps++,
                    child: const SizedBox(
                      width: 120,
                      height: 48,
                      child: Text('Selected'),
                    ),
                  ),
                ),
                const GlassArtworkWell(
                  key: ValueKey('sized-artwork'),
                  tool: true,
                  child: SizedBox(width: 54, height: 54),
                ),
                FilledButton(
                  onPressed: () => taps++,
                  child: const Text('Enabled'),
                ),
                const FilledButton(onPressed: null, child: Text('Disabled')),
              ],
            ),
          ),
        ),
      );
      expect(
        tester.getSize(find.byKey(const ValueKey('sized-control'))),
        const Size(120, 48),
      );
      expect(
        tester.getSize(find.byKey(const ValueKey('sized-artwork'))),
        const Size(54, 54),
      );
      expect(find.byType(BackdropFilter), findsNothing);
      await tester.tap(find.text('Selected'));
      await tester.tap(find.text('Enabled'));
      await tester.tap(find.text('Disabled'));
      await tester.pumpAndSettle();
      expect(taps, 2);
      final style = companionTheme().filledButtonTheme.style!;
      final context = tester.element(find.text('Disabled'));
      const disabledChild = Text('unchanged disabled child');
      expect(
        style.backgroundBuilder!(context, {
          WidgetState.disabled,
        }, disabledChild),
        same(disabledChild),
      );
      expect(tester.takeException(), isNull);
    },
  );

  test('full opacity makes Gathering UI surfaces opaque', () {
    final glass = CompanionGlassTheme.fromPercent(100);

    expect(glass.panel.a, closeTo(1, .0001));
    expect(glass.row.a, closeTo(1, .0001));
    expect(glass.popup.a, closeTo(1, .0001));
    expect(glass.backdropOpacity, closeTo(.60, .0001));
  });

  testWidgets(
    'reading surfaces protect descendants without changing map opacity',
    (tester) async {
      for (final percent in [0, 25, 60, 100]) {
        await tester.pumpWidget(
          MaterialApp(
            theme: companionTheme(opacityPercent: percent),
            home: Scaffold(
              body: Column(
                children: [
                  const Text(
                    'Map control',
                    key: ValueKey('unscoped-map-control'),
                  ),
                  GlassSurface(
                    reading: true,
                    child: Builder(
                      builder: (context) => const Text(
                        'Readable details',
                        key: ValueKey('protected-reading-text'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          tester
              .element(find.byKey(const ValueKey('unscoped-map-control')))
              .glass
              .opacityPercent,
          percent,
        );
        final reading = tester
            .element(find.byKey(const ValueKey('protected-reading-text')))
            .glass;
        expect(reading.opacityPercent, percent < 96 ? 96 : percent);
        expect(reading.panel.a, greaterThanOrEqualTo(.96));
        expect(reading.popup.a, greaterThanOrEqualTo(.98));
        expect(reading.backdropOpacity, .60);
        expect(tester.takeException(), isNull);
      }
    },
  );

  for (final percent in [0, 25]) {
    testWidgets(
      'tooltip stays readable and bounded at $percent% map opacity and 200% text',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(420, 700);
        addTearDown(tester.view.reset);
        final tooltipKey = GlobalKey<TooltipState>();
        const message =
            'Gathering Item Drop Rate\nThe chance of getting extra gathering items.';
        final theme = companionTheme(opacityPercent: percent);
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: Scaffold(
              backgroundColor: Colors.white,
              body: Center(
                child: Tooltip(
                  key: tooltipKey,
                  message: message,
                  child: const Icon(Icons.info_outline),
                ),
              ),
            ),
          ),
        );
        tooltipKey.currentState!.ensureTooltipVisible();
        await tester.pumpAndSettle();
        final text = find.byWidgetPredicate(
          (widget) =>
              widget is RichText && widget.text.toPlainText() == message,
        );
        expect(text, findsOneWidget);
        final bounds = tester.getRect(text);
        expect(bounds.left, greaterThanOrEqualTo(0));
        expect(bounds.right, lessThanOrEqualTo(420));
        expect(bounds.top, greaterThanOrEqualTo(0));
        expect(bounds.bottom, lessThanOrEqualTo(700));
        final decoration = theme.tooltipTheme.decoration! as BoxDecoration;
        expect(decoration.color!.a, greaterThanOrEqualTo(.98));
        expect(
          _contrast(ink, Color.alphaBlend(decoration.color!, Colors.white)),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          theme.tooltipTheme.textStyle!.fontSize,
          greaterThanOrEqualTo(14),
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}

double _contrast(Color foreground, Color background) {
  final first = foreground.computeLuminance();
  final second = background.computeLuminance();
  return first >= second
      ? (first + .05) / (second + .05)
      : (second + .05) / (first + .05);
}
