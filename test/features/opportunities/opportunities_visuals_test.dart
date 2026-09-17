import 'dart:ui' as ui;

import 'package:bdo_craft_planner_flutter/features/opportunities/opportunities_glass_material.dart';
import 'package:bdo_craft_planner_flutter/features/opportunities/opportunities_theme.dart';
import 'package:bdo_craft_planner_flutter/features/opportunities/opportunities_visuals.dart';
import 'package:bdo_craft_planner_flutter/visual/visual.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('card financial values never outrank the item name by size', () {
    expect(OpportunitiesVisualSpec.cardNameFontSize, 20);
    expect(OpportunitiesVisualSpec.cardPrimaryValueFontSize, 18);
    expect(
      OpportunitiesVisualSpec.cardPrimaryValueFontSize,
      lessThanOrEqualTo(OpportunitiesVisualSpec.cardNameFontSize),
    );
    expect(OpportunitiesVisualSpec.cardLabelFontSize, 14);
    expect(OpportunitiesVisualSpec.cardSecondaryValueFontSize, 15);
  });

  test('feature type uses one family and a clear readable size hierarchy', () {
    const type = OpportunitiesVisualSpec.typography;
    final styles = [
      type.display,
      type.section,
      type.body,
      type.meta,
      type.label,
      type.button,
    ];
    expect(styles.map((style) => style.fontFamily).toSet(), {'Segoe UI'});
    expect(styles.map((style) => style.fontSize), [28, 18, 16, 13, 14, 16]);
    expect(type.label.fontWeight, FontWeight.w500);
    expect(type.button.fontWeight, FontWeight.w500);
    expect(type.section.fontWeight, FontWeight.w600);
    expect(type.body.fontWeight, isNot(FontWeight.w600));
  });

  testWidgets('reading surfaces use one border and solid navy without bevel', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            OpportunitySurface(
              key: ValueKey('header'),
              role: AppSurfaceRole.commandBand,
              child: Text('Opportunities'),
            ),
            OpportunitySurface(
              key: ValueKey('toolbar'),
              role: AppSurfaceRole.panel,
              child: Text('Cooking'),
            ),
            OpportunitySurface(
              key: ValueKey('body-card'),
              role: AppSurfaceRole.card,
              child: Text('Beer'),
            ),
          ],
        ),
      ),
    );
    BoxDecoration decoration(String key) =>
        tester
                .widget<DecoratedBox>(
                  find.descendant(
                    of: find.byKey(ValueKey(key)),
                    matching: find.byKey(AppSurface.materialKey),
                  ),
                )
                .decoration
            as BoxDecoration;
    expect(decoration('header').border, isNull);
    expect(decoration('header').gradient, isNull);
    expect(decoration('header').color, Colors.transparent);
    expect(
      decoration('toolbar').color,
      OpportunitiesVisualSpec.palette.surfaceRaised,
    );
    expect(
      decoration('body-card').color,
      OpportunitiesVisualSpec.palette.surface,
    );
    for (final key in ['toolbar', 'body-card']) {
      final surface = decoration(key);
      expect(surface.gradient, isNull);
      expect(surface.boxShadow, isNull);
      expect(surface.color!.a, 1);
      expect(surface.border, isA<Border>());
      expect((surface.border! as Border).top.width, 1);
      expect(surface.borderRadius, BorderRadius.circular(12));
      final host = tester.widget<DecoratedBox>(
        find.descendant(
          of: find.byKey(ValueKey(key)),
          matching: find.byKey(AppSurface.materialKey),
        ),
      );
      expect(host.child, isA<Material>());
      final material = host.child! as Material;
      expect(material.type, MaterialType.transparency);
      expect(material.elevation, 0);
    }
    expect(find.byType(BackdropFilter), findsNothing);
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('static backdrop remains dark navy teal and does not hit test', (
    tester,
  ) async {
    await tester.runAsync(() async {
      const painter = OpportunityGlassBackdrop();
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      painter.paint(canvas, const Size(300, 180));
      final picture = recorder.endRecording();
      final image = await picture.toImage(300, 180);
      final pixels = (await image.toByteData())!;
      final colours = <int>{};
      for (var y = 0; y < 180; y += 10) {
        for (var x = 0; x < 300; x += 10) {
          final index = (y * 300 + x) * 4;
          final red = pixels.getUint8(index);
          final green = pixels.getUint8(index + 1);
          final blue = pixels.getUint8(index + 2);
          final alpha = pixels.getUint8(index + 3);
          final colour = Color.fromARGB(alpha, red, green, blue);
          expect(alpha, 255);
          expect(red, lessThan(green), reason: 'No purple wash at ($x, $y)');
          expect(green, lessThanOrEqualTo(blue));
          expect(colour.computeLuminance(), lessThan(.04));
          colours.add(colour.toARGB32());
        }
      }
      expect(colours.length, greaterThan(8), reason: 'Keep subtle atmosphere.');
      expect(painter.hitTest(const Offset(130, 50)), isFalse);
      expect(painter.shouldRepaint(painter), isFalse);
      image.dispose();
      picture.dispose();
    });
  });

  testWidgets('direction B card materials do not change other reading roles', (
    tester,
  ) async {
    var taps = 0;
    for (final background in [
      'greenhouse',
      SakuraNightGardenSpec.backgroundId,
    ]) {
      await tester.pumpWidget(
        _host(
          outerBackground: background,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              OpportunitySurface(
                key: const ValueKey('direction-b-card'),
                role: AppSurfaceRole.card,
                padding: EdgeInsets.zero,
                decoration: OpportunitiesVisualSpec.recipeCard,
                child: InkWell(
                  onTap: () => taps++,
                  child: const SizedBox(
                    width: 400,
                    height: 150,
                    child: Text('Gem Polisher'),
                  ),
                ),
              ),
              const OpportunitySurface(
                key: ValueKey('unchanged-panel'),
                role: AppSurfaceRole.panel,
                child: Text('Calculation'),
              ),
            ],
          ),
        ),
      );
      final card = tester.widget<DecoratedBox>(
        find.descendant(
          of: find.byKey(const ValueKey('direction-b-card')),
          matching: find.byKey(AppSurface.materialKey),
        ),
      );
      expect(card.decoration, OpportunitiesVisualSpec.recipeCard);
      final material = card.decoration as BoxDecoration;
      expect(material.color, const Color(0xFF162A3A));
      expect(material.gradient, isNull);
      expect(material.borderRadius, BorderRadius.circular(12));
      expect(material.boxShadow, hasLength(1));
      expect(material.boxShadow!.single.blurRadius, 18);
      expect(material.boxShadow!.single.color, const Color(0x24030A10));
      final panel = tester.widget<DecoratedBox>(
        find.descendant(
          of: find.byKey(const ValueKey('unchanged-panel')),
          matching: find.byKey(AppSurface.materialKey),
        ),
      );
      expect(
        (panel.decoration as BoxDecoration).color,
        OpportunitiesVisualSpec.palette.surfaceRaised,
      );
      expect((panel.decoration as BoxDecoration).boxShadow, isNull);
      await tester.tap(find.text('Gem Polisher'));
      expect(tester.takeException(), isNull);
    }
    expect(taps, 2);
    expect(OpportunitiesVisualSpec.recipeArtworkRail.gradient, isNotNull);
    expect(OpportunitiesVisualSpec.recipeArtworkRail.gradient!.colors, [
      const Color(0xFF223F4B),
      const Color(0xFF193140),
    ]);
    expect(OpportunitiesVisualSpec.recipeFooter.color, const Color(0xFF132635));
    final footerBorder = OpportunitiesVisualSpec.recipeFooter.border! as Border;
    expect(footerBorder.top.width, 1);
    expect(footerBorder.left, BorderSide.none);
    expect(footerBorder.right, BorderSide.none);
    expect(footerBorder.bottom, BorderSide.none);
  });

  testWidgets('overlay roles and tooltips use an opaque reading plane', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final role in [
              AppSurfaceRole.modal,
              AppSurfaceRole.popup,
              AppSurfaceRole.tooltip,
            ])
              OpportunitySurface(
                key: ValueKey(role),
                role: role,
                child: Text(role.name),
              ),
          ],
        ),
      ),
    );
    for (final role in [
      AppSurfaceRole.modal,
      AppSurfaceRole.popup,
      AppSurfaceRole.tooltip,
    ]) {
      final box = tester.widget<DecoratedBox>(
        find.descendant(
          of: find.byKey(ValueKey(role)),
          matching: find.byKey(AppSurface.materialKey),
        ),
      );
      final decoration = box.decoration as BoxDecoration;
      expect(decoration.gradient, isNull);
      expect(decoration.color, OpportunitiesVisualSpec.palette.surfaceRaised);
      expect(decoration.color!.a, 1);
      expect(decoration.boxShadow, isNull);
    }
    final context = tester.element(find.byType(OpportunitySurface).first);
    final tooltip = Theme.of(context).tooltipTheme;
    expect(tooltip.textStyle!.fontSize, 16);
    expect(
      (tooltip.decoration! as BoxDecoration).gradient,
      OpportunitiesVisualSpec.overlay,
    );
    expect(OpportunitiesVisualSpec.overlay.colors.toSet(), {
      OpportunitiesVisualSpec.palette.surfaceRaised,
    });
    expect(tester.takeException(), isNull);
  });

  testWidgets('all controls keep a comfortable target at either text size', (
    tester,
  ) async {
    for (final scale in [1.0, 2.0]) {
      await tester.pumpWidget(
        _host(
          scale: scale,
          child: SizedBox(
            width: 300,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                OpportunityButton.label(
                  'Refresh',
                  key: const ValueKey('ordinary'),
                  onPressed: () {},
                ),
                OpportunityButton.label(
                  'Filters',
                  key: const ValueKey('compact'),
                  minimumSize: const Size(0, 38),
                  onPressed: () {},
                ),
                OpportunityButton.icon(
                  key: const ValueKey('icon'),
                  icon: const Icon(Icons.info_outline),
                  semanticLabel: 'Details',
                  onPressed: () {},
                ),
                const OpportunityTextField(label: 'Extra costs'),
              ],
            ),
          ),
        ),
      );
      expect(
        tester.getSize(find.byKey(const ValueKey('ordinary'))).height,
        greaterThanOrEqualTo(40),
      );
      expect(
        tester.getSize(find.byKey(const ValueKey('compact'))).height,
        greaterThanOrEqualTo(40),
      );
      final icon = tester.getSize(find.byKey(const ValueKey('icon')));
      expect(icon.width, greaterThanOrEqualTo(40));
      expect(icon.height, greaterThanOrEqualTo(40));
      expect(
        tester.getSize(find.byType(TextField)).height,
        greaterThanOrEqualTo(40),
      );
      if (scale == 1) {
        expect(
          tester.getSize(find.byKey(const ValueKey('ordinary'))).height,
          40,
        );
        expect(
          tester.getSize(find.byKey(const ValueKey('compact'))).height,
          40,
        );
        expect(icon, const Size.square(40));
      } else {
        expect(
          tester.getSize(find.byKey(const ValueKey('ordinary'))).height,
          greaterThan(40),
        );
        expect(tester.getSize(find.byType(TextField)).height, greaterThan(40));
      }
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('comparison finish stays open and preserves row input and size', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      _host(
        child: Material(
          type: MaterialType.transparency,
          child: OpportunityComparisonRowFinish(
            key: const ValueKey('row-finish'),
            alternate: true,
            child: InkWell(
              onTap: () => taps++,
              child: const SizedBox(
                width: 400,
                height: 84,
                child: Text('Beer'),
              ),
            ),
          ),
        ),
      ),
    );
    final row = find.byKey(const ValueKey('row-finish'));
    expect(tester.getSize(row), const Size(400, 84));
    final ink = tester.widget<Ink>(
      find.descendant(of: row, matching: find.byType(Ink)),
    );
    final border = (ink.decoration! as BoxDecoration).border! as Border;
    expect(border.left, BorderSide.none);
    expect(border.right, BorderSide.none);
    expect(border.top, BorderSide.none);
    expect(border.bottom.width, 1);
    expect((ink.decoration! as BoxDecoration).gradient, isNull);
    expect((ink.decoration! as BoxDecoration).boxShadow, isNull);
    await tester.tap(find.text('Beer'));
    expect(taps, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'local fields, cards and selected controls ignore outer appearance',
    (tester) async {
      BoxDecoration? firstCard;
      BoxDecoration? firstButton;
      InputDecoration? firstField;
      for (final settings in [
        (background: 'greenhouse', hue: 310.0, neon: true),
        (
          background: SakuraNightGardenSpec.backgroundId,
          hue: 80.0,
          neon: false,
        ),
      ]) {
        await tester.pumpWidget(
          _host(
            outerBackground: settings.background,
            hue: settings.hue,
            neon: settings.neon,
            child: SizedBox(
              width: 280,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  OpportunitySurface(
                    key: const ValueKey('card'),
                    child: Builder(
                      builder: (context) {
                        expect(
                          context.visualTheme,
                          same(OpportunitiesVisualSpec.spec),
                        );
                        return const Text('Investment');
                      },
                    ),
                  ),
                  OpportunityFilterButton(
                    key: const ValueKey('filter'),
                    selected: true,
                    label: 'Ingredients available',
                    onChanged: (_) {},
                  ),
                  const OpportunityTextField(
                    label: 'Extra costs',
                    hintText: '0',
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final card =
            tester
                    .widget<DecoratedBox>(
                      find.descendant(
                        of: find.byKey(const ValueKey('card')),
                        matching: find.byKey(AppSurface.materialKey),
                      ),
                    )
                    .decoration
                as BoxDecoration;
        final button =
            tester
                    .widget<AnimatedContainer>(
                      find.descendant(
                        of: find.byKey(const ValueKey('filter')),
                        matching: find.byKey(AppButton.materialKey),
                      ),
                    )
                    .decoration
                as BoxDecoration;
        final field = tester
            .widget<TextField>(find.byType(TextField))
            .decoration!;
        expect(card.image, isNull);
        expect(field.fillColor, OpportunitiesVisualSpec.palette.surfaceInset);
        expect(
          (field.focusedBorder! as OutlineInputBorder).borderSide.color,
          OpportunitiesVisualSpec.palette.primaryBright,
        );
        if (firstCard == null) {
          firstCard = card;
          firstButton = button;
          firstField = field;
        } else {
          expect(card, firstCard);
          expect(button, firstButton);
          expect(field, firstField);
        }
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'local button keeps pointer, keyboard, focus and semantic actions',
    (tester) async {
      final focus = FocusNode();
      addTearDown(focus.dispose);
      var count = 0;
      await tester.pumpWidget(
        _host(
          child: OpportunityButton.label(
            'Check prices',
            key: const ValueKey('button'),
            focusNode: focus,
            semanticLabel: 'Check current prices',
            onPressed: () => count++,
          ),
        ),
      );
      final button = find.byKey(const ValueKey('button'));
      final initialSize = tester.getSize(button);
      expect(tester.widget(button), isA<AppButton>());
      final semantics = tester.ensureSemantics();
      final node = tester.getSemantics(button);
      expect(node.label, 'Check current prices');
      expect(node.getSemanticsData().flagsCollection.isButton, isTrue);
      semantics.dispose();
      await tester.tap(button);
      expect(count, 1);
      focus.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(count, 3);
      expect(
        tester.getSize(button),
        initialSize,
        reason: 'Focus must not move surrounding controls.',
      );
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(tester.getCenter(button));
      await tester.pumpAndSettle();
      expect(tester.getSize(button), initialSize);
      await mouse.removePointer();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'disabled button never activates and filter remains a real toggle',
    (tester) async {
      var changed = false;
      await tester.pumpWidget(
        _host(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              OpportunityButton.label('Unavailable', onPressed: null),
              OpportunityFilterButton(
                label: 'Only profitable',
                selected: false,
                onChanged: (value) => changed = value,
              ),
            ],
          ),
        ),
      );
      await tester.tap(find.text('Unavailable'));
      expect(changed, isFalse);
      await tester.tap(find.text('Only profitable'));
      expect(changed, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('selected flat button keeps light text and a clear focus edge', (
    tester,
  ) async {
    final focus = FocusNode();
    addTearDown(focus.dispose);
    await tester.pumpWidget(
      _host(
        child: OpportunityButton.label(
          'Crafting',
          selected: true,
          focusNode: focus,
          onPressed: () {},
        ),
      ),
    );
    final context = tester.element(find.text('Crafting'));
    expect(
      DefaultTextStyle.of(context).style.color,
      OpportunitiesVisualSpec.palette.text,
    );
    expect(DefaultTextStyle.of(context).style.fontWeight, FontWeight.w600);
    focus.requestFocus();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    focus.requestFocus();
    await tester.pumpAndSettle();
    final material = tester.widget<AnimatedContainer>(
      find.byKey(AppButton.materialKey),
    );
    final decoration = material.decoration! as BoxDecoration;
    expect(decoration.gradient, isNull);
    expect(decoration.boxShadow, isNull);
    expect(
      decoration.color,
      Color.alphaBlend(
        OpportunitiesVisualSpec.palette.primary.withAlpha(32),
        OpportunitiesVisualSpec.palette.surfaceInset,
      ),
    );
    expect(material.transform, isNull);
    expect(
      (decoration.border! as Border).top.color,
      OpportunitiesVisualSpec.palette.primaryBright,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'field preserves editing, formatter and keyboard callbacks at 200 percent',
    (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      var submitted = '';
      var keyCount = 0;
      await tester.pumpWidget(
        _host(
          scale: 2,
          child: SizedBox(
            width: 280,
            child: OpportunityTextField(
              controller: controller,
              label: 'Extra costs',
              minimumHeight: 38,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onSubmitted: (value) => submitted = value,
              onKeyEvent: (_, event) {
                if (event is KeyDownEvent &&
                    event.logicalKey == LogicalKeyboardKey.f2) {
                  keyCount++;
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
            ),
          ),
        ),
      );
      final field = find.byType(TextField);
      final decoration = tester.widget<TextField>(field).decoration!;
      expect(decoration.labelStyle!.fontSize, 14);
      expect(decoration.floatingLabelStyle!.fontSize! * .75, 14);
      await tester.enterText(field, '12a3');
      expect(controller.text, '123');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      expect(submitted, '123');
      await tester.tap(field);
      await tester.sendKeyEvent(LogicalKeyboardKey.f2);
      expect(keyCount, 1);
      expect(tester.getSize(field).height, greaterThanOrEqualTo(52));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('reduced motion skips entrance and control transitions', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(child: OpportunityButton.label('Refresh', onPressed: () {})),
    );
    final entrance = tester.widget<FadeTransition>(
      find.descendant(
        of: find.byType(OpportunityEntrance),
        matching: find.byType(FadeTransition),
      ),
    );
    expect(entrance.opacity.value, 1);
    final material = tester.widget<AnimatedContainer>(
      find.byKey(AppButton.materialKey),
    );
    expect(material.duration, Duration.zero);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('entrance runs once and leaves no idle animation ticker', (
    tester,
  ) async {
    Widget host(String label) =>
        _host(disableAnimations: false, child: Text(label));
    await tester.pumpWidget(host('First result'));
    await tester.pump(const Duration(milliseconds: 250));
    expect(tester.binding.transientCallbackCount, 0);
    await tester.pumpWidget(host('New market result'));
    final fade = tester.widget<FadeTransition>(
      find.descendant(
        of: find.byType(OpportunityEntrance),
        matching: find.byType(FadeTransition),
      ),
    );
    expect(fade.opacity.value, 1);
    expect(tester.binding.transientCallbackCount, 0);
  });

  test('text and figures stay readable across surfaces and selected fills', () {
    const p = OpportunitiesVisualSpec.palette;
    double contrast(Color a, Color b) {
      final first = a.computeLuminance();
      final second = b.computeLuminance();
      return first > second
          ? (first + .05) / (second + .05)
          : (second + .05) / (first + .05);
    }

    for (final surface in [
      p.surface,
      p.surfaceRaised,
      p.surfaceInset,
      ...OpportunitiesVisualSpec.overlay.colors,
      for (final color in [
        ...OpportunitiesVisualSpec.materials.surface.colors,
        ...OpportunitiesVisualSpec.materials.surfaceRaised.colors,
      ])
        // Even a bright underlying scene cannot wash out the text.
        Color.alphaBlend(color, Colors.white),
    ]) {
      for (final foreground in [
        p.text,
        p.textMuted,
        p.success,
        p.danger,
        p.warning,
      ]) {
        expect(
          contrast(foreground, surface),
          greaterThanOrEqualTo(4.5),
          reason: '$foreground on $surface',
        );
      }
    }
    for (final color in [
      ...OpportunitiesVisualSpec.materials.primary.colors,
      ...OpportunitiesVisualSpec.materials.secondary.colors,
      Color.alphaBlend(p.primary.withAlpha(32), p.surfaceInset),
      Color.alphaBlend(p.primary.withAlpha(45), p.surfaceInset),
    ]) {
      expect(
        contrast(p.text, Color.alphaBlend(color, Colors.white)),
        greaterThanOrEqualTo(4.5),
      );
    }
    expect(contrast(p.canvasDeep, p.primary), greaterThanOrEqualTo(7));
  });
}

Widget _host({
  required Widget child,
  String outerBackground = 'greenhouse',
  double hue = 158,
  bool neon = false,
  bool disableAnimations = true,
  double scale = 1,
}) => MaterialApp(
  debugShowCheckedModeBanner: false,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(
      disableAnimations: disableAnimations,
      textScaler: TextScaler.linear(scale),
    ),
    child: child!,
  ),
  home: ThemeSpecScope(
    spec: RetainedThemeRegistry.resolve(backgroundId: outerBackground),
    child: StandardVisualScope(
      settings: StandardVisualSettings(
        backgroundId: outerBackground,
        accentHue: hue,
        neon: neon,
        rainbow: neon,
      ),
      child: OpportunitiesTheme(child: Center(child: child)),
    ),
  ),
);
