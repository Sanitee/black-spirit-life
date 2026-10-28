import 'dart:io';
import 'dart:ui' as ui;

import 'package:bdo_gathering_companion/domain/models.dart';
import 'package:bdo_gathering_companion/src/ui/buff_picker.dart';
import 'package:bdo_gathering_companion/src/ui/theme.dart';
import 'package:bdo_gathering_companion/src/ui/visual_palette.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _captureKey = ValueKey('dialog-clarity-capture');
const _triggerKey = ValueKey('open-buff-details');
const _lightPalette = CompanionVisualPalette(
  brightness: Brightness.light,
  canvas: Color(0xFFECE1C4),
  canvasDeep: Color(0xFFD7C9A8),
  surface: Color(0xFFF1E8D3),
  raised: Color(0xFFFFF8E8),
  inset: Color(0xFFE2D3B1),
  ink: Color(0xFF262C32),
  muted: Color(0xFF645C50),
  accent: Color(0xFF264D62),
  accentBright: Color(0xFF3C6A80),
  gold: Color(0xFF87601F),
  edge: Color(0xFF92784D),
  rim: Color(0xFFFFFDF5),
  positive: Color(0xFF315E42),
  warning: Color(0xFF87601F),
  danger: Color(0xFF933A36),
);

Finder _key(String value) => find.byKey(ValueKey(value));
Finder _dialog(Buff buff) => _key('buff-pinned-card-${buff.id}');
Finder _header(Buff buff) => _key('buff-details-header-${buff.id}');
Finder _close(Buff buff) => _key('buff-details-close-${buff.id}');

Future<void> _loadFonts() async {
  if (!Platform.isWindows) return;
  final windows = Platform.environment['WINDIR'] ?? r'C:\Windows';
  var flutter = File(Platform.resolvedExecutable).parent;
  while (!Directory(
    '${flutter.path}/bin/cache/artifacts/material_fonts',
  ).existsSync()) {
    final parent = flutter.parent;
    if (parent.path == flutter.path) throw StateError('Flutter fonts missing.');
    flutter = parent;
  }
  for (final entry in <String, List<String>>{
    'Segoe UI': ['$windows/Fonts/segoeui.ttf', '$windows/Fonts/seguisb.ttf'],
    'Georgia': ['$windows/Fonts/georgia.ttf', '$windows/Fonts/georgiab.ttf'],
    'Roboto': [
      '${flutter.path}/bin/cache/artifacts/material_fonts/roboto-regular.ttf',
    ],
    'MaterialIcons': [
      '${flutter.path}/bin/cache/artifacts/material_fonts/materialicons-regular.otf',
    ],
  }.entries) {
    final loader = FontLoader(entry.key);
    for (final path in entry.value) {
      loader.addFont(File(path).readAsBytes().then(ByteData.sublistView));
    }
    await loader.load();
  }
}

