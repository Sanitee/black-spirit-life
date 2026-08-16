import 'package:bdo_craft_planner_flutter/visual/components/app_brand_lockup.dart';
import 'package:bdo_craft_planner_flutter/visual/components/app_button.dart';
import 'package:bdo_craft_planner_flutter/visual/components/app_completion_control.dart';
import 'package:bdo_craft_planner_flutter/visual/components/app_surface.dart';
import 'package:bdo_craft_planner_flutter/visual/components/app_vector_glyph.dart';
import 'package:bdo_craft_planner_flutter/visual/components/section_header.dart';
import 'package:bdo_craft_planner_flutter/visual/foundations/theme_spec.dart';
import 'package:bdo_craft_planner_flutter/visual/illuminated_ledger/ledger_ornament_painters.dart';
import 'package:bdo_craft_planner_flutter/visual/illuminated_ledger/ledger_spec.dart';
import 'package:bdo_craft_planner_flutter/visual/sakura_night_garden/sakura_material_painters.dart';
import 'package:bdo_craft_planner_flutter/visual/sakura_night_garden/sakura_spec.dart';
import 'package:bdo_craft_planner_flutter/visual/standard/standard_spec.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(
  ThemeSpec spec,
  Widget child, {
  StandardVisualSettings standard = StandardVisualSettings.fallback,
}) => MaterialApp(
  theme: spec.materialTheme(),
  home: ThemeSpecScope(
    spec: spec,
    child: StandardVisualScope(
      settings: standard,
      child: Scaffold(body: Center(child: child)),
    ),
  ),
);

BoxDecoration _buttonDecoration(WidgetTester tester) =>
    tester
            .widget<AnimatedContainer>(find.byKey(AppButton.materialKey))
            .decoration!
        as BoxDecoration;

