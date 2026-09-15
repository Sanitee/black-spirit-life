import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bdo_gathering_companion/domain/models.dart';
import 'package:bdo_gathering_companion/src/ui/theme.dart';
import 'package:bdo_gathering_companion/src/widgets/spot_media_gallery.dart';
import 'package:bdo_gathering_companion/src/widgets/spot_video_player.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _videoId = 'KnfbewYBxhE';
const _assetRoot = 'assets/rotations/';
const _captureKey = ValueKey('luneye-reference-capture');
const _routeChapters = {
  'narcion-grass-rhino-hunting': 1100,
  'narcion-shadow-wolf-hunting': 1234,
  'narcion-shadow-lion-hunting': 1121,
  'loml-sniper-preserve': 1305,
  'edania-rock-elephant-hunting': 1348,
  'edania-cliffside-sheep-hunting': 1374,
};
const _images = {
  'luneye_matchlock_crystals_1321.png': (
    801,
    '9c36298800ac7d94a340674ee263837205ff282f84a616c9972c54ed60419f72',
  ),
  'luneye_matchlock_buffs_1424.png': (
    864,
    'feea5d3d48132f18c51d6ce76b77aa7166fcadef37f96d11e2bf9e2a13aeacc8',
  ),
  'luneye_sniper_buffs_1505.png': (
    905,
    'fed5dbb7b5a8fe01cc79c6edfa891140b4dbb5931c920fcda960ec688f39638c',
  ),
};

