import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bdo_gathering_companion/domain/bairog_benchmarks.dart';
import 'package:bdo_gathering_companion/domain/models.dart';
import 'package:bdo_gathering_companion/src/ui/field_guide.dart';
import 'package:bdo_gathering_companion/src/ui/theme.dart';
import 'package:bdo_gathering_companion/src/widgets/spot_map.dart';
import 'package:bdo_gathering_companion/src/widgets/spot_media_gallery.dart';
import 'package:bdo_gathering_companion/src/widgets/spot_video_player.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Catalog catalog;
  late Spot spot;
  setUpAll(() async {
    catalog = await Catalog.load();
    spot = catalog.spots.singleWhere(
      (entry) => entry.id == 'edania-thuja-bunnygirl',
    );
    if (Platform.isWindows) {
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
  });

  test(
    'creator Edania reference does not borrow the Seoul benchmark or pin',
    () {
      expect(spot.region, 'Edania');
      expect(spot.nodeName, 'Whispering Memorial');
      expect(spot.mapped, isFalse);
      expect(spot.x, isNull);
      expect(spot.z, isNull);
      expect(spot.mapPrecision, 'unmapped');
      expect(spot.mapNote, contains('exact map coordinates are not verified'));
      final video = spot.media.singleWhere(
        (media) => YouTubeVideo.parse(media.url)?.id == 'LuQYJzrKojE',
      );
      expect(YouTubeVideo.parse(video.url)!.id, 'LuQYJzrKojE');
      expect(video.author, 'bunnygirl');
      expect(video.publishedDate, DateTime(2026, 9, 10));
      expect(video.title, contains('minigame-event reference'));
      expect(spot.tips, contains(contains('two channels')));
      expect(spot.tips, contains(contains('alternatives or event-only')));
      expect(spot.tips.join(' '), isNot(contains('4.35')));
      expect(
        bairogBenchmarkSet.routes.where((route) => route.spotId == spot.id),
        isEmpty,
      );
      final seoul = bairogBenchmarkSet.routes.singleWhere(
        (route) => route.sourceRouteId == 46,
      );
      expect(seoul.sourceRouteName, 'Seoul Thuja sap');
      expect(seoul.spotId, isNull);
      expect(seoul.gathersPerHour, 693);
      expect(seoul.sourceSilverAfterTaxPerHour, 1940000000);
      expect(seoul.videoUrl, 'https://youtu.be/lD-8E-PnIyE');
    },
  );

  test('both real tools keep method-specific Thuja and Nostos rewards', () {
    expect(spot.methodIds, ['fluid', 'lumbering']);
    final sap = catalog
        .lootForSpot(spot, 'fluid')
        .map((item) => item.id)
        .toSet();
    final timber = catalog
        .lootForSpot(spot, 'lumbering')
        .map((item) => item.id)
        .toSet();
    expect(sap, containsAll(['5020', '821349']));
    expect(sap, isNot(contains(anyOf('4616', '4605', '821348'))));
    expect(timber, containsAll(['4616', '4605', '821348']));
    expect(timber, isNot(contains(anyOf('5020', '821349'))));
    expect(catalog.lootForSpot(spot, 'hunting'), isEmpty);
    expect(
      catalog.methods.singleWhere((method) => method.id == 'fluid').icon,
      contains('fluid_collector'),
    );
  });

  test(
    'rotation and setup captures keep original source bytes and timestamp attribution',
    () async {
      final raw = objectMap(
        jsonDecode(
          await rootBundle.loadString(
            'packages/bdo_gathering_companion/assets/rotations/provenance.json',
          ),
        ),
      );
      final records = objectList(
        raw['images'],
      ).where((entry) => entry['spotId'] == spot.id).toList();
      expect(records, hasLength(3));
      final images = orderSpotMediaForDisplay(
        spot.media,
      ).where((media) => media.type == 'image').toList();
      expect(
        images.first.asset,
        'assets/rotations/bunnygirl_edania_thuja_rotation.png',
      );
      for (final reference in images) {
        final record = records.singleWhere(
          (entry) => entry['asset'] == reference.asset,
        );
        final bytes = await rootBundle.load(reference.asset);
        expect(bytes.lengthInBytes, record['bytes']);
        expect(
          sha256
              .convert(
                bytes.buffer.asUint8List(
                  bytes.offsetInBytes,
                  bytes.lengthInBytes,
                ),
              )
              .toString(),
          record['sha256'],
        );
        expect(reference.author, 'bunnygirl');
        expect(reference.methodIds, ['fluid', 'lumbering']);
        expect(reference.sourceUrl, contains('LuQYJzrKojE&t='));
        final codec = await ui.instantiateImageCodec(
          bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
        );
        final frame = await codec.getNextFrame();
        expect(frame.image.width, 2560);
        expect(frame.image.height, 1440);
        frame.image.dispose();
        codec.dispose();
      }
      final icon = await rootBundle.load('assets/icons/items/4616.webp');
      expect(
        sha256
            .convert(
              icon.buffer.asUint8List(icon.offsetInBytes, icon.lengthInBytes),
            )
            .toString(),
        'a956d72305e8eba81e5952979b14bf098a4812996ed3c78767319fc904987aa9',
      );
    },
  );

  testWidgets('setup references are not labelled as maps', (tester) async {
    for (final entry in <String, String>{
      'Starter setup options': 'Setup',
      'Extra buff options': 'Buffs',
      'Thuja rotation': 'Rotation',
      'Hunting area': 'Hunting area',
      'Regional reference': 'Map',
    }.entries) {
      await tester.pumpWidget(
        MaterialApp(
          theme: companionTheme(),
          home: Scaffold(
            body: SpotMediaGallery(
              key: ValueKey(entry.key),
              media: [
                SpotMedia({
                  'type': 'image',
                  'title': entry.key,
                  'asset':
                      'assets/rotations/bunnygirl_edania_thuja_rotation.png',
                }),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(entry.value), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets(
      'unmapped Thuja guide displays real reference without a false map at $scale text',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(scale == 1 ? 1500 : 1000, 1000);
        addTearDown(tester.view.reset);
        final used = <Spot>[];
        await tester.pumpWidget(
          MaterialApp(
            theme: companionTheme(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(scale),
                disableAnimations: true,
              ),
              child: child!,
            ),
            home: RepaintBoundary(
              key: const ValueKey('thuja-guide-capture'),
              child: Scaffold(
                body: TickerMode(
                  enabled:
                      false, // Never starts the embedded video or its native profile.
                  child: FieldGuide(
                    catalog: catalog,
                    initialSpot: spot,
                    onUse: used.add,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(SpotMap), findsNothing);
        expect(
          find.byKey(const ValueKey('unmapped-spot-guide-notes')),
          findsOneWidget,
        );
        expect(find.text('Route tips'), findsOneWidget);
        expect(find.textContaining('two channels'), findsNothing);
        expect(
          find.text('Recorded during the minigame event.'),
          findsOneWidget,
        );
        final gallery = tester.widget<SpotMediaGallery>(
          find.byKey(ValueKey('guide-media-${spot.id}')),
        );
        expect(gallery.media, hasLength(5));
        expect(find.byType(SpotVideoPlayer), findsNothing);
        final image = find.byWidgetPredicate(
          (widget) =>
              widget is Image &&
              widget.image is AssetImage &&
              (widget.image as AssetImage).assetName.endsWith(
                'bunnygirl_edania_thuja_rotation.png',
              ),
        );
        expect(image, findsOneWidget);
        expect(tester.getTopLeft(image).dy, lessThan(scale == 1 ? 250 : 400));
        expect(tester.getBottomLeft(image).dy, lessThan(850));
        for (final element in find.byType(Image).evaluate()) {
          await tester.runAsync(
            () => precacheImage((element.widget as Image).image, element),
          );
        }
        await tester.pumpAndSettle();
        final captureRoot =
            Platform.environment['GATHERING_CONTENT_CAPTURE_DIR'];
        if (captureRoot != null) {
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(const ValueKey('thuja-guide-capture')),
          );
          await tester.runAsync(() async {
            final capture = await boundary.toImage(pixelRatio: 1);
            final bytes = (await capture.toByteData(
              format: ui.ImageByteFormat.png,
            ))!;
            await File(
              '$captureRoot${Platform.pathSeparator}gathering-thuja-reference-verified-text${(scale * 100).round()}.png',
            ).writeAsBytes(
              bytes.buffer.asUint8List(
                bytes.offsetInBytes,
                bytes.lengthInBytes,
              ),
            );
            capture.dispose();
          });
        }
        final routeTips = find.byKey(
          const ValueKey('unmapped-spot-guide-notes'),
        );
        await tester.ensureVisible(routeTips);
        await tester.tap(find.text('Route tips'));
        await tester.pumpAndSettle();
        expect(find.textContaining('two channels'), findsOneWidget);
        expect(
          find.textContaining('alternatives or event-only'),
          findsOneWidget,
        );
        expect(find.textContaining('Helix Elixir'), findsOneWidget);
        final prepare = find.byKey(const ValueKey('use-spot'));
        await tester.ensureVisible(prepare);
        await tester.tap(prepare);
        await tester.pumpAndSettle();
        expect(used.single.id, spot.id);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
