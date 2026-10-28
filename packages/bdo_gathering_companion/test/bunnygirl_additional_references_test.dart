import 'dart:convert';

import 'package:bdo_gathering_companion/domain/bairog_benchmarks.dart';
import 'package:bdo_gathering_companion/domain/models.dart';
import 'package:bdo_gathering_companion/src/ui/field_guide.dart';
import 'package:bdo_gathering_companion/src/ui/theme.dart';
import 'package:bdo_gathering_companion/src/widgets/spot_map.dart';
import 'package:bdo_gathering_companion/src/widgets/spot_media_gallery.dart';
import 'package:bdo_gathering_companion/src/widgets/spot_video_player.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Catalog catalog;
  late Map<String, dynamic> source;
  late Map<String, dynamic> provenance;
  const references = {
    'edania-thuja-bunnygirl': 'JPVgR5G2eg4',
    'edania-marble-bunnygirl-guide': '6V_VpzpLnCk',
    'edania-basalt-magnetite-bunnygirl-guide': 'mHd91cpqw8o',
  };

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
  });

  test(
    'three creator references retain verified identity and scoped evidence',
    () {
      for (final entry in references.entries) {
        final spot = catalog.spots.singleWhere((spot) => spot.id == entry.key);
        final video = spot.media.singleWhere(
          (media) => YouTubeVideo.parse(media.url)?.id == entry.value,
        );
        expect(video.author, 'bunnygirl');
        expect(video.title, contains('Edania'));
        expect(
          video.sourceUrl,
          'https://www.youtube.com/watch?v=${entry.value}',
        );
        expect(video.publishedDate?.year, 2026);
        expect(video.publishedDate?.month, 8);
        expect(video.methodIds, spot.methodIds);
        final record = objectList(provenance['videos']).singleWhere(
          (record) =>
              YouTubeVideo.parse(textOf(record, 'url'))?.id == entry.value,
        );
        expect(record['spotId'], spot.id);
        expect(record['channelId'], 'UCbibEY3CZ_gna3FrA6vyB5w');
        expect(record['downloadedVideo'], isFalse);
        expect(record['languageEvidence'], contains('no caption tracks'));
        expect(record['limitations'], contains('No footage watched'));
        expect(record['evidenceSha256'], matches(RegExp(r'^[a-f0-9]{64}$')));
        expect(spot.guideLinks.any((link) => link['url'] == video.url), isTrue);
      }
    },
  );

  test(
    'related Thuja preserves inspected event images and separate Seoul rate',
    () {
      final spot = catalog.spots.singleWhere(
        (spot) => spot.id == 'edania-thuja-bunnygirl',
      );
      expect(spot.nodeName, 'Whispering Memorial');
      expect(spot.summary, 'Recorded during the minigame event.');
      expect(spot.media.where((media) => media.type == 'image'), hasLength(3));
      final videos = spot.media
          .where((media) => media.type == 'video')
          .toList();
      expect(videos, hasLength(2));
      expect(
        videos.map((media) => YouTubeVideo.parse(media.url)!.id),
        containsAll(['LuQYJzrKojE', 'JPVgR5G2eg4']),
      );
      expect(videos.last.title, startsWith('Related Edania Thuja guide'));
      final related = objectList(
        provenance['videos'],
      ).singleWhere((record) => textOf(record, 'url').contains('JPVgR5G2eg4'));
      expect(related['association'], contains('not a verified match'));
      final seoul = bairogBenchmarkSet.routes.singleWhere(
        (route) => route.sourceRouteId == 46,
      );
      expect(seoul.spotId, isNull);
      expect(seoul.gathersPerHour, 693);
      expect(seoul.sourceSilverAfterTaxPerHour, 1940000000);
      expect(seoul.videoUrl, 'https://youtu.be/lD-8E-PnIyE');
    },
  );

  test(
    'guide-only mining has no invented coordinates IDs or yield values',
    () async {
      for (final id in references.keys.where((id) => id.endsWith('-guide'))) {
        final spot = catalog.spots.singleWhere((spot) => spot.id == id);
        final raw = objectList(
          source['spots'],
        ).singleWhere((spot) => spot['id'] == id);
        expect(spot.region, 'Edania');
        expect(spot.methodIds, ['mining']);
        expect(spot.nodeName, isEmpty);
        expect(spot.mapped, isFalse);
        expect(spot.x, isNull);
        expect(spot.z, isNull);
        expect(spot.mapPrecision, 'unmapped');
        final expectedArtwork = id == 'edania-marble-bunnygirl-guide'
            ? 'assets/icons/items/4016.webp'
            : 'assets/icons/items/4017.webp';
        expect(spot.icon, expectedArtwork);
        expect(
          (await rootBundle.load(
            'packages/bdo_gathering_companion/$expectedArtwork',
          )).lengthInBytes,
          greaterThan(0),
        );
        expect(spot.requirements, isEmpty);
        for (final material in spot.materials) {
          expect(material['itemId'], isNull);
          expect(material.keys, isNot(contains('yieldPerHour')));
        }
        for (final key in [
          'worldX',
          'worldZ',
          'profit',
          'silverPerHour',
          'gathersPerHour',
          'yieldPerHour',
        ]) {
          expect(raw.containsKey(key), isFalse, reason: '$id/$key');
        }
        for (final goal in BairogBenchmarkGoal.values) {
          expect(bairogBenchmarkSet.bestForSpot(id, goal), isNull);
        }
        // Descriptive material labels must not become fabricated market identities.
        expect(
          catalog.lootForSpot(spot, 'mining').map((item) => item.name),
          isNot(contains(spot.displayName)),
        );
      }
    },
  );

  test('Marble and Basalt chapters point to the reviewed creator video', () {
    for (final id in references.keys.where((id) => id.endsWith('-guide'))) {
      final spot = catalog.spots.singleWhere((spot) => spot.id == id);
      final chapters = spot.guideLinks.where(
        (link) => textOf(link, 'label').contains('· 00:'),
      );
      expect(chapters, hasLength(2));
      expect(
        chapters.map(
          (link) => YouTubeVideo.parse(textOf(link, 'url'))!.startSeconds,
        ),
        [0, 47],
      );
      expect(
        chapters.every(
          (link) =>
              YouTubeVideo.parse(textOf(link, 'url'))!.id == references[id],
        ),
        isTrue,
      );
    }
  });

  for (final id in references.keys.where((id) => id.endsWith('-guide'))) {
    testWidgets('$id opens its reference with no map or borrowed earnings', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1200, 752);
      addTearDown(tester.view.reset);
      final spot = catalog.spots.singleWhere((spot) => spot.id == id);
      await tester.pumpWidget(
        MaterialApp(
          theme: companionTheme(),
          home: Scaffold(
            body: TickerMode(
              enabled: false, // No native video host, network or profile.
              child: FieldGuide(
                catalog: catalog,
                initialSpot: spot,
                onUse: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(SpotMap), findsNothing);
      final gallery = tester.widget<SpotMediaGallery>(
        find.byKey(ValueKey('guide-media-$id')),
      );
      expect(gallery.media, hasLength(1));
      expect(YouTubeVideo.parse(gallery.media.single.url)!.id, references[id]);
      expect(
        find.byKey(const ValueKey('bairog-selected-route-evidence')),
        findsNothing,
      );
      expect(find.textContaining('gathers/h'), findsNothing);
      expect(find.textContaining('silver/h'), findsNothing);
      expect(find.textContaining('0 per hour'), findsNothing);
      expect(find.text('Route tips'), findsOneWidget);
      expect(find.byKey(const ValueKey('use-spot')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
