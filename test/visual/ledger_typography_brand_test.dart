import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/features/shell/shell.dart';
import 'package:bdo_craft_planner_flutter/visual/components/app_brand_lockup.dart';
import 'package:bdo_craft_planner_flutter/visual/foundations/theme_spec.dart';
import 'package:bdo_craft_planner_flutter/visual/illuminated_ledger/ledger_spec.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const spec = IlluminatedLedgerSpec.theme;

  test('Ledger typography uses Avalonia roman metadata and button scale', () {
    expect(spec.typography.meta.fontStyle, FontStyle.normal);
    expect(spec.typography.button.fontSize, 14);
    expect(spec.typography.button.letterSpacing, isNull);
  });

  testWidgets('Ledger brand retains its product lockup without a theme name', (
    tester,
  ) async {
    await tester.pumpWidget(_brandHost(const AppBrandLockup()));

    expect(
      tester
          .widget<Padding>(find.byKey(AppBrandLockup.ledgerOuterSpacingKey))
          .padding,
      const EdgeInsets.fromLTRB(7, 10, 6, 5),
    );
    expect(
      tester
          .widget<Padding>(find.byKey(AppBrandLockup.ledgerInnerSpacingKey))
          .padding,
      const EdgeInsets.fromLTRB(5, 6, 5, 5),
    );
    expect(
      tester.getSize(find.byKey(AppBrandLockup.ledgerDropCapKey)),
      const Size(52, 86),
    );

    final eyebrow = tester.widget<Text>(find.text('BLACK DESERT'));
    expect(eyebrow.style!.fontFamily, 'Georgia');
    expect(eyebrow.style!.fontSize, 9.5);
    expect(eyebrow.style!.fontWeight, FontWeight.w700);
    expect(eyebrow.style!.color, const Color(0xFF6F501F));

    final title = tester.widget<Text>(
      find.byKey(AppBrandLockup.ledgerTitleKey),
    );
    expect(title.data, 'BLACK SPIRIT\nLIFE');
    expect(title.style!.fontSize, 17);
    expect(title.style!.height, 19 / 17);
    expect(title.style!.fontWeight, FontWeight.w700);
    expect(title.style!.color, const Color(0xFF352516));

    expect(find.text('ILLUMINATED LEDGER'), findsNothing);
    final divider = find.byKey(AppBrandLockup.ledgerDividerKey);
    expect(divider, findsOneWidget);
    expect(tester.getSize(divider).height, 1);
  });

  testWidgets('Ledger sidebar navigation uses the 16 px Georgia label', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1500, 940);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      _brandHost(
        WorkspaceShell(
          mode: CraftMode.alchemy,
          destination: ShellDestination.planner,
          onModeChanged: (_) {},
          onDestinationChanged: (_) {},
          child: const SizedBox.expand(),
        ),
      ),
    );

    final planner = tester.widget<Text>(
      find.descendant(
        of: find.byKey(const ValueKey<String>('S07')),
        matching: find.text('Planner'),
      ),
    );
    expect(planner.style!.fontFamily, 'Georgia');
    expect(planner.style!.fontSize, 16);
    expect(planner.style!.fontWeight, FontWeight.w700);
    expect(planner.style!.letterSpacing, isNull);
    expect(tester.takeException(), isNull);
  });
}

Widget _brandHost(Widget child) => MaterialApp(
  theme: IlluminatedLedgerSpec.theme.materialTheme(),
  home: ThemeSpecScope(
    spec: IlluminatedLedgerSpec.theme,
    child: Scaffold(body: child),
  ),
);
