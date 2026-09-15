import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bdo_gathering_companion/domain/bairog_benchmarks.dart';
import 'package:bdo_gathering_companion/src/domain/models.dart';
import 'package:bdo_gathering_companion/src/ui/field_guide.dart';
import 'package:bdo_gathering_companion/src/ui/theme.dart';
import 'package:bdo_gathering_companion/src/widgets/spot_media_gallery.dart';
import 'package:bdo_gathering_companion/src/widgets/spot_video_player.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _rotation = 'assets/rotations/bunnygirl_edania_thuja_rotation.png';
const _setup = 'assets/rotations/bunnygirl_edania_thuja_starter_options.png';
List<SpotMedia> _references() => [
  SpotMedia({
    'type': 'image',
    'title': 'Thuja rotation · bunnygirl · 00:37',
    'asset': _rotation,
    'author': 'bunnygirl',
  }),
  SpotMedia({
    'type': 'image',
    'title': 'Starter setup options · bunnygirl · 00:22',
    'asset': _setup,
    'author': 'bunnygirl',
  }),
  SpotMedia({
    'type': 'video',
    'title': 'Edania Thuja · minigame-event reference',
    'url': 'https://www.youtube.com/watch?v=LuQYJzrKojE',
    'author': 'bunnygirl',
  }),
  SpotMedia({
    'type': 'video',
    'title': 'Bunny’s newer Edania Thuja reference',
    'url': 'https://www.youtube.com/watch?v=JPVgR5G2eg4',
    'author': 'bunnygirl',
  }),
];

class _FakeVideoSession implements SpotVideoSession {
  final _events = StreamController<SpotVideoEvent>.broadcast();
  bool disposed = false;
  int plays = 0;
  YouTubeVideo? video;
  @override
  Stream<SpotVideoEvent> get events => _events.stream;
  @override
  Future<void> open(YouTubeVideo video) async {
    this.video = video;
    _events.add(const SpotVideoEvent(SpotVideoEventKind.ready));
  }

  @override
  Future<void> play() async => plays++;
  @override
  Widget buildView() => const ColoredBox(
    color: Color(0xff142c36),
    child: Center(child: Text('Video test surface')),
  );
  @override
  Future<void> dispose() async {
    disposed = true;
    await _events.close();
  }
}

