import 'dart:io';
import 'dart:ui' as ui;

import 'package:bdo_craft_planner_flutter/features/gathering/gathering_workspace.dart';
import 'package:bdo_craft_planner_flutter/visual/visual.dart';
import 'package:bdo_gathering_companion/src/domain/models.dart' as gathering;
import 'package:bdo_gathering_companion/src/ui/loot_panel.dart';
import 'package:bdo_gathering_companion/src/ui/theme.dart' as gathering;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/native_preview_fonts.dart';

const _capture = ValueKey('gathering-capture');
late gathering.Catalog _catalog;
late gathering.GameItem _stone, _log;

Widget host(
  Map<String, gathering.LootEntry> entries, {
  ThemeSpec? theme,
  double scale = 1,
  ValueChanged<bool>? onValid,
}) {
  final spec = theme ?? RetainedThemeRegistry.sakuraNightGarden;
  return RepaintBoundary(
    key: _capture,
    child: ThemeSpecScope(
      spec: spec,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: gathering.companionTheme(
          visualPalette: gatheringPaletteForTheme(spec),
        ),
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: Scaffold(
            backgroundColor: spec.palette.surface,
            body: Center(
              child: SizedBox(
                width: 590,
                child: LootPanel(
                  catalog: _catalog,
                  entries: entries,
                  suggestedItems: [_stone, _log],
                  onChanged: () {},
                  onValidityChanged: onValid,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

Map<String, gathering.LootEntry> fixture() => {
  _stone.id: gathering.LootEntry(
    id: _stone.id,
    name: _stone.name,
    icon: _stone.icon,
    start: 1000,
    remaining: 9000,
    sentAway: 4345,
  ),
  _log.id: gathering.LootEntry(
    id: _log.id,
    name: _log.name,
    icon: _log.icon,
    overrideTotal: 8760,
  ),
};

Finder total() => find.byKey(ValueKey('loot-total-${_stone.id}'));
Finder menu() => find.byKey(ValueKey('loot-actions-${_stone.id}'));

Future<void> openAction(WidgetTester tester, String label) async {
  await tester.tap(menu());
  await tester.pumpAndSettle();
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

Future<void> save(WidgetTester tester, String name) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_capture),
  );
  await tester.runAsync(() async {
    final image = await (boundary.debugLayer! as OffsetLayer).toImage(
      Offset.zero & boundary.size,
    );
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('build/gathering-dots-quiet-menus/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await loadNativePreviewFonts();
    _catalog = await gathering.Catalog.load();
    _stone = _catalog.items.firstWhere((i) => i.name == 'Rough Stone');
    _log = _catalog.items.firstWhere((i) => i.name == 'Log');
  });

  testWidgets('Displayed whole counts round-trip; legacy inputs stay valid', (
    tester,
  ) async {
    final entries = fixture();
    final before = entries[_stone.id]!.toJson();
    final validity = <bool>[];
    await tester.pumpWidget(host(entries, onValid: validity.add));
    await tester.pumpAndSettle();
    expect(
      entries[_stone.id]!.toJson(),
      before,
      reason: 'Formatting does not alter stored observations',
    );
    for (final value in [0, 1, 999, 1000, 12345, 1234567, 999999999999]) {
      final display = gathering.countText(value);
      expect(display.contains(','), isFalse);
      await tester.enterText(total(), display);
      await tester.pump();
      expect(entries[_stone.id]!.rawTotal, value);
      expect(find.text('Whole number'), findsNothing);
      expect(validity.last, isTrue);
    }
    for (final input in ['12345', '12.345', '12,345', '12 345', ' 12.345 ']) {
      await tester.enterText(total(), input);
      await tester.pump();
      expect(entries[_stone.id]!.rawTotal, 12345);
      expect(validity.last, isTrue);
    }
    expect(gathering.countText(1234567), '1.234.567');
    expect(gathering.countText(-12345), '-12.345');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Fractions, malformed grouping and overflow cannot change loot', (
    tester,
  ) async {
    final entries = fixture();
    final validity = <bool>[];
    await tester.pumpWidget(host(entries, onValid: validity.add));
    await tester.pumpAndSettle();
    for (final bad in [
      '12.34',
      '1.23.456',
      '1..234',
      '1.234,567',
      '1,234.567',
      '1234.567',
      '12,34',
      '1 23',
      '-1',
      '1e3',
      'NaN',
      'Infinity',
      '1000000000000',
      '1.000.000.000.000',
    ]) {
      await tester.enterText(total(), '12.345');
      await tester.pump();
      final before = entries[_stone.id]!.toJson();
      await tester.enterText(total(), bad);
      await tester.pump();
      expect(find.text('Whole number'), findsOneWidget, reason: bad);
      expect(validity.last, isFalse, reason: bad);
      expect(entries[_stone.id]!.toJson(), before, reason: bad);
    }
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Maid deposit and observation editor accept dotted quantities', (
    tester,
  ) async {
    final entries = fixture();
    await tester.pumpWidget(host(entries));
    await tester.pumpAndSettle();
    await openAction(tester, 'Add maid deposit');
    await tester.enterText(find.byKey(const ValueKey('maid-quantity')), '0');
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('maid-add')))
          .onPressed,
      isNull,
    );
    await tester.enterText(
      find.byKey(const ValueKey('maid-quantity')),
      '1.000',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('maid-add')));
    await tester.pumpAndSettle();
    expect(entries[_stone.id]!.sentAway, 5345);
    expect(entries[_stone.id]!.rawTotal, 13345);
    expect(tester.widget<TextField>(total()).controller!.text, '13.345');
    await openAction(tester, 'Inventory details');
    Finder field(String label) => find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.labelText == label,
    );
    expect(
      tester.widget<TextField>(field('Starting inventory')).controller!.text,
      '1.000',
    );
    expect(
      tester
          .widget<TextField>(field('Final inventory / still in your bag'))
          .controller!
          .text,
      '9.000',
    );
    await tester.enterText(field('Starting inventory'), '2.000');
    await tester.enterText(
      field('Final inventory / still in your bag'),
      '10.000',
    );
    await tester.enterText(field('Maid deposits / sent away'), '6.000');
    await tester.pump();
    expect(find.text('Session total: 14.000'), findsOneWidget);
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();
    expect(entries[_stone.id]!.rawTotal, 14000);
    expect(entries[_stone.id]!.start, 2000);
    expect(tester.widget<TextField>(total()).controller!.text, '14.000');
    await tester.pumpWidget(const SizedBox());
  });

  for (final spec in RetainedThemeRegistry.themes) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'Quiet loot controls retain alignment and actions ${spec.id} $scale',
        (tester) async {
          tester.view.physicalSize = const Size(780, 460);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          final semantics = tester.ensureSemantics();
          final entries = fixture();
          final before = entries[_stone.id]!.toJson();
          await tester.pumpWidget(host(entries, theme: spec, scale: scale));
          await tester.pumpAndSettle();
          await tester.runAsync(() async {
            for (final image in tester.widgetList<Image>(find.byType(Image))) {
              await precacheImage(
                image.image,
                tester.element(find.byKey(_capture)),
              );
            }
          });
          await tester.pumpAndSettle();
          final second = find.byKey(ValueKey('loot-total-${_log.id}'));
          expect(tester.getRect(total()).left, tester.getRect(second).left);
          expect(tester.getRect(total()).right, tester.getRect(second).right);
          expect(tester.getCenter(total()).dy, tester.getCenter(menu()).dy);
          final editable = tester
              .state<EditableTextState>(
                find.descendant(
                  of: total(),
                  matching: find.byType(EditableText),
                ),
              )
              .renderEditable;
          expect(
            (editable.offset as ScrollPosition).maxScrollExtent,
            0,
            reason: 'The displayed total fits without horizontal clipping.',
          );
          expect(
            tester.getRect(total()).right,
            lessThanOrEqualTo(tester.getRect(menu()).left),
          );
          expect(
            find.bySemanticsLabel('Options for Rough Stone'),
            findsOneWidget,
          );
          final mouse = await tester.createGesture(
            kind: PointerDeviceKind.mouse,
          );
          await mouse.addPointer(location: Offset.zero);
          for (final target in [menu(), total(), find.text('Rough Stone')]) {
            await mouse.moveTo(tester.getCenter(target));
            await tester.pump(const Duration(seconds: 2));
            // Flutter retains an inert Tooltip for PopupMenuButton's explicit
            // empty hint. Only nonempty hints can create visual hover content.
            expect(
              tester
                  .widgetList<Tooltip>(
                    find.byType(Tooltip, skipOffstage: false),
                  )
                  .where(
                    (hint) =>
                        (hint.message ?? hint.richMessage?.toPlainText() ?? '')
                            .isNotEmpty,
                  ),
              isEmpty,
            );
            expect(find.text('Options for Rough Stone'), findsNothing);
          }
          await mouse.moveTo(tester.getCenter(menu()));
          await tester.pumpAndSettle();
          await save(tester, '${spec.id}-$scale');
          expect(entries[_stone.id]!.toJson(), before);
          await mouse.removePointer();
          await tester.tap(menu());
          await tester.pumpAndSettle();
          expect(find.text('Add maid deposit'), findsOneWidget);
          expect(find.text('Inventory details'), findsOneWidget);
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await tester.pumpAndSettle();
          expect(find.text('Add maid deposit'), findsNothing);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
          semantics.dispose();
        },
      );
    }
  }
}
