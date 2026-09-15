import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bdo_gathering_companion/domain/models.dart';
import 'package:bdo_gathering_companion/src/ui/theme.dart';
import 'package:bdo_gathering_companion/src/widgets/spot_media_gallery.dart';
import 'package:bdo_gathering_companion/src/widgets/spot_video_player.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _video = 'KnfbewYBxhE';
const _captureKey = ValueKey('grouped-media-capture');
const _buffImage = 'assets/rotations/edania_coral_crabs.png';
const _setupImage = 'assets/rotations/edania_rock_elephants.png';
Finder _key(String key) => find.byKey(ValueKey(key));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Catalog catalog;
  late List<SpotMedia> lion;
  setUpAll(() async {
    catalog = await Catalog.load();
    lion = _withPublicImageFixtures(
      catalog.spots
          .singleWhere((spot) => spot.id == 'narcion-shadow-lion-hunting')
          .media,
    );
    await _loadFonts();
  });

  for (final scenario in [
    (name: 'normal100', size: const Size(1200, 752), scale: 1.0),
    (name: 'enlarged200', size: const Size(760, 752), scale: 2.0),
  ]) {
    testWidgets(
      'one video heading with chapters in both pickers ${scenario.name}',
      (tester) async {
        addTearDown(tester.view.reset);
        final shadows = debugDisableShadows;
        debugDisableShadows = false;
        try {
          final sessions = <_VideoSession>[];
          await _pump(
            tester,
            lion,
            sessions,
            size: scenario.size,
            scale: scenario.scale,
          );
          expect(
            _position(tester),
            '2/4',
            reason:
                'Three chapters share one video; two images and the earlier video remain.',
          );
          expect(_key('spot-media-image-$_buffImage'), findsOneWidget);
          await tester.tap(_key('spot-media-reference'));
          await tester.pumpAndSettle();
          _expectGroupedMenu(tester, lion);
          await _capture(tester, 'grouped-inline-${scenario.name}');
          for (final seconds in [1121, 858, 795]) {
            final option = _chapterOption(lion, seconds);
            await tester.ensureVisible(option);
            await tester.pumpAndSettle();
            expect(option.hitTestable(), findsOneWidget);
          }
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await tester.pumpAndSettle();
          await tester.tap(_key('expand-spot-media'));
          await tester.pumpAndSettle();
          await _decodeImages(tester);
          expect(_position(tester, expanded: true), '2/4');
          await tester.tap(_key('expanded-spot-media-reference'));
          await tester.pumpAndSettle();
          _expectGroupedMenu(tester, lion);
          await _capture(tester, 'grouped-expanded-${scenario.name}');
          final option = _chapterOption(lion, 795);
          await tester.ensureVisible(option);
          await tester.pumpAndSettle();
          await tester.tap(option.hitTestable());
          await tester.pumpAndSettle();
          expect(_position(tester, expanded: true), '1/4');
          expect(_currentVideo(tester).startSeconds, 795);
          expect(find.byType(SpotVideoPlayer), findsOneWidget);
          await tester.tap(_key('close-spot-media'));
          await tester.pumpAndSettle();
          expect(_position(tester), '1/4');
          expect(_currentVideo(tester).startSeconds, 795);
          expect(find.byType(SpotVideoPlayer), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
          expect(sessions.every((session) => session.disposed), isTrue);
        } finally {
          debugDisableShadows = shadows;
        }
      },
    );
  }

  testWidgets(
    'paging remembers each selected chapter across expansion and rebuilds',
    (tester) async {
      addTearDown(tester.view.reset);
      final sessions = <_VideoSession>[];
      await _pump(tester, lion, sessions);
      await _choose(tester, lion, 858);
      expect(_position(tester), '1/4');
      expect(_currentVideo(tester).startSeconds, 858);
      await _page(tester, next: true);
      expect(_key('spot-media-image-$_buffImage'), findsOneWidget);
      await _page(tester, next: false);
      expect(_currentVideo(tester).startSeconds, 858);
      await _pump(tester, List.of(lion), sessions);
      expect(_currentVideo(tester).startSeconds, 858);
      await tester.tap(_key('expand-spot-media'));
      await tester.pumpAndSettle();
      expect(_currentVideo(tester).startSeconds, 858);
      await _page(tester, next: true, expanded: true);
      await _page(tester, next: false, expanded: true);
      expect(_currentVideo(tester).startSeconds, 858);
      await _choose(tester, lion, 1121, expanded: true);
      expect(_currentVideo(tester).startSeconds, 1121);
      await tester.tap(_key('close-spot-media'));
      await tester.pumpAndSettle();
      await _page(tester, next: true);
      await _page(tester, next: false);
      expect(_currentVideo(tester).startSeconds, 1121);
      expect(
        sessions.last.plays,
        0,
        reason: 'Returning inline remains paused.',
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      expect(sessions.every((session) => session.disposed), isTrue);
    },
  );

  testWidgets(
    'Bairog remains first and URL aliases do not add groups or chapters',
    (tester) async {
      addTearDown(tester.view.reset);
      final rhino = _withPublicImageFixtures(
        catalog.spots
            .singleWhere((spot) => spot.id == 'narcion-grass-rhino-hunting')
            .media,
      );
      final entries = [
        ...rhino,
        SpotMedia({
          'type': 'video',
          'url': 'https://youtu.be/$_video?t=858',
          'author': 'Luneye',
          'title': 'Duplicate tracking URL',
        }),
      ];
      final ordered = orderSpotMediaForDisplay(entries);
      expect(ordered, hasLength(rhino.length));
      final sessions = <_VideoSession>[];
      await _pump(tester, entries, sessions);
      expect(_position(tester), '3/4');
      await tester.tap(_key('spot-media-reference'));
      await tester.pumpAndSettle();
      final first = tester.widget<PopupMenuItem<String>>(
        _key('spot-reference-option-0'),
      );
      expect(first.value, 'video:SUMvn-j_1Hg:1315');
      expect(_key('spot-reference-group-video:$_video'), findsOneWidget);
      expect(find.text('Duplicate tracking URL'), findsNothing);
      await tester.tap(_key('spot-reference-option-0'));
      await tester.pumpAndSettle();
      expect(_position(tester), '1/4');
      expect(_currentVideo(tester).id, 'SUMvn-j_1Hg');
      await _page(tester, next: true);
      expect(_position(tester), '2/4');
      expect(_currentVideo(tester).id, _video);
      await _page(tester, next: true);
      expect(_position(tester), '3/4');
      expect(_key('spot-media-image-$_buffImage'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'a single video keeps its chapter chooser without a repeated-video pager',
    (tester) async {
      addTearDown(tester.view.reset);
      final chapters = lion
          .where(
            (entry) =>
                entry.type == 'video' &&
                YouTubeVideo.parse(entry.url)?.id == _video,
          )
          .toList();
      final sessions = <_VideoSession>[];
      await _pump(tester, chapters, sessions);
      expect(_key('inline-spot-reference-position'), findsNothing);
      expect(_key('inline-next-spot-reference'), findsNothing);
      await _choose(tester, chapters, 858);
      expect(_currentVideo(tester).startSeconds, 858);
      await tester.tap(_key('spot-media-reference'));
      await tester.pumpAndSettle();
      expect(_key('spot-reference-group-video:$_video'), findsOneWidget);
      expect(find.text('Luneye · Sep 2026'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(_currentVideo(tester).startSeconds, 858);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}

List<SpotMedia> _withPublicImageFixtures(List<SpotMedia> media) => <SpotMedia>[
  ...media,
  SpotMedia({
    'type': 'image',
    'asset': _buffImage,
    'title': 'Buff reference fixture',
    'publishedDate': '2026-09-13',
  }),
  SpotMedia({
    'type': 'image',
    'asset': _setupImage,
    'title': 'Setup reference fixture',
    'publishedDate': '2026-09-13',
  }),
];

void _expectGroupedMenu(WidgetTester tester, List<SpotMedia> media) {
  expect(_key('spot-reference-group-video:$_video'), findsOneWidget);
  expect(find.text('Luneye · Sep 2026'), findsOneWidget);
  expect(find.text('14:18'), findsOneWidget);
  expect(find.text('13:15'), findsOneWidget);
  expect(find.text('Matchlock buffs and food choices'), findsOneWidget);
  expect(
    find.text('Matchlock crystal setup and resistance swaps'),
    findsOneWidget,
  );
  for (final seconds in [1121, 858, 795]) {
    expect(_chapterOption(media, seconds), findsOneWidget);
  }
  expect(tester.takeException(), isNull);
}

Finder _chapterOption(List<SpotMedia> media, int seconds) {
  final ordered = orderSpotMediaForDisplay(media);
  final index = ordered.indexWhere(
    (entry) =>
        entry.type == 'video' &&
        YouTubeVideo.parse(entry.url)?.id == _video &&
        YouTubeVideo.parse(entry.url)?.startSeconds == seconds,
  );
  expect(index, greaterThanOrEqualTo(0));
  return _key('spot-reference-option-$index');
}

Future<void> _choose(
  WidgetTester tester,
  List<SpotMedia> media,
  int seconds, {
  bool expanded = false,
}) async {
  await tester.tap(
    _key(expanded ? 'expanded-spot-media-reference' : 'spot-media-reference'),
  );
  await tester.pumpAndSettle();
  final option = _chapterOption(media, seconds);
  await tester.ensureVisible(option);
  await tester.pumpAndSettle();
  await tester.tap(option.hitTestable());
  await tester.pumpAndSettle();
}

Future<void> _page(
  WidgetTester tester, {
  required bool next,
  bool expanded = false,
}) async {
  await tester.tap(
    _key(
      '${expanded ? '' : 'inline-'}${next ? 'next' : 'previous'}-spot-reference',
    ),
  );
  await tester.pumpAndSettle();
}

String _position(WidgetTester tester, {bool expanded = false}) => tester
    .widget<Text>(_key('${expanded ? '' : 'inline-'}spot-reference-position'))
    .data!;
YouTubeVideo _currentVideo(WidgetTester tester) => YouTubeVideo.parse(
  tester.widget<SpotVideoPlayer>(find.byType(SpotVideoPlayer)).videoUrl,
)!;

Future<void> _pump(
  WidgetTester tester,
  List<SpotMedia> media,
  List<_VideoSession> sessions, {
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
        theme: companionTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: SizedBox(
                width: 780,
                child: SpotMediaGallery(
                  media: media,
                  height: 520,
                  videoSessionFactory: () {
                    final session = _VideoSession();
                    sessions.add(session);
                    return session;
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await _decodeImages(tester);
}

Future<void> _decodeImages(WidgetTester tester) async {
  for (final element in find.byType(Image).evaluate()) {
    await tester.runAsync(
      () => precacheImage((element.widget as Image).image, element),
    );
  }
  await tester.pumpAndSettle();
}

Future<void> _capture(WidgetTester tester, String name) async {
  final directory = Platform.environment['GROUPED_MEDIA_CAPTURE_DIR'];
  if (directory == null) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_captureKey),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
    await File('$directory/$name.png').writeAsBytes(
      bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
    );
    image.dispose();
  });
}

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

class _VideoSession implements SpotVideoSession {
  final _events = StreamController<SpotVideoEvent>.broadcast();
  bool disposed = false;
  int plays = 0;
  @override
  Stream<SpotVideoEvent> get events => _events.stream;
  @override
  Future<void> open(YouTubeVideo video) async {
    _events.add(const SpotVideoEvent(SpotVideoEventKind.ready));
  }

  @override
  Future<void> play() async => plays++;
  @override
  Widget buildView() => const ColoredBox(color: Color(0xff142c36));
  @override
  Future<void> dispose() async {
    disposed = true;
    await _events.close();
  }
}
