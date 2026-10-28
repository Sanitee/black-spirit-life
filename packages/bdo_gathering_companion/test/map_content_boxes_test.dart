import 'dart:io';
import 'dart:ui' as ui;

import 'package:bdo_gathering_companion/domain/models.dart';
import 'package:bdo_gathering_companion/src/domain/world_map.dart';
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

  testWidgets('field browser floats lazy results above the single usable map', (
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
      expect(find.byType(BackdropGroup), findsNothing);
      expect(find.byType(SpotMap), findsOneWidget);
      for (final control in [
        find.byKey(const ValueKey('spot-search')),
        find.byKey(const ValueKey('spot-method-filter')),
        find.byKey(const ValueKey('spot-ranking-browse')),
        cards().first,
      ]) {
        expect(control, findsOneWidget);
        expect(
          find.ancestor(of: control, matching: find.byType(BackdropFilter)),
          findsNothing,
        );
      }
      final list = tester.widget<ListView>(
        find.byKey(const ValueKey('spot-list')),
      );
      expect(list.shrinkWrap, isFalse);
      final viewport = tester.renderObject(
        find.byKey(const ValueKey('spot-map-viewport')),
      );
      final mapBounds = tester.getRect(
        find.byKey(const ValueKey('spot-map-viewport')),
      );
      final listBounds = tester.getRect(
        find.byKey(const ValueKey('spot-list')),
      );
      expect(mapBounds.left, lessThanOrEqualTo(listBounds.left));
      expect(mapBounds.contains(listBounds.center), isTrue);
      expect(tester.widget<SpotMap>(find.byType(SpotMap)).viewInsets.left, 336);
      for (final point in [
        mapBounds.center,
        Offset(listBounds.right + 60, mapBounds.bottom - 60),
      ]) {
        expect(
          tester
              .hitTestOnBinding(point)
              .path
              .any((entry) => entry.target == viewport),
          isTrue,
          reason:
              'The map at $point must not be obscured by results or filters.',
        );
      }
      for (final point in [
        tester.getCenter(find.byKey(const ValueKey('spot-search'))),
        tester.getCenter(cards().first),
        Offset(listBounds.left + 1, listBounds.bottom - 1),
      ]) {
        expect(
          tester
              .hitTestOnBinding(point)
              .path
              .any((entry) => entry.target == viewport),
          isFalse,
          reason: 'Map gestures must not run through the finder at $point.',
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
          final search = tester.widget<TextField>(
            find.byKey(const ValueKey('spot-search')),
          );
          expect(
            search.decoration!.fillColor!.a,
            alphas.last,
            reason:
                'Search uses one legible control face above the map, not a weak nested inset.',
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

  testWidgets('finder wheel and focus remain independent of map navigation', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    await HttpOverrides.runZoned(() async {
      await mount(tester);
      final map = find.byType(SpotMap);
      final mapState = tester.state(map);
      final search = find.byKey(const ValueKey('spot-search'));
      await tester.tap(search);
      await tester.enterText(search, 'a');
      await tester.pumpAndSettle();
      final focused = FocusManager.instance.primaryFocus;
      final marker = find
          .byWidgetPredicate(
            (widget) =>
                widget is Semantics &&
                widget.key is ValueKey<String> &&
                (widget.key! as ValueKey<String>).value.startsWith('map-spot-'),
          )
          .first;
      final markerKey = tester.widget(marker).key!;
      final markerBefore = tester.getCenter(find.byKey(markerKey));
      final list = find.byKey(const ValueKey('spot-list'));
      final scroll = tester.widget<ListView>(list).controller!;
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: tester.getCenter(cards().hitTestable().first),
          scrollDelta: const Offset(0, 140),
        ),
      );
      await tester.pumpAndSettle();
      expect(scroll.offset, greaterThan(0));
      expect(tester.getCenter(find.byKey(markerKey)), markerBefore);
      for (final width in [1200.0, 1500.0]) {
        tester.view.physicalSize = Size(width, 900);
        await tester.pumpAndSettle();
        expect(tester.state(map), same(mapState));
        expect(FocusManager.instance.primaryFocus, same(focused));
        expect(tester.widget<ListView>(list).controller, same(scroll));
      }
      final mapRect = tester.getRect(
        find.byKey(const ValueKey('spot-map-viewport')),
      );
      final beforePan = tester.getCenter(find.byKey(markerKey));
      await tester.dragFrom(
        mapRect.centerRight - const Offset(100, 0),
        const Offset(30, 20),
      );
      await tester.pumpAndSettle();
      expect(
        (tester.getCenter(find.byKey(markerKey)) - beforePan).distance,
        greaterThan(10),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    }, createHttpClient: (_) => _OfflineMapClient());
  });

  testWidgets('map fit focus and recenter account for the floating finder', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 700);
    final icon = catalog.spots.firstWhere((spot) => spot.icon.isNotEmpty).icon;
    final spots = [
      Spot({
        'id': 'west',
        'name': 'West',
        'icon': icon,
        'worldX': -200000,
        'worldZ': 100000,
      }),
      Spot({
        'id': 'east',
        'name': 'East',
        'icon': icon,
        'worldX': 200000,
        'worldZ': -100000,
      }),
    ];
    await HttpOverrides.runZoned(() async {
      Future<void> map({double inset = 336, Spot? selected}) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: companionTheme(),
            home: Scaffold(
              body: SpotMap(
                spots: spots,
                selected: selected,
                methods: const [],
                onSelect: (_) {},
                overview: selected == null,
                viewInsets: EdgeInsets.only(left: inset),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      void expectFit(double inset) {
        for (final spot in spots) {
          final point = tester.getCenter(
            find.byKey(ValueKey('map-spot-${spot.id}')),
          );
          expect(point.dx, greaterThan(inset + 30));
          expect(point.dx, lessThan(1370));
          expect(point.dy, inInclusiveRange(30, 670));
        }
      }

      await map();
      expectFit(336);
      final state = tester.state(find.byType(SpotMap));
      await map(inset: 448);
      expect(tester.state(find.byType(SpotMap)), same(state));
      expectFit(448);
      await tester.dragFrom(const Offset(950, 350), const Offset(-200, 100));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('map-recenter')));
      await tester.pumpAndSettle();
      expectFit(448);
      await map(inset: 448, selected: spots.first);
      final selected = find.byKey(const ValueKey('map-spot-west'));
      expect(tester.getCenter(selected), const Offset(924, 350));
      await tester.tap(find.byKey(const ValueKey('map-zoom-in')));
      await tester.pumpAndSettle();
      expect(tester.getCenter(selected), const Offset(924, 350));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    }, createHttpClient: (_) => _OfflineMapClient());
  });

  testWidgets(
    'finder insets clip annotation paint and hits without filtering data',
    (tester) async {
      addTearDown(tester.view.reset);
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(800, 600);
      final capture = GlobalKey();
      final spot = Spot({
        'id': 'clip-fixture',
        'name': 'Clip fixture',
        'nodeName': 'Fixture',
        'worldX': 0,
        'worldZ': 0,
        'icon': catalog.spots.firstWhere((spot) => spot.icon.isNotEmpty).icon,
      });
      final nodes = [
        WorldNode(
          id: 'covered',
          name: 'Covered town',
          x: 10000,
          z: 20000,
          icon: catalog.mapNodes.first.icon,
          type: 'Town',
          links: ['visible'],
        ),
        WorldNode(
          id: 'visible',
          name: 'Visible town',
          x: 100000,
          z: 20000,
          icon: catalog.mapNodes.first.icon,
          type: 'Town',
        ),
      ];
      var selected = 0;
      await HttpOverrides.runZoned(() async {
        Future<void> mountMap(EdgeInsets insets) async {
          await tester.pumpWidget(
            MaterialApp(
              theme: companionTheme(),
              home: RepaintBoundary(
                key: capture,
                child: Scaffold(
                  body: SpotMap(
                    spots: [spot],
                    selected: spot,
                    methods: const [],
                    nodes: nodes,
                    onSelect: (_) => selected++,
                    viewInsets: insets,
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
        }

        await mountMap(const EdgeInsets.only(left: 300));
        final mapState = tester.state(find.byType(SpotMap));
        await tester.dragFrom(const Offset(700, 500), const Offset(-400, 0));
        await tester.pumpAndSettle();
        final marker = find.byKey(const ValueKey('map-spot-clip-fixture'));
        final town = find.byKey(const ValueKey('map-node-covered'));
        final visibleTown = find.byKey(const ValueKey('map-node-visible'));
        expect(
          marker,
          findsOneWidget,
          reason: 'Clipping must not filter source spots.',
        );
        expect(
          town,
          findsOneWidget,
          reason: 'Clipping must not remove source nodes.',
        );
        final markerPoint = tester.getCenter(marker);
        final townPoint = tester.getCenter(town);
      final labelPoint = tester.getCenter(
        find.byKey(const ValueKey('map-spot-label-clip-fixture')),
      );
        expect(markerPoint.dx, lessThan(300));
        expect(townPoint.dx, lessThan(300));
        expect(marker.hitTestable(), findsNothing);
        expect(town.hitTestable(), findsNothing);
        expect(visibleTown.hitTestable(), findsOneWidget);
        await tester.tapAt(markerPoint);
        await tester.pumpAndSettle();
        expect(
          selected,
          0,
          reason: 'Covered annotations must not accept pointer taps.',
        );
        final clip = find.byKey(const ValueKey('spot-map-annotation-clip'));
        final clipWidget = tester.widget<ClipRect>(clip);
        expect(
          clipWidget.clipper!.getClip(const Size(800, 600)),
          const Rect.fromLTWH(300, 0, 500, 600),
        );
        expect(
          find.ancestor(
            of: find.byKey(const ValueKey('map-zoom-in')),
            matching: clip,
          ),
          findsNothing,
        );
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(capture),
        );
        final pixels = await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 1);
          final data = await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          );
          image.dispose();
          return data!;
        });
        for (final point in [
          markerPoint,
          townPoint,
        labelPoint,
          Offset(260, townPoint.dy),
        ]) {
          final offset = (point.dy.floor() * 800 + point.dx.floor()) * 4;
          expect(
            [for (var i = 0; i < 4; i++) pixels!.getUint8(offset + i)],
            [48, 68, 72, 255],
            reason:
                'Covered marker, town icon and connection must paint only the map background at $point.',
          );
        }
        await mountMap(EdgeInsets.zero);
        expect(tester.state(find.byType(SpotMap)), same(mapState));
        expect(
          clip,
          findsNothing,
          reason:
              'Ordinary detail maps retain their original un-inset annotation tree.',
        );
        await tester.tap(find.byKey(const ValueKey('map-recenter')));
        await tester.pumpAndSettle();
        expect(marker.hitTestable(), findsOneWidget);
        await tester.tap(marker);
        await tester.pumpAndSettle();
        expect(selected, 1);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      }, createHttpClient: (_) => _OfflineMapClient());
    },
  );

  testWidgets('oversized finder insets remain bounded in a tiny map', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 600);
    final spot = Spot({
      'id': 'tiny',
      'name': 'Tiny',
      'worldX': 0,
      'worldZ': 0,
      'icon': catalog.spots.firstWhere((spot) => spot.icon.isNotEmpty).icon,
    });
    await HttpOverrides.runZoned(() async {
      await tester.pumpWidget(
        MaterialApp(
          theme: companionTheme(),
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 80,
                height: 160,
                child: SpotMap(
                  spots: [spot],
                  selected: spot,
                  methods: const [],
                  onSelect: (_) {},
                  viewInsets: const EdgeInsets.all(448),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final point = tester.getCenter(
        find.byKey(const ValueKey('map-spot-tiny')),
      );
      expect(point.dx, inInclusiveRange(0, 80));
      expect(point.dy, inInclusiveRange(0, 160));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    }, createHttpClient: (_) => _OfflineMapClient());
  });

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
