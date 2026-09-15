import 'dart:io';
import 'dart:ui' as ui;

import 'package:bdo_gathering_companion/domain/models.dart';
import 'package:bdo_gathering_companion/src/ui/field_guide.dart';
import 'package:bdo_gathering_companion/src/ui/theme.dart';
import 'package:bdo_gathering_companion/src/widgets/spot_map.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _OfflineMapClient implements HttpClient {
  @override
  Future<HttpClientRequest> getUrl(Uri url) async =>
      throw const HttpException('Offline Gathering map fixture');
  @override
  set connectionTimeout(Duration? value) {}
  @override
  void close({bool force = false}) {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Catalog catalog;
  setUpAll(() async {
    catalog = await Catalog.load();
    if (Platform.isWindows) await _loadWindowsFonts();
  });

  Future<void> mount(
    WidgetTester tester, {
    int opacity = 60,
    Size size = const Size(1500, 900),
    double textScale = 1,
    ValueChanged<Spot>? onUse,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    await tester.pumpWidget(
      MaterialApp(
        theme: companionTheme(opacityPercent: opacity),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
            disableAnimations: true,
          ),
          child: child!,
        ),
        home: RepaintBoundary(
          key: const ValueKey('gathering-content-capture'),
          child: Scaffold(
            body: FieldGuide(
              catalog: catalog,
              onUse: onUse ?? (_) {},
              initialFiltersExpanded: true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder cards() => find.byWidgetPredicate(
    (widget) =>
        widget is GlassControl &&
        widget.key is ValueKey<String> &&
        (widget.key! as ValueKey<String>).value.startsWith('spot-card-'),
  );

  Future<void> capture(WidgetTester tester, String name) async {
    final path = Platform.environment['GATHERING_CONTENT_CAPTURE_DIR'];
    if (path == null) return;
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('gathering-content-capture')),
    );
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1);
      final data = (await image.toByteData(format: ui.ImageByteFormat.png))!;
      await File('$path${Platform.pathSeparator}$name.png').writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      );
      image.dispose();
    });
  }

  testWidgets('map browser has only individually backed content boxes', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    await HttpOverrides.runZoned(() async {
      await mount(tester);
      for (final key in [
        'spot-journal-surface',
        'spot-filter-journal-surface',
      ]) {
        final region = find.byKey(ValueKey(key));
        expect(tester.widget(region), isA<Padding>());
        expect(
          find.descendant(of: region, matching: find.byType(GlassSurface)),
          findsNothing,
        );
      }
      expect(find.byType(BackdropGroup), findsOneWidget);
      for (final control in [
        find.byKey(const ValueKey('spot-search')),
        find.byKey(const ValueKey('spot-method-filter')),
        find.byKey(const ValueKey('spot-ranking-browse')),
        cards().first,
      ]) {
        expect(control, findsOneWidget);
        final blur = tester.widget<BackdropFilter>(
          find
              .ancestor(of: control, matching: find.byType(BackdropFilter))
              .first,
        );
        expect(blur.enabled, isTrue);
      }
      final list = tester.widget<ListView>(
        find.byKey(const ValueKey('spot-list')),
      );
      expect(list.hitTestBehavior, HitTestBehavior.deferToChild);
      final viewport = tester.renderObject(
        find.byKey(const ValueKey('spot-map-viewport')),
      );
      final firstCard = tester.getRect(cards().first);
      for (final point in [
        const Offset(423, 100), // Empty left padding of the filter palette.
        Offset(
          firstCard.center.dx,
          firstCard.bottom + 3,
        ), // Between item boxes.
      ]) {
        expect(
          tester
              .hitTestOnBinding(point)
              .path
              .any((entry) => entry.target == viewport),
          isTrue,
          reason:
              'Unpainted space at $point must leave the map gesture available.',
        );
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    }, createHttpClient: (_) => _OfflineMapClient());
  });

  testWidgets(
    'glass setting changes backing but leaves copy icons and map opaque',
    (tester) async {
      addTearDown(tester.view.reset);
      await HttpOverrides.runZoned(() async {
        final alphas = <double>[];
        TextStyle? originalStyle;
        for (final opacity in [25, 60, 100]) {
          await mount(tester, opacity: opacity);
          final card = cards().first;
          final finish = tester.widget<TweenAnimationBuilder<Decoration>>(
            find.descendant(
              of: card,
              matching: find.byKey(const ValueKey('glass-control-finish')),
            ),
          );
          alphas.add(
            (finish.tween.end! as BoxDecoration).gradient!.colors.first.a,
          );
          final text = tester.widget<Text>(
            find.descendant(of: card, matching: find.byType(Text)).first,
          );
          originalStyle ??= text.style;
          expect(text.style, originalStyle);
          for (final target in [card, find.byType(SpotMap)]) {
            expect(
              find.ancestor(of: target, matching: find.byType(Opacity)),
              findsNothing,
            );
          }
          await capture(tester, 'gathering-content-$opacity');
        }
        expect(alphas[0], lessThan(alphas[1]));
        expect(alphas[1], lessThan(alphas[2]));
        expect(alphas[2], 1);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      }, createHttpClient: (_) => _OfflineMapClient());
    },
  );

  for (final size in [const Size(1500, 900), const Size(800, 900)]) {
    testWidgets(
      'choose another spot keeps filter and scroll at ${size.width}',
      (tester) async {
        addTearDown(tester.view.reset);
        await HttpOverrides.runZoned(() async {
          final used = <Spot>[];
          await mount(tester, size: size, onUse: used.add);
          await tester.enterText(
            find.byKey(const ValueKey('spot-search')),
            'a',
          );
          await tester.pumpAndSettle();
          final list = find.byKey(
            ValueKey(size.width >= 900 ? 'spot-list' : 'spot-strip'),
          );
          final controller = tester.widget<ListView>(list).controller!;
          await tester.sendEventToBinding(
            PointerScrollEvent(
              position: tester.getCenter(cards().hitTestable().first),
              scrollDelta: const Offset(0, 140),
            ),
          );
          await tester.pumpAndSettle();
          final before = controller.offset;
          expect(before, greaterThan(0));
          final chosen = cards().hitTestable().first;
          await tester.tap(chosen);
          await tester.pumpAndSettle();
          final back = find.byKey(const ValueKey('guide-change-spot'));
          expect(
            find.descendant(
              of: back,
              matching: find.text('Choose another spot'),
            ),
            findsOneWidget,
          );
          expect(
            find.descendant(of: back, matching: find.byIcon(Icons.arrow_back)),
            findsOneWidget,
          );
          expect(used, isEmpty);
          Focus.of(
            tester.element(find.text('Choose another spot')),
          ).requestFocus();
          await tester.pump();
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pumpAndSettle();
          expect(
            tester
                .widget<TextField>(find.byKey(const ValueKey('spot-search')))
                .controller!
                .text,
            'a',
          );
          expect(tester.widget<ListView>(list).controller, same(controller));
          expect(controller.offset, closeTo(before, .1));
          expect(used, isEmpty);
          await tester.tap(cards().hitTestable().first);
          await tester.pumpAndSettle();
          final prepare = find.byKey(const ValueKey('use-spot'));
          await tester.ensureVisible(prepare);
          await tester.tap(prepare);
          await tester.pumpAndSettle();
          expect(used, hasLength(1));
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        }, createHttpClient: (_) => _OfflineMapClient());
      },
    );
  }

  testWidgets('explicit spot return remains visible with doubled text', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    await HttpOverrides.runZoned(() async {
      await mount(tester, size: const Size(900, 900), textScale: 2);
      await tester.tap(cards().hitTestable().first);
      await tester.pumpAndSettle();
      final back = find.byKey(const ValueKey('guide-change-spot'));
      expect(back.hitTestable(), findsOneWidget);
      await capture(tester, 'gathering-explicit-return-double-text');
      final button = tester.widget<TextButton>(back);
      expect(button.onPressed, isNotNull);
      await tester.tap(back);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('spot-search')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    }, createHttpClient: (_) => _OfflineMapClient());
  });
}