Future<void> _pump(
  WidgetTester tester, {
  List<SpotMedia>? media,
  double width = 620,
  double scale = 1,
  List<_FakeVideoSession>? sessions,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1000, 900);
  await tester.pumpWidget(
    MaterialApp(
      theme: companionTheme(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Scaffold(
        body: Center(
          child: RepaintBoundary(
            key: const ValueKey('pager-capture'),
            child: SizedBox(
              width: width,
              child: SpotMediaGallery(
                media: media ?? _references(),
                height: 440,
                videoSessionFactory: () {
                  final session = _FakeVideoSession();
                  sessions?.add(session);
                  return session;
                },
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _key(String name) => find.byKey(ValueKey(name));
String _text(WidgetTester tester, String key) =>
    tester.widget<Text>(_key(key)).data!;
Future<void> _next(WidgetTester tester, {bool expanded = false}) async {
  await tester.tap(_key('${expanded ? '' : 'inline-'}next-spot-reference'));
  await tester.pumpAndSettle();
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump();
}

Future<void> _captureNavigation(WidgetTester tester, String name) async {
  final captureRoot = Platform.environment['GATHERING_PAGER_CAPTURE_DIR'];
  if (captureRoot == null) return;
  for (final element in find.byType(Image).evaluate()) {
    await tester.runAsync(
      () => precacheImage((element.widget as Image).image, element),
    );
  }
  await tester.pumpAndSettle();
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    _key('related-guide-capture'),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
    await File('$captureRoot/$name.png').writeAsBytes(
      bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
    );
    image.dispose();
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    if (!Platform.isWindows) return;
    final root = Platform.environment['WINDIR'] ?? r'C:\Windows';
    var flutter = File(Platform.resolvedExecutable).parent;
    while (!Directory(
      '${flutter.path}/bin/cache/artifacts/material_fonts',
    ).existsSync()) {
      final parent = flutter.parent;
      if (parent.path == flutter.path) {
        throw StateError('Flutter fonts missing.');
      }
      flutter = parent;
    }
    for (final entry in <String, List<String>>{
      'Segoe UI': ['$root/Fonts/segoeui.ttf', '$root/Fonts/seguisb.ttf'],
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
  });

  test(
    'same video and start time deduplicate without discarding other chapters',
    () {
      SpotMedia video(String url) => SpotMedia({'type': 'video', 'url': url});
      final entries = [
        video('https://youtu.be/LuQYJzrKojE?si=tracking'),
        video('https://www.youtube.com/watch?v=LuQYJzrKojE'),
        video('https://www.youtube.com/watch?v=LuQYJzrKojE&t=47s'),
        video('https://youtu.be/LuQYJzrKojE?start=47'),
        video('https://youtu.be/JPVgR5G2eg4'),
      ];
      final result = orderSpotMediaForDisplay(entries);
      expect(result, hasLength(3));
      expect(result, [entries[0], entries[2], entries[4]]);
    },
  );
  testWidgets(
    'visible pager reaches every image and video and stops at boundaries',
    (tester) async {
      addTearDown(tester.view.reset);
      final sessions = <_FakeVideoSession>[];
      await _pump(tester, sessions: sessions);
      expect(_text(tester, 'inline-spot-reference-position'), '1/4');
      expect(
        tester
            .widget<IconButton>(_key('inline-previous-spot-reference'))
            .onPressed,
        isNull,
      );
      await _next(tester);
      expect(_text(tester, 'spot-media-type'), 'Setup');
      expect(_text(tester, 'inline-spot-reference-position'), '2/4');
      await _next(tester);
      expect(_text(tester, 'spot-media-type'), 'Video');
      expect(
        tester.widget<SpotVideoPlayer>(find.byType(SpotVideoPlayer)).videoUrl,
        contains('LuQYJzrKojE'),
      );
      expect(sessions, hasLength(1));
      expect(
        sessions.single.plays,
        0,
        reason: 'Inline paging loads paused, never autoplays.',
      );
      await _next(tester);
      expect(_text(tester, 'inline-spot-reference-position'), '4/4');
      expect(sessions.first.disposed, isTrue);
      expect(sessions.last.video?.id, 'JPVgR5G2eg4');
      expect(
        tester.widget<IconButton>(_key('inline-next-spot-reference')).onPressed,
        isNull,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      expect(sessions.every((session) => session.disposed), isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('expanded mixed pager returns its exact selected media inline', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    final sessions = <_FakeVideoSession>[];
    await _pump(tester, sessions: sessions);
    await tester.tap(_key('expand-spot-media'));
    await tester.pumpAndSettle();
    expect(_text(tester, 'spot-reference-position'), '1/4');
    await _next(tester, expanded: true);
    await _next(tester, expanded: true);
    expect(find.byKey(const ValueKey('spot-video-dialog')), findsOneWidget);
    expect(
      find.byType(SpotVideoPlayer),
      findsOneWidget,
      reason: 'No hidden inline player alongside expanded video.',
    );
    expect(sessions, hasLength(1));
    await tester.tap(_key('close-spot-media'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    expect(_text(tester, 'inline-spot-reference-position'), '3/4');
    expect(sessions.first.disposed, isTrue);
    await tester.tap(_key('inline-previous-spot-reference'));
    await tester.pumpAndSettle();
    expect(_text(tester, 'spot-media-type'), 'Setup');
    expect(sessions.every((session) => session.disposed), isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'selection survives rebuild and removed selection reconciles safely',
    (tester) async {
      addTearDown(tester.view.reset);
      await _pump(tester);
      await _next(tester);
      await _pump(tester, media: _references());
      expect(_text(tester, 'inline-spot-reference-position'), '2/4');
      await _pump(tester, media: [_references().first]);
      expect(_text(tester, 'spot-media-type'), 'Rotation');
      expect(_key('inline-next-spot-reference'), findsNothing);
      await _pump(tester, media: []);
      expect(_key('spot-media-gallery'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'keyboard activation and reference picker preserve selection actions',
    (tester) async {
      addTearDown(tester.view.reset);
      await _pump(tester);
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      var reachedNext = false;
      // Tab traversal reaches the actual next button without intercepting player keys.
      for (var tries = 0; tries < 8; tries++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        if (FocusManager.instance.primaryFocus?.context != null &&
            find
                .ancestor(
                  of: find.byElementPredicate(
                    (element) => identical(
                      element,
                      FocusManager.instance.primaryFocus!.context,
                    ),
                  ),
                  matching: _key('inline-next-spot-reference'),
                )
                .evaluate()
                .isNotEmpty) {
          reachedNext = true;
          break;
        }
      }
      expect(reachedNext, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(_text(tester, 'inline-spot-reference-position'), '2/4');
      await tester.tap(_key('spot-media-reference'));
      await tester.pumpAndSettle();
      expect(find.byType(PopupMenuItem<String>), findsNWidgets(4));
      await tester.tap(find.byType(PopupMenuItem<String>).first);
      await tester.pumpAndSettle();
      expect(_text(tester, 'inline-spot-reference-position'), '1/4');
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Seoul preview opens separate Edania guide without transferring its benchmark',
    (tester) async {
      addTearDown(tester.view.reset);
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1500, 1000);
      final catalog = (await tester.runAsync(Catalog.load))!;
      final seoul = bairogBenchmarkSet.routes.singleWhere(
        (route) => route.sourceRouteId == 46,
      );
      expect(seoul.spotId, isNull);
      await tester.pumpWidget(
        MaterialApp(
          theme: companionTheme(),
          builder: (context, child) => RepaintBoundary(
            key: const ValueKey('related-guide-capture'),
            child: TickerMode(enabled: false, child: child!),
          ),
          home: Scaffold(
            body: FieldGuide(
              catalog: catalog,
              bairogCalculatorData: catalog.bairogCalculatorData,
              onUse: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(_key('spot-filter-rail-control'));
      await tester.pumpAndSettle();
      await tester.tap(_key('spot-ranking-nostos-821349'));
      await tester.pumpAndSettle();
      await tester.enterText(_key('spot-search'), 'Seoul Thuja');
      await tester.pumpAndSettle();
      final routeCard = _key('spot-route-46');
      await tester.ensureVisible(routeCard);
      await tester.tap(routeCard);
      await tester.pumpAndSettle();
      final seoulGallery = tester.widget<SpotMediaGallery>(
        _key('bairog-route-media-46'),
      );
      expect(seoulGallery.media, hasLength(1));
      expect(
        YouTubeVideo.parse(seoulGallery.media.single.url)!.id,
        'lD-8E-PnIyE',
      );
      expect(
        find.byKey(const ValueKey('bairog-route-evidence-46')),
        findsOneWidget,
      );
      // Native video stays disabled in this offline fixture. Complete only the
      // dialog entrance so its real overlay is visible in the capture.
      final route = ModalRoute.of(
        tester.element(_key('open-related-edania-thuja-guides')),
      )!;
      // Test-only transition control while native media tickers stay disabled.
      // ignore: invalid_use_of_protected_member
      route.controller!.value = 1;
      await tester.pump();
      await _captureNavigation(tester, 'seoul-preview-related-edania');
      await tester.tap(_key('open-related-edania-thuja-guides'));
      // ignore: invalid_use_of_protected_member
      route.controller!.value = 0;
      await tester.pumpAndSettle();
      expect(_key('bairog-route-media-46'), findsNothing);
      expect(_key('bairog-selected-route-evidence'), findsNothing);
      final edaniaGallery = tester.widget<SpotMediaGallery>(
        _key('guide-media-edania-thuja-bunnygirl'),
      );
      expect(
        edaniaGallery.media.where((media) => media.type == 'image'),
        hasLength(3),
      );
      expect(
        edaniaGallery.media.any((media) => media.url.contains('LuQYJzrKojE')),
        isTrue,
      );
      expect(
        edaniaGallery.media.any((media) => media.url.contains('lD-8E-PnIyE')),
        isFalse,
      );
      expect(find.textContaining('Whispering Memorial'), findsWidgets);
      await _captureNavigation(tester, 'separate-edania-guide-from-seoul');
      await tester.tap(_key('guide-change-spot'));
      await tester.pumpAndSettle();
      expect(routeCard, findsOneWidget);
      expect(
        tester.widget<TextField>(_key('spot-search')).controller!.text,
        'Seoul Thuja',
      );
      expect(seoul.videoUrl, 'https://youtu.be/lD-8E-PnIyE');
      expect(seoul.gathersPerHour, 693);
      expect(seoul.sourceSilverAfterTaxPerHour, 1940000000);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
  for (final scale in [1.0, 2.0]) {
    for (final width in [620.0, 320.0]) {
      testWidgets('real reference fits ${width.toInt()}px at ${scale}x text', (
        tester,
      ) async {
        addTearDown(tester.view.reset);
        await _pump(tester, width: width, scale: scale);
        for (final element in find.byType(Image).evaluate()) {
          await tester.runAsync(
            () => precacheImage((element.widget as Image).image, element),
          );
        }
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final gallery = tester.getRect(_key('spot-media-gallery'));
        for (final key in [
          'spot-media-title',
          'inline-previous-spot-reference',
          'inline-next-spot-reference',
          'expand-spot-media',
        ]) {
          expect(gallery.contains(tester.getRect(_key(key)).center), isTrue);
        }
        final captureRoot = Platform.environment['GATHERING_PAGER_CAPTURE_DIR'];
        if (captureRoot != null) {
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            _key('pager-capture'),
          );
          await tester.runAsync(() async {
            final image = await boundary.toImage(pixelRatio: 1);
            final bytes = (await image.toByteData(
              format: ui.ImageByteFormat.png,
            ))!;
            await File(
              '$captureRoot/pager-${width.toInt()}-text${(scale * 100).round()}.png',
            ).writeAsBytes(
              bytes.buffer.asUint8List(
                bytes.offsetInBytes,
                bytes.lengthInBytes,
              ),
            );
            image.dispose();
          });
        }
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }
}