// Canonical JSON hashes from the verified pre-Luneye source (14 Sep 2026).
// First: all spot fields except media/guideLinks/sourceUrls. Second: old media.
// No external backup, user profile or network dependency exists at test time.
const _baseline = {
  'balenos-sniper-elk': (
    'f8834b5290096fa68fb5f2ee0999ae75e2f381efb6b4c72f43fa58b6cf5de77a',
    '0acbe669de50bcfac4da44f21b5d2879b761992cdcb21484fe0e4d300db8a9bc',
  ),
  'narcion-grass-rhino-hunting': (
    'c487575b9c782e942520c020ae060d6b475a1000cb5f6ed6a0c2c48efdba90bf',
    '7a6116e655bbce7d53ebe35e4fa1519b0200b5439065931d2f88a0eb2b510eef',
  ),
  'narcion-shadow-wolf-hunting': (
    'ba81a93b1da14b667f57d00ce9b7e62e8d3c352e5f93925e80bdd4455b8f343c',
    '8d86850fd26e1abec6c08d98f136d73c31125cbf52f7dfbbbb37ea5a8be615dc',
  ),
  'narcion-shadow-lion-hunting': (
    '687562b3eb9c4bc612c461eebd56f656ba20bd2632f39d5b4d567b5cfdbb6b4e',
    '52e94e2e9bfbc3847dcd32f82260ed76e4fe0f680ea2fed63c5a47fa0f1608bb',
  ),
  'narcion-deer-hunting': (
    'bbb5db3bcf0cc16066e383f14c7045b0e1b0b5a6b19ce223eeab2556e39839f1',
    '72795f7920387737f641db4af68d734bed8a27617849b598fa7935d1d4186a61',
  ),
  'loml-sniper-preserve': (
    '03caef0cb86c8ea30f03a995810b7e8362fceb93eba6eea138a36a7fb1a96a9d',
    'adfc8c10f8857bbfd5208cc15e4580effea8c78fe29d3ea07b14e392b9c05876',
  ),
  'edania-coral-crab-hunting': (
    '59da59ce4c0f8e276f0423fd3067379c04852f6c6cbc3cda45c66ee28adc0e60',
    '130403589f6e080209f5c193a3eaca6b1d658a87471215026fc7e017c3872b47',
  ),
  'edania-golden-leaf-hunting': (
    '5df738c49d4f3c7ee20b19528613374f7fc452beaf904a381d41864f43b16fab',
    '3e2ab7dfe6cd4bfdef41346f46813866dbe300af6772ab046ef5714d706b80fa',
  ),
  'edania-cliffside-sheep-hunting': (
    '7e3c1ae9801558d31e18da6ebeeb199dc050b89f5039c270fbe7b1e320fa09cd',
    '376953c10d3bfdfc5f040aa1abf15da72f151b787814680cbb58efd89f4f9d23',
  ),
  'edania-rock-elephant-hunting': (
    '692dd2b25c2bb8107a6a2f9aca94a44711dbbf15ff7a5331598d00c1d1aba32f',
    '03c33fba1d0c2bbd415adf7a895e4a13d72c8672b5fc02289edc44c515269553',
  ),
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Catalog catalog;
  late Map<String, dynamic> source;
  late Map<String, dynamic> provenance;
  setUpAll(() async {
    catalog = await Catalog.load();
    source = objectMap(
      jsonDecode(
        await rootBundle.loadString(
          'packages/bdo_gathering_companion/assets/data/spots.json',
        ),
      ),
    );
    provenance = objectMap(
      jsonDecode(
        await rootBundle.loadString(
          'packages/bdo_gathering_companion/assets/rotations/provenance.json',
        ),
      ),
    );
    await _loadFonts();
  });

  test(
    'Luneye chapters are scoped to eight matchlock and two sniper spots',
    () {
      final linked = catalog.spots.where((spot) => spot.media.any(_isNew));
      expect(linked.map((spot) => spot.id), unorderedEquals(_baseline.keys));
      expect(
        linked.where((spot) => spot.methodIds.contains('hunting')),
        hasLength(8),
      );
      expect(
        linked.where((spot) => spot.methodIds.contains('sniper')),
        hasLength(2),
      );
      for (final spot in linked) {
        final sniper = spot.methodIds.contains('sniper');
        final media = spot.media.where(_isNew).toList();
        final starts = media
            .where((entry) => entry.type == 'video')
            .map((entry) => YouTubeVideo.parse(entry.url)!.startSeconds);
        expect(
          starts,
          unorderedEquals([
            if (sniper) ...[735, 904] else ...[795, 858],
            if (_routeChapters[spot.id] case final int start) start,
          ]),
          reason: spot.id,
        );
        expect(
          media
              .where((entry) => entry.type == 'image')
              .map((entry) => entry.asset),
          isEmpty,
          reason: spot.id,
        );
        for (final entry in media) {
          expect(entry.author, 'Luneye');
          expect(entry.publishedDate, DateTime(2026, 9, 13));
          expect(entry.methodIds, [sniper ? 'sniper' : 'hunting']);
          expect(YouTubeVideo.parse(entry.sourceUrl)?.id, _videoId);
          if (entry.type == 'video') {
            expect(entry.title.toLowerCase(), isNot(contains('rotation')));
          }
        }
      }
      final bison = catalog.spots.singleWhere(
        (spot) => spot.id == 'stonetail-bisons',
      );
      expect(bison.media.any(_isNew), isFalse);
      expect(bison.media.single.author, 'Luneye');
      expect(YouTubeVideo.parse(bison.media.single.url)?.id, 'AWBQK8msTWA');
      expect(bison.methodIds, isNot(contains('hunting')));
    },
  );

  test(
    'guide additions preserve exact spot facts and every prior reference',
    () {
      for (final spot in objectList(source['spots'])) {
        final expected = _baseline[spot['id']];
        if (expected == null) continue;
        final facts = Map<String, dynamic>.of(spot)
          ..remove('media')
          ..remove('guideLinks')
          ..remove('sourceUrls');
        expect(_digest(facts), expected.$1, reason: '${spot['id']} facts');
        final oldMedia = objectList(
          spot['media'],
        ).where((entry) => !_isNew(SpotMedia(entry))).toList();
        expect(
          _digest(oldMedia),
          expected.$2,
          reason: '${spot['id']} old media',
        );
      }
    },
  );

  test(
    'personal setup screenshots are omitted while their guide stays linked',
    () async {
      for (final entry in _images.entries) {
        final asset = '$_assetRoot${entry.key}';
        expect(
          objectList(
            provenance['images'],
          ).where((image) => image['asset'] == asset),
          isEmpty,
        );
        expect(
          File(
            '${Directory.current.path}${Platform.pathSeparator}'
            '${asset.replaceAll('/', Platform.pathSeparator)}',
          ).existsSync(),
          isFalse,
        );
      }
      expect(
        catalog.spots
            .expand((spot) => spot.media)
            .where(
              (media) =>
                  media.type == 'video' &&
                  YouTubeVideo.parse(media.sourceUrl)?.id == _videoId,
            ),
        isNotEmpty,
      );
    },
  );

  testWidgets(
    'existing hunting area remains the initial preview after setup additions',
    (tester) async {
      addTearDown(tester.view.reset);
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1200, 752);
      final spot = catalog.spots.singleWhere(
        (spot) => spot.id == 'edania-coral-crab-hunting',
      );
      Widget host() => MaterialApp(
        theme: companionTheme(),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 780,
              child: SpotMediaGallery(media: spot.media, height: 520),
            ),
          ),
        ),
      );
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();
      expect(
        _key('spot-media-image-${_assetRoot}edania_coral_crabs.png'),
        findsOneWidget,
      );
      final ordered = orderSpotMediaForDisplay(spot.media);
      final setup = ordered.indexWhere(
        (entry) =>
            entry.type == 'video' &&
            YouTubeVideo.parse(entry.url)?.id == _videoId &&
            YouTubeVideo.parse(entry.url)?.startSeconds == 858,
      );
      await _select(tester, setup);
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();
      expect(
        find.byType(SpotVideoPlayer),
        findsOneWidget,
        reason: 'Rebuilds retain the chosen guide chapter.',
      );
      expect(
        YouTubeVideo.parse(
          tester.widget<SpotVideoPlayer>(find.byType(SpotVideoPlayer)).videoUrl,
        )?.startSeconds,
        858,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final scenario in [
    (name: 'normal100', size: const Size(1200, 752), scale: 1.0),
    (name: 'enlarged200', size: const Size(760, 752), scale: 2.0),
  ]) {
    testWidgets(
      'Luneye guide chapters reach setup and comparison in ${scenario.name}',
      (tester) async {
        addTearDown(tester.view.reset);
        final shadows = debugDisableShadows;
        debugDisableShadows = false;
        try {
          final spot = catalog.spots.singleWhere(
            (spot) => spot.id == 'narcion-shadow-lion-hunting',
          );
          final media = orderSpotMediaForDisplay(spot.media);
          final sessions = <_FakeVideoSession>[];
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = scenario.size;
          await tester.pumpWidget(
            RepaintBoundary(
              key: _captureKey,
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: companionTheme(),
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.linear(scenario.scale)),
                  child: child!,
                ),
                home: Scaffold(
                  body: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: SizedBox(
                        width: 780,
                        child: SpotMediaGallery(
                          media: spot.media,
                          height: 520,
                          videoSessionFactory: () {
                            final session = _FakeVideoSession();
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
          await tester.pumpAndSettle();
          final setup = media.indexWhere(
            (entry) =>
                entry.type == 'video' &&
                YouTubeVideo.parse(entry.url)?.id == _videoId &&
                YouTubeVideo.parse(entry.url)?.startSeconds == 858,
          );
          expect(setup, greaterThanOrEqualTo(0));
          await _select(tester, setup);
          expect(find.byType(SpotVideoPlayer), findsOneWidget);
          expect(
            YouTubeVideo.parse(
              tester
                  .widget<SpotVideoPlayer>(find.byType(SpotVideoPlayer))
                  .videoUrl,
            )?.startSeconds,
            858,
          );
          await _capture(tester, 'luneye-matchlock-guide-${scenario.name}');
          await tester.tap(_key('spot-media-reference'));
          await tester.pumpAndSettle();
          await _capture(tester, 'luneye-reference-menu-${scenario.name}');
          for (var index = 0; index < media.length; index++) {
            await tester.ensureVisible(_key('spot-reference-option-$index'));
            await tester.pumpAndSettle();
            expect(
              _key('spot-reference-option-$index').hitTestable(),
              findsOneWidget,
            );
          }
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await tester.pumpAndSettle();
          expect(_key('spot-reference-option-0'), findsNothing);
          expect(
            tester.widget<Text>(_key('spot-media-title')).data,
            media[setup].title,
          );
          final comparison = media.indexWhere(
            (entry) =>
                entry.type == 'video' &&
                YouTubeVideo.parse(entry.url)?.id == _videoId &&
                YouTubeVideo.parse(entry.url)?.startSeconds == 1121,
          );
          expect(comparison, greaterThanOrEqualTo(0));
          await _select(tester, comparison);
          final player = tester.widget<SpotVideoPlayer>(
            find.byType(SpotVideoPlayer),
          );
          expect(YouTubeVideo.parse(player.videoUrl)?.startSeconds, 1121);
          expect(sessions.every((session) => session.plays == 0), isTrue);
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
}

bool _isNew(SpotMedia media) =>
    YouTubeVideo.parse(media.sourceUrl)?.id == _videoId;
Finder _key(String value) => find.byKey(ValueKey(value));
String _digest(Object? value) =>
    sha256.convert(utf8.encode(jsonEncode(_canonical(value)))).toString();
Object? _canonical(Object? value) {
  if (value is Map) {
    final keys = value.keys.cast<String>().toList()..sort();
    return {for (final key in keys) key: _canonical(value[key])};
  }
  if (value is List) return value.map(_canonical).toList();
  if (value is double && value.isFinite && value == value.truncateToDouble()) {
    return value.toInt();
  }
  return value;
}

Future<void> _select(WidgetTester tester, int index) async {
  await tester.tap(_key('spot-media-reference'));
  await tester.pumpAndSettle();
  await tester.ensureVisible(_key('spot-reference-option-$index'));
  await tester.pumpAndSettle();
  await tester.tap(_key('spot-reference-option-$index').hitTestable());
  await tester.pumpAndSettle();
}

Future<void> _capture(WidgetTester tester, String name) async {
  final directory = Platform.environment['LUNEYE_REFERENCE_CAPTURE_DIR'];
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

class _FakeVideoSession implements SpotVideoSession {
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