Future<void> _loadWindowsFonts() async {
  final windowsRoot = Platform.environment['WINDIR'] ?? r'C:\Windows';
  var flutterRoot = File(Platform.resolvedExecutable).parent;
  while (!Directory(
    '${flutterRoot.path}/bin/cache/artifacts/material_fonts',
  ).existsSync()) {
    final parent = flutterRoot.parent;
    if (parent.path == flutterRoot.path) {
      throw StateError('Flutter fonts not found.');
    }
    flutterRoot = parent;
  }
  final fonts = <String, List<String>>{
    'Segoe UI': [
      for (final name in ['segoeui.ttf', 'seguisb.ttf', 'segoeuib.ttf'])
        '$windowsRoot/Fonts/$name',
    ],
    'Roboto': [
      for (final name in ['roboto-regular.ttf', 'roboto-bold.ttf'])
        '${flutterRoot.path}/bin/cache/artifacts/material_fonts/$name',
    ],
    'MaterialIcons': [
      '${flutterRoot.path}/bin/cache/artifacts/material_fonts/materialicons-regular.otf',
    ],
  };
  for (final entry in fonts.entries) {
    final loader = FontLoader(entry.key);
    for (final path in entry.value) {
      loader.addFont(File(path).readAsBytes().then(ByteData.sublistView));
    }
    await loader.load();
  }
}
