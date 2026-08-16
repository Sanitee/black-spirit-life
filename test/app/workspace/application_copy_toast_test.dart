import 'package:bdo_craft_planner_flutter/app/workspace/application_copy_toast.dart';
import 'package:bdo_craft_planner_flutter/visual/illuminated_ledger/ledger_ornament_painters.dart';
import 'package:bdo_craft_planner_flutter/visual/visual.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/application_test_harness.dart';

void main() {
  testWidgets(
    'Standard copy toast uses the retained pill and content position',
    (tester) async {
      configureApplicationTestSurface(tester, const Size(1500, 940));
      const settings = StandardVisualSettings(
        backgroundId: 'greenhouse',
        accentHue: 158,
      );
      await _pumpToast(tester, spec: StandardSpec.theme, settings: settings);

      final surface = find.byKey(ApplicationCopyToastKeys.surface);
      final rect = tester.getRect(surface);
      expect(rect.top, 52);
      expect(rect.center.dx, 750);
      expect(find.text('Copied Apple'), findsOneWidget);
      expect(find.text('Copied “Apple”.'), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
      expect(find.byType(Icon), findsNothing);
      expect(find.byKey(ApplicationCopyToastKeys.ledgerSeal), findsNothing);
      expect(surface.hitTestable(), findsNothing);

      final glyph = tester.widget<AppVectorGlyph>(find.byType(AppVectorGlyph));
      expect(glyph.name, 'check');
      expect(glyph.size, 14);
      expect(glyph.color, const Color(0xFFEFFFF0));

      final container = tester.widget<Container>(surface);
      expect(
        container.padding,
        const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
      );
      final decoration = container.decoration! as BoxDecoration;
      expect(decoration.borderRadius, BorderRadius.circular(999));
      expect(decoration.gradient, StandardSpec.accentGlass(158, topAlpha: 156));
      final border = decoration.border! as Border;
      expect(border.top.width, 1);
      expect(border.top.color, StandardSpec.accentBrush(158, alpha: .72));
      expect(decoration.boxShadow, const <BoxShadow>[
        BoxShadow(
          color: Color(0x66000000),
          blurRadius: 24,
          offset: Offset(0, 8),
        ),
      ]);

      final label = tester.widget<Text>(find.text('Copied Apple'));
      expect(label.style?.fontFamily, 'Segoe UI');
      expect(label.style?.fontSize, 13);
      expect(label.style?.fontWeight, FontWeight.w700);
      expect(label.style?.color, const Color(0xFFFFF7D8));
    },
  );

  testWidgets('Ledger copy toast uses lapis material inside the title strip', (
    tester,
  ) async {
    configureApplicationTestSurface(tester, const Size(1200, 752));
    await _pumpToast(
      tester,
      spec: IlluminatedLedgerSpec.theme,
      settings: const StandardVisualSettings(
        backgroundId: IlluminatedLedgerSpec.backgroundId,
      ),
    );

    final surface = find.byKey(ApplicationCopyToastKeys.surface);
    final rect = tester.getRect(surface);
    expect(rect.center.dx, 600);
    expect(rect.center.dy, 20);
    expect(find.text('Copied Apple'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    expect(find.byType(Icon), findsNothing);

    final seal = find.byKey(ApplicationCopyToastKeys.ledgerSeal);
    expect(seal, findsOneWidget);
    expect(tester.getSize(seal), const Size.square(24));
    final sealPaint = tester.widget<CustomPaint>(
      find.descendant(
        of: seal,
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is CustomPaint && widget.painter is LedgerWaxSealPainter,
        ),
      ),
    );
    expect(sealPaint.painter, isA<LedgerWaxSealPainter>());
    final glyph = tester.widget<AppVectorGlyph>(find.byType(AppVectorGlyph));
    expect(glyph.name, 'check');
    expect(glyph.size, 10.08);
    expect(glyph.color, const Color(0xFFFFF1BD));
    expect(glyph.tightBounds, isTrue);
    final labelRect = tester.getRect(find.text('Copied Apple'));
    expect(rect.height, 39);
    expect(rect.width - labelRect.width, closeTo(66, .01));
    final container = tester.widget<Container>(surface);
    expect(
      container.padding,
      const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
    );
    final decoration = container.decoration! as BoxDecoration;
    expect(decoration.borderRadius, BorderRadius.circular(2));
    final gradient = decoration.gradient! as LinearGradient;
    expect(gradient.begin, Alignment.topLeft);
    expect(gradient.end, Alignment.bottomRight);
    expect(gradient.colors, const <Color>[
      Color(0xFF174D7E),
      Color(0xFF0A2744),
    ]);
    final border = decoration.border! as Border;
    expect(border.top.width, 1.5);
    expect(border.top.color, const Color(0xFFD2B15A));
    expect(decoration.boxShadow, const <BoxShadow>[
      BoxShadow(color: Color(0x69352516), blurRadius: 9, offset: Offset(0, 3)),
    ]);

    final label = tester.widget<Text>(find.text('Copied Apple'));
    expect(label.style?.fontFamily, 'Georgia');
    expect(label.style?.fontSize, 13);
    expect(label.style?.fontWeight, FontWeight.w700);
    expect(label.style?.color, const Color(0xFFF7EAC7));
  });
}

Future<void> _pumpToast(
  WidgetTester tester, {
  required ThemeSpec spec,
  required StandardVisualSettings settings,
}) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(
      body: ApplicationCopyToastOverlay(
        message: 'Copied Apple',
        spec: spec,
        standardSettings: settings,
      ),
    ),
  ),
);