void main() {
  testWidgets('button hover, press, and focus do not alter geometry', (
    tester,
  ) async {
    var activations = 0;
    final focusNode = FocusNode();
    addTearDown(focusNode.dispose);
    await tester.pumpWidget(
      _host(
        StandardSpec.theme,
        AppButton.label(
          'Apply',
          onPressed: () => activations++,
          role: AppButtonRole.primary,
          focusNode: focusNode,
        ),
      ),
    );

    final initialSize = tester.getSize(find.byType(AppButton));
    final initialBorder = _buttonDecoration(tester).border! as Border;
    final focusable = tester.widget<FocusableActionDetector>(
      find.descendant(
        of: find.byType(AppButton),
        matching: find.byType(FocusableActionDetector),
      ),
    );
    focusable.onShowHoverHighlight!(true);
    await tester.pumpAndSettle();
    final hoverBorder = _buttonDecoration(tester).border! as Border;
    expect(hoverBorder.top.color, isNot(initialBorder.top.color));
    expect(tester.getSize(find.byType(AppButton)), initialSize);

    final gestureDetector = tester.widget<GestureDetector>(
      find.descendant(
        of: find.byType(AppButton),
        matching: find.byType(GestureDetector),
      ),
    );
    gestureDetector.onTapDown!(TapDownDetails());
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(AppButton)), initialSize);
    gestureDetector.onTapCancel!();

    focusNode.requestFocus();
    tester
        .widget<FocusableActionDetector>(
          find.descendant(
            of: find.byType(AppButton),
            matching: find.byType(FocusableActionDetector),
          ),
        )
        .onShowFocusHighlight!(true);
    await tester.pumpAndSettle();
    final focusBorder = _buttonDecoration(tester).border! as Border;
    expect(focusBorder.top.width, initialBorder.top.width);
    expect(focusBorder.top.color, isNot(initialBorder.top.color));
    expect(tester.getSize(find.byType(AppButton)), initialSize);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(activations, 1);
  });

  testWidgets('disabled button is inert and remains the same size', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        StandardSpec.theme,
        AppButton.label('Unavailable', onPressed: null),
      ),
    );
    final size = tester.getSize(find.byType(AppButton));
    await tester.tap(find.byType(AppButton));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(AppButton)), size);
  });

  testWidgets('Standard buttons use exact glass geometry without shadows', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(StandardSpec.theme, AppButton.label('Recipes', onPressed: () {})),
    );

    final secondary = _buttonDecoration(tester);
    final secondaryGradient = secondary.gradient! as LinearGradient;
    expect(tester.getSize(find.byKey(AppButton.materialKey)).height, 38);
    expect(
      secondaryGradient.colors.map((color) => color.toARGB32() >>> 24),
      <int>[70, 24, 22],
    );
    expect(
      (secondary.borderRadius! as BorderRadius).topLeft.x,
      StandardSpec.geometry.buttonRadius,
    );
    expect(secondary.boxShadow, isEmpty);
    expect(
      tester
          .widget<DefaultTextStyle>(
            find.descendant(
              of: find.byType(AppButton),
              matching: find.byType(DefaultTextStyle),
            ),
          )
          .style
          .fontSize,
      14,
    );

    await tester.pumpWidget(
      _host(
        StandardSpec.theme,
        AppButton.label('Build', role: AppButtonRole.primary, onPressed: () {}),
      ),
    );
    final primary = _buttonDecoration(tester);
    expect((primary.gradient! as LinearGradient).colors.toSet(), hasLength(1));
    expect(
      tester
          .widget<DefaultTextStyle>(
            find.descendant(
              of: find.byType(AppButton),
              matching: find.byType(DefaultTextStyle),
            ),
          )
          .style
          .color,
      const Color(0xFF03120E),
    );
    expect(primary.boxShadow, isEmpty);
  });

  testWidgets('Standard option pills use selected and inactive materials', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        StandardSpec.theme,
        AppButton.label(
          'FULL TARGET AMOUNT',
          role: AppButtonRole.optionPill,
          selected: true,
          onPressed: () {},
        ),
      ),
    );
    var decoration = _buttonDecoration(tester);
    expect((decoration.borderRadius! as BorderRadius).topLeft.x, 999);
    expect(
      (decoration.gradient! as LinearGradient).colors.map(
        (color) => color.toARGB32() >>> 24,
      ),
      <int>[96, 50, 32],
    );

    await tester.pumpWidget(
      _host(
        StandardSpec.theme,
        AppButton.label(
          'FULL TARGET AMOUNT',
          role: AppButtonRole.optionPill,
          onPressed: () {},
        ),
      ),
    );
    decoration = _buttonDecoration(tester);
    expect(
      (decoration.gradient! as LinearGradient).colors.map(
        (color) => color.toARGB32() >>> 24,
      ),
      <int>[44, 24, 14],
    );
  });

  testWidgets('Standard danger buttons retain destructive signaling', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        StandardSpec.theme,
        AppButton.label('Delete', role: AppButtonRole.danger, onPressed: () {}),
      ),
    );

    final decoration = _buttonDecoration(tester);
    final gradient = decoration.gradient! as LinearGradient;
    final border = decoration.border! as Border;
    expect(
      gradient.colors.first,
      StandardSpec.theme.palette.danger.withAlpha(164),
    );
    expect(border.top.color, StandardSpec.theme.palette.danger.withAlpha(214));
    expect(
      tester
          .widget<DefaultTextStyle>(
            find.descendant(
              of: find.byType(AppButton),
              matching: find.byType(DefaultTextStyle),
            ),
          )
          .style
          .color,
      const Color(0xFFFFF4D4),
    );
  });

  testWidgets('Ledger buttons use Avalonia construction defaults', (
    tester,
  ) async {
    Future<(Size, Size, AnimatedContainer, BoxDecoration)> renderLabel(
      String label,
      AppButtonRole role,
    ) async {
      await tester.pumpWidget(
        _host(
          IlluminatedLedgerSpec.theme,
          AppButton.label(label, role: role, onPressed: () {}),
        ),
      );
      final material = tester.widget<AnimatedContainer>(
        find.byKey(AppButton.materialKey),
      );
      return (
        tester.getSize(find.byType(AppButton)),
        tester.getSize(find.text(label)),
        material,
        material.decoration! as BoxDecoration,
      );
    }

    final save = await renderLabel('Save', AppButtonRole.primary);
    expect(save.$1.height, 38);
    expect(save.$1.width, closeTo(save.$2.width + 30, .01));
    expect(save.$1.width, lessThan(96));
    expect(
      save.$3.padding,
      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
    );
    expect((save.$4.border! as Border).top.color, const Color(0xFFB9903E));
    expect(save.$4.boxShadow, const <BoxShadow>[
      BoxShadow(color: Color(0x4A352516), blurRadius: 6, offset: Offset(0, 3)),
    ]);

    final delete = await renderLabel('Delete', AppButtonRole.secondary);
    expect(delete.$1.height, 38);
    expect(delete.$1.width, closeTo(delete.$2.width + 30, .01));
    expect(delete.$1.width, greaterThan(save.$1.width));
    expect(
      delete.$3.padding,
      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
    );
    expect((delete.$4.border! as Border).top.color, const Color(0x8A7A5B2A));
    expect(delete.$4.boxShadow, save.$4.boxShadow);

    await tester.pumpWidget(
      _host(
        IlluminatedLedgerSpec.theme,
        AppButton.icon(
          icon: const SizedBox.square(dimension: 16),
          semanticLabel: 'Blank icon action',
          onPressed: () {},
        ),
      ),
    );
    expect(tester.getSize(find.byType(AppButton)), const Size(46, 38));
    expect(
      tester
          .widget<AnimatedContainer>(find.byKey(AppButton.materialKey))
          .padding,
      const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
    );

    await tester.pumpWidget(
      _host(
        IlluminatedLedgerSpec.theme,
        AppButton.label(
          'Save',
          minimumSize: const Size(112, 44),
          padding: const EdgeInsets.all(3),
          onPressed: () {},
        ),
      ),
    );
    expect(tester.getSize(find.byType(AppButton)), const Size(112, 44));
    expect(
      tester
          .widget<AnimatedContainer>(find.byKey(AppButton.materialKey))
          .padding,
      const EdgeInsets.all(3),
    );
  });

  testWidgets('Sakura button material spans the complete control face', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        SakuraNightGardenSpec.theme,
        AppButton.label('Save', role: AppButtonRole.primary, onPressed: () {}),
      ),
    );

    final material = find.byKey(AppButton.materialKey);
    final detailedFace = find.descendant(
      of: material,
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is CustomPaint &&
            widget.painter is SakuraPlumMaterialPainter &&
            widget.foregroundPainter is SakuraSurfaceToolingPainter,
      ),
    );
    expect(detailedFace, findsOneWidget);
    final faceRect = tester.getRect(detailedFace);
    final expectedFaceRect = tester.getRect(material).deflate(1.15);
    expect(faceRect.left, closeTo(expectedFaceRect.left, .1));
    expect(faceRect.top, closeTo(expectedFaceRect.top, .1));
    expect(faceRect.right, closeTo(expectedFaceRect.right, .1));
    expect(faceRect.bottom, closeTo(expectedFaceRect.bottom, .1));
    expect(tester.widget<AnimatedContainer>(material).padding, EdgeInsets.zero);
    final labelRect = tester.getRect(find.text('Save'));
    final materialRect = tester.getRect(material);
    expect(labelRect.left, greaterThanOrEqualTo(materialRect.left + 14));
    expect(labelRect.right, lessThanOrEqualTo(materialRect.right - 14));
  });

  testWidgets('Ledger control buttons omit decorative baseline tooling', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        IlluminatedLedgerSpec.theme,
        AppButton.label(
          'New Recipe',
          role: AppButtonRole.primary,
          onPressed: () {},
        ),
      ),
    );

    expect(
      find.descendant(
        of: find.byType(AppButton),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is CustomPaint &&
              widget.foregroundPainter is LedgerButtonToolingPainter,
        ),
      ),
      findsNothing,
    );
  });

  testWidgets(
    'Ledger navigation can omit its ornament without losing selected colour',
    (tester) async {
      Future<void> pump({required bool showNavigationOrnament}) =>
          tester.pumpWidget(
            _host(
              IlluminatedLedgerSpec.theme,
              AppButton.label(
                'Selected category',
                role: AppButtonRole.navigation,
                selected: true,
                showNavigationOrnament: showNavigationOrnament,
                onPressed: () {},
              ),
            ),
          );

      Finder ribbon() => find.descendant(
        of: find.byType(AppButton),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is CustomPaint &&
              widget.foregroundPainter is LedgerNavigationRibbonPainter,
        ),
      );

      await pump(showNavigationOrnament: true);
      expect(ribbon(), findsOneWidget);

      await pump(showNavigationOrnament: false);
      expect(ribbon(), findsNothing);
      expect(
        (_buttonDecoration(tester).gradient! as LinearGradient).colors,
        const <Color>[Color(0xFF174D7E), Color(0xFF0A2744)],
      );
    },
  );

  testWidgets('surface roles preserve theme-owned silhouettes and tooling', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        IlluminatedLedgerSpec.theme,
        const AppSurface(
          role: AppSurfaceRole.card,
          child: SizedBox(
            width: 180,
            height: 80,
            child: Text('Unstyled manuscript value'),
          ),
        ),
      ),
    );
    final ledgerDecoration =
        tester.widget<Container>(find.byKey(AppSurface.materialKey)).decoration!
            as BoxDecoration;
    expect(
      (ledgerDecoration.borderRadius! as BorderRadius).topLeft.x,
      IlluminatedLedgerSpec.geometry.cardRadius,
    );
    expect(
      tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .any(
            (paint) => paint.foregroundPainter is LedgerSurfaceToolingPainter,
          ),
      isTrue,
    );
    expect(
      tester
          .widget<DefaultTextStyle>(
            find
                .descendant(
                  of: find.byType(AppSurface),
                  matching: find.byType(DefaultTextStyle),
                )
                .last,
          )
          .style
          .color,
      IlluminatedLedgerSpec.palette.text,
    );

    await tester.pumpWidget(
      _host(
        StandardSpec.theme,
        const AppSurface(
          role: AppSurfaceRole.card,
          child: SizedBox(width: 180, height: 80),
        ),
      ),
    );
    final standardDecoration =
        tester.widget<Container>(find.byKey(AppSurface.materialKey)).decoration!
            as BoxDecoration;
    expect(
      (standardDecoration.borderRadius! as BorderRadius).topLeft.x,
      StandardSpec.geometry.cardRadius,
    );
  });

  testWidgets('Ledger layout frames stay transparent and untooled', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        IlluminatedLedgerSpec.theme,
        const AppSurface(
          role: AppSurfaceRole.layout,
          padding: EdgeInsets.all(12),
          clipBehavior: Clip.antiAlias,
          child: SizedBox(width: 180, height: 80),
        ),
      ),
    );

    final material = tester.widget<Container>(
      find.byKey(AppSurface.materialKey),
    );
    expect(material.color, Colors.transparent);
    expect(material.decoration, isNull);
    expect(
      tester.widget<ClipRect>(find.byType(ClipRect)).clipBehavior,
      Clip.antiAlias,
    );
    expect(
      tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .where(
            (paint) => paint.foregroundPainter is LedgerSurfaceToolingPainter,
          ),
      isEmpty,
    );
    expect(
      tester.getSize(find.byKey(AppSurface.materialKey)),
      const Size(204, 104),
    );
  });

  testWidgets('Ledger shared surfaces use exact Avalonia materials', (
    tester,
  ) async {
    Future<BoxDecoration> render(
      AppSurfaceRole role, {
      AppSurfaceTone tone = AppSurfaceTone.neutral,
    }) async {
      await tester.pumpWidget(
        _host(
          IlluminatedLedgerSpec.theme,
          AppSurface(
            role: role,
            tone: tone,
            child: const SizedBox(width: 180, height: 80),
          ),
        ),
      );
      return tester
              .widget<Container>(find.byKey(AppSurface.materialKey))
              .decoration!
          as BoxDecoration;
    }

    var decoration = await render(AppSurfaceRole.commandBand);
    final commandGradient = decoration.gradient! as LinearGradient;
    expect(commandGradient.begin, Alignment.topLeft);
    expect(commandGradient.end, Alignment.bottomRight);
    expect(commandGradient.colors, const <Color>[
      Color(0xA3FFF7DF),
      Color(0x76E7D3AB),
    ]);
    expect((decoration.borderRadius! as BorderRadius).topLeft.x, 4);
    var border = decoration.border! as Border;
    expect(border.left, const BorderSide(color: Color(0x6FA77E2E)));
    expect(border.right, const BorderSide(color: Color(0x6FA77E2E)));
    expect(border.top, BorderSide.none);
    expect(border.bottom, BorderSide.none);
    expect(decoration.boxShadow, isNull);
    expect(
      tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .where(
            (paint) => paint.foregroundPainter is LedgerSurfaceToolingPainter,
          ),
      isEmpty,
    );

    decoration = await render(AppSurfaceRole.panel);
    expect(decoration.gradient, IlluminatedLedgerSpec.materials.surface);
    expect((decoration.borderRadius! as BorderRadius).topLeft.x, 5);
    border = decoration.border! as Border;
    expect(border.top, const BorderSide(color: Color(0x7EA77E2E)));
    expect(decoration.boxShadow, const <BoxShadow>[
      BoxShadow(color: Color(0x30352516), blurRadius: 18, offset: Offset(0, 5)),
    ]);
    expect(
      tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .where(
            (paint) => paint.foregroundPainter is LedgerSurfaceToolingPainter,
          ),
      isEmpty,
    );

    const tones = <AppSurfaceTone, (Color?, Color)>{
      AppSurfaceTone.neutral: (null, Color(0x7FA77E2E)),
      AppSurfaceTone.success: (Color(0xB8E3E2C9), Color(0x82647B35)),
      AppSurfaceTone.warning: (Color(0xB8EADBB7), Color(0x8EB9903E)),
      AppSurfaceTone.danger: (Color(0xC2E8CDC1), Color(0xA6A45648)),
      AppSurfaceTone.info: (Color(0xB8DFDAC7), Color(0x786B765A)),
    };
    for (final role in <AppSurfaceRole>[
      AppSurfaceRole.card,
      AppSurfaceRole.row,
    ]) {
      for (final entry in tones.entries) {
        decoration = await render(role, tone: entry.key);
        expect((decoration.borderRadius! as BorderRadius).topLeft.x, 2);
        expect(decoration.color, entry.value.$1);
        expect(
          decoration.gradient,
          entry.value.$1 == null
              ? IlluminatedLedgerSpec.materials.surfaceRaised
              : null,
        );
        expect(
          (decoration.border! as Border).top,
          BorderSide(color: entry.value.$2),
        );
        expect(decoration.boxShadow, const <BoxShadow>[
          BoxShadow(
            color: Color(0x40352516),
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ]);
      }
    }
  });

  testWidgets('Standard surface roles preserve backdrop-forward hierarchy', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        StandardSpec.theme,
        const AppSurface(
          role: AppSurfaceRole.card,
          tone: AppSurfaceTone.warning,
          child: SizedBox(width: 180, height: 80),
        ),
        standard: const StandardVisualSettings(
          backgroundId: 'hearth',
          accentHue: 28,
        ),
      ),
    );
    var decoration =
        tester.widget<Container>(find.byKey(AppSurface.materialKey)).decoration!
            as BoxDecoration;
    expect(decoration.color, const Color.fromARGB(148, 58, 37, 23));
    expect(decoration.border, isNull);
    expect(decoration.boxShadow, isNull);

    await tester.pumpWidget(
      _host(
        StandardSpec.theme,
        const AppSurface(
          role: AppSurfaceRole.row,
          tone: AppSurfaceTone.success,
          child: SizedBox(width: 180, height: 80),
        ),
        standard: const StandardVisualSettings(
          backgroundId: 'orrery',
          accentHue: 218,
        ),
      ),
    );
    decoration =
        tester.widget<Container>(find.byKey(AppSurface.materialKey)).decoration!
            as BoxDecoration;
    expect(decoration.color, const Color.fromARGB(148, 26, 39, 61));
    expect((decoration.border! as Border).top.color, const Color(0x4A7BCB83));
    expect(decoration.boxShadow, isNull);

    await tester.pumpWidget(
      _host(
        StandardSpec.theme,
        const AppSurface(
          role: AppSurfaceRole.layout,
          child: SizedBox(width: 180, height: 80),
        ),
      ),
    );
    decoration =
        tester.widget<Container>(find.byKey(AppSurface.materialKey)).decoration!
            as BoxDecoration;
    expect(decoration.color, Colors.transparent);
    expect(decoration.border, isNull);
    expect(
      tester.getSize(find.byKey(AppSurface.materialKey)),
      const Size(180, 80),
    );

    await tester.pumpWidget(
      _host(
        StandardSpec.theme,
        const AppSurface(
          role: AppSurfaceRole.panel,
          child: SizedBox(width: 180, height: 80),
        ),
      ),
    );
    decoration =
        tester.widget<Container>(find.byKey(AppSurface.materialKey)).decoration!
            as BoxDecoration;
    expect((decoration.gradient! as LinearGradient).colors, const <Color>[
      Color.fromARGB(44, 16, 48, 36),
      Color.fromARGB(10, 5, 19, 15),
      Color.fromARGB(16, 1, 6, 7),
    ]);
    expect((decoration.border! as Border).top.color, const Color(0x346B8B74));
  });

  testWidgets('section header applies each system structural treatment', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        IlluminatedLedgerSpec.theme,
        const MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.noScaling),
          child: SizedBox(
            width: 420,
            child: SectionHeader(
              title: 'Plan',
              meta: '2 left',
              trailing: SizedBox(
                key: ValueKey<String>('ledger-header-action'),
                width: 76,
                height: 38,
              ),
            ),
          ),
        ),
      ),
    );
    expect(
      tester.widget<Text>(find.byKey(SectionHeader.titleKey)).data,
      'PLAN',
    );
    expect(
      tester
          .widget<CustomPaint>(
            find.descendant(
              of: find.byKey(SectionHeader.ruleKey),
              matching: find.byType(CustomPaint),
            ),
          )
          .painter,
      isA<LedgerSectionRulePainter>(),
    );
    final coreRect = tester.getRect(find.byKey(SectionHeader.coreKey));
    final ruleRect = tester.getRect(find.byKey(SectionHeader.ruleKey));
    final actionRect = tester.getRect(
      find.byKey(const ValueKey<String>('ledger-header-action')),
    );
    expect(
      coreRect.height,
      40,
      reason:
          'title=${tester.getRect(find.byKey(SectionHeader.titleKey))}, '
          'rule=$ruleRect, action=$actionRect, core=$coreRect',
    );
    expect(ruleRect.height, 7);
    expect(actionRect.left - coreRect.right, 10);
    expect(ruleRect.left, coreRect.left);
    expect(ruleRect.right, coreRect.right);

    await tester.pumpWidget(
      _host(
        StandardSpec.theme,
        const SizedBox(
          width: 420,
          child: SectionHeader(title: 'Crafting plan'),
        ),
      ),
    );
    expect(
      tester.widget<Text>(find.byKey(SectionHeader.titleKey)).data,
      'Crafting plan',
    );
    final standardTitle = tester.widget<Text>(
      find.byKey(SectionHeader.titleKey),
    );
    expect(standardTitle.style!.fontFamily, 'Georgia');
    expect(standardTitle.style!.fontSize, 28);
    expect(standardTitle.style!.color, const Color(0xFFFFF1BB));
    expect(find.byKey(SectionHeader.ruleKey), findsNothing);
  });

  testWidgets('Standard brand and completion match retained silhouettes', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        StandardSpec.theme,
        Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const SizedBox(width: 210, child: AppBrandLockup()),
            AppCompletionControl(
              completed: false,
              semanticLabel: 'Done with recipe',
              onPressed: () {},
            ),
          ],
        ),
      ),
    );

    final brandTitle = tester.widget<Text>(find.text('Black Spirit\nLife'));
    expect(brandTitle.style!.fontSize, 34);
    expect(brandTitle.style!.height, 31 / 34);
    expect(brandTitle.style!.color, const Color(0xFFFFF8D4));
    final completion = tester.getSize(find.byType(AppCompletionControl));
    expect(completion, const Size.square(48));
    final completionGlyph = tester.widget<AppVectorGlyph>(
      find.descendant(
        of: find.byType(AppCompletionControl),
        matching: find.byType(AppVectorGlyph),
      ),
    );
    expect(completionGlyph.size, 23);
    expect(completionGlyph.tightBounds, isTrue);
    final completionDecoration = _buttonDecoration(tester);
    expect((completionDecoration.borderRadius! as BorderRadius).topLeft.x, 9);
    expect(
      tester
          .widget<DefaultTextStyle>(
            find.descendant(
              of: find.byType(AppCompletionControl),
              matching: find.byType(DefaultTextStyle),
            ),
          )
          .style
          .color,
      const Color(0xFF03120E),
    );
  });
}
