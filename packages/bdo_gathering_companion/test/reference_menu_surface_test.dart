import 'dart:io';
import 'dart:ui' as ui;

import 'package:bdo_gathering_companion/domain/models.dart';
import 'package:bdo_gathering_companion/src/ui/theme.dart';
import 'package:bdo_gathering_companion/src/widgets/spot_media_gallery.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _routeAsset = 'assets/rotations/bunnygirl_edania_thuja_rotation.png';
const _captureKey = ValueKey('reference-menu-navigator-capture');
Finder _key(String key) => find.byKey(ValueKey(key));

Future<void> _fonts() async {
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

Future<void> _pumpMenuHost(
  WidgetTester tester,
  List<SpotMedia> media, {
  int opacity = 0,
  Size size = const Size(1200, 752),
  double scale = 1,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  await tester.pumpWidget(
    RepaintBoundary(
      key: _captureKey,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: companionTheme(opacityPercent: opacity),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(
          body: Stack(
            children: [
              Positioned.fill(
                child: Image.asset(
                  _routeAsset,
                  package: 'bdo_gathering_companion',
                  fit: BoxFit.cover,
                ),
              ),
              Positioned(
                top: 72,
                left: 24,
                right: size.width > 800 ? 520 : 24,
                child: TickerMode(
                  enabled: false,
                  child: SpotMediaGallery(media: media, height: 380),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  for (final element in find.byType(Image).evaluate()) {
    await tester.runAsync(
      () => precacheImage((element.widget as Image).image, element),
    );
  }
  await tester.pumpAndSettle();
}

Future<void> _capture(WidgetTester tester, String name) async {
  final root = Platform.environment['REFERENCE_MENU_CAPTURE_DIR'];
  if (root == null) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_captureKey),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
    await File('$root/$name.png').writeAsBytes(
      bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
    );
    image.dispose();
  });
}

Finder _option(int index) => _key('spot-reference-option-$index');

Material _menuMaterial(WidgetTester tester) => tester.widget<Material>(
  find.ancestor(of: _option(0), matching: find.byType(Material)).first,
);

Future<void> _open(WidgetTester tester) async {
  await tester.tap(_key('spot-media-reference'));
  await tester.pumpAndSettle();
  expect(_option(0), findsOneWidget);
}

void _assertReadable(WidgetTester tester, List<SpotMedia> sorted) {
  final material = _menuMaterial(tester);
  expect(material.color, isNotNull);
  expect(material.color!.a, greaterThanOrEqualTo(.98));
  expect(material.surfaceTintColor, Colors.transparent);
  for (var i = 0; i < sorted.length; i++) {
    final text = find.descendant(
      of: _option(i),
      matching: find.text(sorted[i].title),
    );
    expect(text, findsOneWidget);
    final widget = tester.widget<Text>(text);
    final style = DefaultTextStyle.of(
      tester.element(text),
    ).style.merge(widget.style);
    expect(style.color?.a, 1);
    expect(widget.overflow, isNot(TextOverflow.ellipsis));
    final paragraph = tester.renderObject<RenderParagraph>(text);
    expect(paragraph.didExceedMaxLines, isFalse, reason: sorted[i].title);
  }
}

void _assertBelowTrigger(WidgetTester tester) {
  final trigger = tester.getRect(_key('spot-media-reference'));
  final menu = tester.getRect(
    find.ancestor(of: _option(0), matching: find.byType(Material)).first,
  );
  expect(menu.top, greaterThanOrEqualTo(trigger.bottom));
  expect(menu.bottom, lessThanOrEqualTo(tester.view.physicalSize.height));
  expect(menu.left, greaterThanOrEqualTo(0));
  expect(menu.right, lessThanOrEqualTo(tester.view.physicalSize.width));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late List<SpotMedia> media;
  setUpAll(() async {
    final catalog = await Catalog.load();
    media = catalog.spots
        .singleWhere((spot) => spot.id == 'edania-thuja-bunnygirl')
        .media;
    expect(media, hasLength(5));
    await _fonts();
  });

  for (final opacity in [0, 60, 100]) {
    testWidgets(
      'reference menu stays readable below first and last selection at opacity$opacity',
      (tester) async {
        addTearDown(tester.view.reset);
        final sorted = orderSpotMediaForDisplay(media);
        await _pumpMenuHost(tester, media, opacity: opacity);
        final mapContext = tester.element(_key('spot-media-gallery'));
        final originalPanel = mapContext.glass.panel;
        final trigger = tester.widget<PopupMenuButton<String>>(
          _key('spot-media-reference'),
        );
        expect(trigger.position, PopupMenuPosition.under);
        expect(trigger.initialValue, isNull);
        await _open(tester);
        _assertReadable(tester, sorted);
        _assertBelowTrigger(tester);
        expect(
          find.descendant(of: _option(0), matching: find.byIcon(Icons.check)),
          findsOneWidget,
        );
        await _capture(tester, 'reference-menu-opacity$opacity-normal-first');
        expect(
          mapContext.glass.panel,
          originalPanel,
          reason:
              'The map opacity must not be replaced by the popup reading surface.',
        );
        await tester.tap(_option(sorted.length - 1));
        await tester.pumpAndSettle();
        expect(_option(0), findsNothing);
        expect(
          tester.widget<Text>(_key('spot-media-title')).data,
          sorted.last.title,
        );
        expect(
          tester.widget<Text>(_key('inline-spot-reference-position')).data,
          '5/5',
        );
        await _open(tester);
        _assertReadable(tester, sorted);
        _assertBelowTrigger(tester);
        expect(
          find.descendant(
            of: _option(sorted.length - 1),
            matching: find.byIcon(Icons.check),
          ),
          findsOneWidget,
        );
        await _capture(tester, 'reference-menu-opacity$opacity-normal-last');
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(_option(0), findsNothing);
        expect(
          tester.widget<Text>(_key('spot-media-title')).data,
          sorted.last.title,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets(
    'reference title opens by keyboard and Escape leaves selection unchanged',
    (tester) async {
      addTearDown(tester.view.reset);
      await _pumpMenuHost(tester, media, opacity: 60);
      final title = tester.widget<Text>(_key('spot-media-title')).data;
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(_option(0), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(_option(0), findsNothing);
      expect(tester.widget<Text>(_key('spot-media-title')).data, title);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final scenario in [
    (name: 'compact', size: const Size(520, 560), scale: 1.0),
    (name: 'enlarged200', size: const Size(760, 752), scale: 2.0),
    (name: 'short-enlarged200', size: const Size(420, 360), scale: 2.0),
  ]) {
    testWidgets(
      'all full reference names stay accessible in ${scenario.name}',
      (tester) async {
        addTearDown(tester.view.reset);
        final sorted = orderSpotMediaForDisplay(media);
        await _pumpMenuHost(
          tester,
          media,
          size: scenario.size,
          scale: scenario.scale,
        );
        await _open(tester);
        _assertReadable(tester, sorted);
        final scrollable = find
            .ancestor(of: _option(0), matching: find.byType(Scrollable))
            .first;
        if (scenario.name.startsWith('short-')) {
          expect(
            tester.state<ScrollableState>(scrollable).position.maxScrollExtent,
            greaterThan(0),
          );
        }
        await _capture(tester, 'reference-menu-${scenario.name}-first');
        for (var i = 0; i < sorted.length; i++) {
          await tester.ensureVisible(_option(i));
          await tester.pumpAndSettle();
          expect(
            _option(i).hitTestable(),
            findsOneWidget,
            reason: sorted[i].title,
          );
        }
        await _capture(tester, 'reference-menu-${scenario.name}-last');
        await tester.tap(_option(sorted.length - 1));
        await tester.pumpAndSettle();
        expect(
          tester.widget<Text>(_key('spot-media-title')).data,
          sorted.last.title,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