Future<FocusNode> _open(
  WidgetTester tester,
  Catalog catalog,
  Buff buff, {
  double scale = 1,
  CompanionVisualPalette palette = CompanionVisualPalette.fieldDesk,
  Size size = const Size(1200, 752),
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
  final triggerFocus = FocusNode();
  addTearDown(triggerFocus.dispose);
  await tester.pumpWidget(
    RepaintBoundary(
      key: _captureKey,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: companionTheme(opacityPercent: 60, visualPalette: palette),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(
          backgroundColor: palette.canvasDeep,
          body: Builder(
            builder: (context) => Align(
              alignment: Alignment.topLeft,
              child: TextButton(
                key: _triggerKey,
                focusNode: triggerFocus,
                onPressed: () => showBuffInfo(context, catalog, buff),
                child: const Text('Item details'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  triggerFocus.requestFocus();
  await tester.pump();
  expect(triggerFocus.hasFocus, isTrue);
  await tester.tap(find.byKey(_triggerKey));
  await tester.pumpAndSettle();
  for (final element in find.byType(Image).evaluate()) {
    await tester.runAsync(
      () => precacheImage((element.widget as Image).image, element),
    );
  }
  await tester.pumpAndSettle();
  expect(_dialog(buff), findsOneWidget);
  return triggerFocus;
}

void _assertHeader(WidgetTester tester, Buff buff) {
  final header = tester.getRect(_header(buff));
  final close = tester.getRect(_close(buff));
  final title = find.descendant(
    of: _header(buff),
    matching: find.text(buff.name),
  );
  final textRect = tester.getRect(title);
  final surface = find
      .ancestor(of: _header(buff), matching: find.byType(Material))
      .first;
  final bounds = tester.getRect(surface);
  final viewport =
      Offset.zero & (tester.view.physicalSize / tester.view.devicePixelRatio);
  expect(bounds.left, greaterThanOrEqualTo(viewport.left + 16));
  expect(bounds.top, greaterThanOrEqualTo(viewport.top + 16));
  expect(bounds.right, lessThanOrEqualTo(viewport.right - 16));
  expect(bounds.bottom, lessThanOrEqualTo(viewport.bottom - 16));
  expect(bounds.width, lessThanOrEqualTo(400));
  expect(close.width, closeTo(34, .01));
  expect(close.height, closeTo(34, .01));
  expect(close.top, closeTo(header.top, .01));
  expect(close.right, closeTo(header.right, .01));
  expect(textRect.right, lessThanOrEqualTo(close.left - 8));
  expect(_close(buff).hitTestable(), findsOneWidget);
  final text = tester.widget<Text>(title);
  expect(text.maxLines, isNull);
  expect(text.overflow, isNot(TextOverflow.ellipsis));
  expect(
    tester.renderObject<RenderParagraph>(title).didExceedMaxLines,
    isFalse,
  );
  final icon = tester.widget<GameIcon>(
    find.descendant(of: _header(buff), matching: find.byType(GameIcon)),
  );
  expect(icon.path, buff.icon);
  expect(icon.grade, buff.grade);
  expect(icon.size, 36);
  expect(tester.widget<AlertDialog>(_dialog(buff)).actions, isNull);
  expect(find.text('Close'), findsNothing);
  final material = tester.widget<Material>(surface);
  expect(material.color!.a, greaterThanOrEqualTo(.98));
  expect(tester.takeException(), isNull);
}

Future<void> _capture(WidgetTester tester, String name) async {
  final root = Platform.environment['DIALOG_CLARITY_CAPTURE_DIR'];
  if (root == null || root.isEmpty) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_captureKey),
  );
  await tester.runAsync(() async {
    await Directory(root).create(recursive: true);
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
    await File('$root/dialog-clarity-gathering-$name.png').writeAsBytes(
      bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
    );
    image.dispose();
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Catalog catalog;
  Buff buff(String id) => catalog.buffs.firstWhere((buff) => buff.id == id);

  setUpAll(() async {
    catalog = await Catalog.load();
    await _loadFonts();
  });

  testWidgets('header close is accessible and preserves effects and focus', (
    tester,
  ) async {
    final item = buff('buff-735');
    final semantics = tester.ensureSemantics();
    try {
      final triggerFocus = await _open(tester, catalog, item);
      _assertHeader(tester, item);
      expect(find.byTooltip('Close'), findsOneWidget);
      final accessibleClose = find.semantics.byPredicate(
        (node) =>
            node.tooltip == 'Close' &&
            node.flagsCollection.isButton &&
            node.flagsCollection.isEnabled == ui.Tristate.isTrue &&
            node.getSemanticsData().hasAction(ui.SemanticsAction.tap),
      );
      expect(accessibleClose.evaluate(), hasLength(1));
      expect(find.text('Effects'), findsOneWidget);
      for (final effect in item.effects.entries) {
        expect(find.text(catalog.statLabel(effect.key)), findsOneWidget);
        expect(
          find.text(effectText(catalog, effect.key, effect.value)),
          findsWidgets,
        );
      }
      expect(find.text('Duration  20 min'), findsOneWidget);
      await _capture(tester, 'perfume-dark-text100');
      tester.semantics.tap(accessibleClose);
      await tester.pumpAndSettle();
      expect(_dialog(item), findsNothing);
      expect(triggerFocus.hasFocus, isTrue);
      expect(tester.takeException(), isNull);
    } finally {
      semantics.dispose();
    }
  });

  for (final method in ['Escape', 'backdrop']) {
    testWidgets('$method dismisses details and restores trigger focus', (
      tester,
    ) async {
      final item = buff('buff-735');
      final triggerFocus = await _open(tester, catalog, item);
      if (method == 'Escape') {
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      } else {
        await tester.tapAt(const Offset(8, 8));
      }
      await tester.pumpAndSettle();
      expect(_dialog(item), findsNothing);
      expect(triggerFocus.hasFocus, isTrue);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Lightstone content scrolls without moving header close', (
    tester,
  ) async {
    final item = buff('buff-yawning-hedgehog');
    await _open(tester, catalog, item, scale: 2);
    _assertHeader(tester, item);
    for (final line in const [
      'Gathering Item Drop Rate +10%',
      'Gathering EXP +10%',
      'Gathering Mastery +20',
      'Gathering Speed +1.',
    ]) {
      expect(find.text(line), findsOneWidget);
    }
    expect(find.text('Lightstones'), findsOneWidget);
    for (final id in ['764011', '764003', '764001', '766101']) {
      expect(_key('buff-component-$id'), findsOneWidget);
    }
    expect(find.text('How to get'), findsNothing);
    expect(find.textContaining('Equip Flora:'), findsNothing);
    final initialClose = tester.getRect(_close(item));
    await tester.ensureVisible(_key('buff-component-766101'));
    await tester.pumpAndSettle();
    expect(_key('buff-component-766101').hitTestable(), findsOneWidget);
    expect(tester.getRect(_close(item)), initialClose);
    expect(_close(item).hitTestable(), findsOneWidget);
    await _capture(tester, 'lightstones-dark-text200');
    await tester.tap(_close(item));
    await tester.pumpAndSettle();
    expect(_dialog(item), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('acquisition ingredients remain individual readable rows', (
    tester,
  ) async {
    final item = buff('buff-721032');
    await _open(tester, catalog, item);
    _assertHeader(tester, item);
    expect(find.text('Simple Alchemy'), findsOneWidget);
    for (final name in ['Rough Stone', 'Log or Timber', 'Powder of Flame']) {
      expect(_key('buff-obtain-item-$name'), findsOneWidget);
      expect(find.text(name), findsOneWidget);
    }
    expect(find.text('×5'), findsNWidgets(3));
    await _capture(tester, 'bonfire-dark-text100');
    expect(tester.takeException(), isNull);
  });

  for (final entry in {
    'dark': CompanionVisualPalette.fieldDesk,
    'light': _lightPalette,
  }.entries) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('${entry.key} long name wraps safely at ${scale * 100}%', (
        tester,
      ) async {
        final item = buff('buff-790781');
        await _open(tester, catalog, item, palette: entry.value, scale: scale);
        _assertHeader(tester, item);
        expect(find.text('Effects'), findsOneWidget);
        await _capture(
          tester,
          'long-name-${entry.key}-text${(scale * 100).round()}',
        );
        await tester.tap(_close(item));
        await tester.pumpAndSettle();
        expect(_dialog(item), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
