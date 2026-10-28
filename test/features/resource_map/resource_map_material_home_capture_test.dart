import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/domain/state/planner_state.dart';
import 'package:bdo_craft_planner_flutter/features/resource_map/resource_map_theme_adapter.dart';
import 'package:bdo_craft_planner_flutter/visual/foundations/application_theme.dart';
import 'package:bdo_craft_planner_flutter/visual/foundations/theme_spec.dart';
import 'package:bdo_craft_planner_flutter/visual/illuminated_ledger/ledger_spec.dart';
import 'package:bdo_craft_planner_flutter/visual/sakura_night_garden/sakura_spec.dart';
import 'package:bdo_map_core/bdo_map_core.dart';
import 'package:bdo_map_core/src/widgets/map_canvas.dart';
import 'package:bdo_map_core/src/widgets/resource_map_discovery_home.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _sceneKey = ValueKey('resource-material-home-scene');
const _viewport = Size(1200, 752);
const _homeActions = <String, String>{
  'resource-map-home-find-material': 'Materials',
  'resource-map-home-worker-income': 'Workers',
  'resource-map-home-houses': 'Houses',
  'resource-map-home-saved': 'Saved',
  'resource-map-home-checklist': 'To-do list',
};
final _expectedNodeArtwork = <BdoNodeIconImageKey>{
  for (
    var type = bdoNodeIconTypeMinimum;
    type <= bdoNodeIconTypeMaximum;
    type++
  )
    for (final active in const [false, true])
      for (final highlighted in const [false, true])
        (sourceIconType: type, active: active, highlighted: highlighted),
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final themes = <String, ThemeSpec>{
    'sakura': SakuraNightGardenSpec.theme,
    'ledger': IlluminatedLedgerSpec.theme,
    'forest': applicationThemeForAppearance(
      AppearanceSettings.classicDefaultsFor(CraftMode.alchemy),
    ),
  };

  for (final theme in themes.entries) {
    for (final scale in const [1.0, 1.5]) {
      testWidgets(
        '${theme.key} full Resource Map home at ${(scale * 100).round()}% text retains geometry and state through opacity',
        (tester) async {
          final priorShadows = debugDisableShadows;
          debugDisableShadows = false;
          try {
            await tester.binding.setSurfaceSize(_viewport);
            addTearDown(() => tester.binding.setSurfaceSize(null));
            final fixture = (await tester.runAsync(() async {
              await _loadFonts();
              return (
                dataset: await BdoResourceMapLoader.loadBundled(),
                lodging: await LodgingDataLoader.loadBundled(),
                economics: await BdoWorkerEconomicsLoader.loadBundled(),
                tile: await _terrainTile(),
                cache: await Directory.systemTemp.createTemp(
                  'resource_material_home_',
                ),
              );
            }))!;
            final opacity = ValueNotifier(.7);
            final assets = _TrackedAssetBundle();
            var requests = 0;
            final client = MockClient((request) async {
              expect(request.url.host, 'example.test');
              requests++;
              return http.Response.bytes(
                fixture.tile,
                200,
                headers: {'content-type': 'image/png'},
              );
            });
            addTearDown(() async {
              await tester.pumpWidget(const SizedBox.shrink());
              await tester.pump();
              opacity.dispose();
              client.close();
              await tester.runAsync(() async {
                // This is only the unique temporary cache created above.
                for (var attempt = 0; attempt < 30; attempt++) {
                  try {
                    await fixture.cache.delete(recursive: true);
                    break;
                  } on FileSystemException {
                    if (attempt == 29) rethrow;
                    await Future<void>.delayed(
                      const Duration(milliseconds: 20),
                    );
                  }
                }
              });
            });
            final tileSource = BdoTileSource(
              id: 'material-home-${theme.key}-${(scale * 100).round()}',
              displayName: 'Generated terrain fixture',
              urlTemplate: 'https://example.test/{z}/{x}_{y}.png',
              worldBounds: BdoTileSource.workermanCommunity.worldBounds,
              attribution: 'Generated headless test fixture',
              usageNotice: 'No remote tiles or personal state.',
              fileExtension: 'png',
            );
            await tester.pumpWidget(
              MaterialApp(
                theme: ThemeData(
                  fontFamily: 'Segoe UI',
                  platform: TargetPlatform.windows,
                ),
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!,
                ),
                home: DefaultAssetBundle(
                  bundle: assets,
                  child: ValueListenableBuilder<double>(
                    valueListenable: opacity,
                    builder: (context, value, _) => ResourceMapThemeAdapter(
                      spec: theme.value,
                      uiOpacity: value,
                      child: RepaintBoundary(
                        key: _sceneKey,
                        child: BdoResourceMap(
                          dataset: fixture.dataset,
                          lodgingDataset: fixture.lodging,
                          workerEconomics: fixture.economics,
                          cacheDirectory: fixture.cache,
                          tileHttpClient: client,
                          tileSource: tileSource,
                          showSourceNotice: false,
                          uiOpacity: value,
                          onUiOpacityChanged: (value) => opacity.value = value,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
            await _settleScene(tester, assets, () => requests);
            final mapState = tester.state(find.byType(BdoResourceMap));
            final discoveryState = tester.state(
              find.byType(ResourceMapDiscoveryHome),
            );
            final canvasState = tester.state(find.byType(BdoMapCanvas));
            final canvas = tester.widget<BdoMapCanvas>(
              find.byType(BdoMapCanvas),
            );
            final camera = canvas.cameraController;
            final position = _cameraValues(camera.camera);
            final manager = canvas.tileManager;
            final initialRequests = requests;
            final initialRevision = manager.decodedTileRevision;
            final nodeArtwork = _mapPainter(tester).nodeIconImages;
            final tiles = {
              for (final coordinate in manager.visibleCoordinates)
                coordinate: manager.tile(coordinate)!.image,
            };
            final initialBounds = _homeBounds(tester);
            final frames = <Map<String, Object?>>[];
            Uint8List? initialPixels;

            for (final step in const [
              (name: '70', opacity: .7),
              (name: '0', opacity: 0.0),
              (name: '100', opacity: 1.0),
              (name: '70-return', opacity: .7),
            ]) {
              if (opacity.value != step.opacity) {
                // Invoke the actual visible slider's callback; do not replace
                // the map or manufacture its navigation/material composition.
                tester.widget<Slider>(_opacitySlider).onChanged!(step.opacity);
              }
              await _settleScene(tester, assets, () => requests);
              expect(tester.takeException(), isNull);
              expect(find.text('Atlas'), findsNothing);
              final title = find.text('Resource Map');
              expect(title.hitTestable(), findsOneWidget);
              expect(tester.widget<Text>(title).data, 'Resource Map');
              expect(tester.widget<Text>(title).style?.fontSize, 17);
              final titleParagraph = tester.renderObject<RenderParagraph>(
                find.descendant(of: title, matching: find.byType(RichText)),
              );
              expect(titleParagraph.text.toPlainText(), 'Resource Map');
              expect(titleParagraph.didExceedMaxLines, isFalse);
              expect(titleParagraph.overflow, isNot(TextOverflow.ellipsis));
              if (scale == 1) {
                expect(tester.getSize(title).height, lessThanOrEqualTo(32));
              }
              for (final action in _homeActions.entries) {
                final finder = find.byKey(ValueKey(action.key));
                expect(finder.hitTestable(), findsOneWidget);
                expect(
                  find.descendant(
                    of: finder,
                    matching: find.text(action.value),
                  ),
                  findsOneWidget,
                );
              }
              expect(
                find
                    .byKey(const ValueKey('resource-map-home-more-tools'))
                    .hitTestable(),
                findsOneWidget,
              );
              expect(find.byType(BackdropFilter), findsNothing);
              expect(tester.widget<Slider>(_opacitySlider).value, step.opacity);
              final bounds = _homeBounds(tester);
              _expectStableHomeBounds(bounds, initialBounds);
              if (step.name == '70-return') {
                expect(bounds, initialBounds);
              }
              final after = tester.widget<BdoMapCanvas>(
                find.byType(BdoMapCanvas),
              );
              expect(tester.state(find.byType(BdoResourceMap)), same(mapState));
              expect(
                tester.state(find.byType(ResourceMapDiscoveryHome)),
                same(discoveryState),
              );
              expect(
                tester.state(find.byType(BdoMapCanvas)),
                same(canvasState),
              );
              expect(after.cameraController, same(camera));
              expect(after.tileManager, same(manager));
              expect(_cameraValues(camera.camera), position);
              expect(requests, initialRequests);
              expect(manager.decodedTileRevision, initialRevision);
              expect(_mapPainter(tester).nodeIconImages, same(nodeArtwork));
              for (final entry in tiles.entries) {
                expect(manager.tile(entry.key)!.image, same(entry.value));
              }
              final name =
                  'resource-home-${theme.key}-text${(scale * 100).round()}-opacity${step.name}';
              final pixels = await _capture(tester, name);
              final probes = _materialProbes(tester, pixels);
              if (step.name == '70') {
                initialPixels = pixels;
                for (final probe in probes.take(3)) {
                  expect(
                    probe['rgbDistance'] as double,
                    greaterThan(3),
                    reason:
                        '${probe['action']} artwork bay must be visibly '
                        'distinct from its reading face in the assembled rail.',
                  );
                }
              } else if (step.name == '70-return') {
                expect(_differentPixels(initialPixels!, pixels), 0);
              }
              frames.add({
                'capture': '$name.png',
                'opacity': step.opacity,
                'step': step.name,
                'bounds': bounds,
                'probes': probes,
                'camera': _cameraValues(camera.camera),
                'requests': requests,
                'retainedMapDiscoveryCameraTiles': true,
              });
            }
            final output = Platform.environment['MATERIAL_MATCH_CAPTURE_DIR'];
            if (output != null) {
              await tester.runAsync(() async {
                final directory = Directory(output);
                await directory.create(recursive: true);
                await File(
                  '${directory.path}/resource-home-${theme.key}-text${(scale * 100).round()}.json',
                ).writeAsString(
                  const JsonEncoder.withIndent('  ').convert({
                    'fixture':
                        'Full production BdoResourceMap with bundled '
                        'dataset, lodging, economics, artwork and fonts.',
                    'theme': theme.key,
                    'textScale': scale,
                    'viewport': [_viewport.width, _viewport.height],
                    'terrain':
                        'Deterministic generated PNG via MockClient; '
                        'fresh isolated temporary tile cache.',
                    'allVisibleControlsChecked': true,
                    'outerGeometryUnchangedAcrossOpacity': true,
                    'sliderOriginAndHeightUnchanged': true,
                    'sliderWidthTracksPercentageLabel': true,
                    'exactGeometryAfterOpacityReturn': true,
                    'samePixelsAfterOpacityReturn': true,
                    'profileOrNetworkAccess': false,
                    'limitations': [
                      'Headless Flutter image replay, not Windows or monitor '
                          'presentation verification.',
                      'Generated terrain is not the production remote map.',
                      'RGB probes sample clear regions of actual assembled '
                          'bays/faces; they are not a theme-match or universal '
                          'contrast guarantee.',
                    ],
                    'frames': frames,
                  }),
                );
              });
            }
          } finally {
            debugDisableShadows = priorShadows;
          }
        },
      );
    }
  }
}

Finder get _opacitySlider =>
    find.byKey(const ValueKey('resource-map-ui-opacity-slider'));

Map<String, double> _cameraValues(BdoMapCamera camera) => {
  'x': camera.center.x,
  'y': camera.center.y,
  'zoom': camera.zoom,
};

Map<String, List<double>> _homeBounds(WidgetTester tester) {
  final result = <String, List<double>>{};
  void record(String name, Finder finder) {
    final rect = tester.getRect(finder);
    expect(rect.left, greaterThanOrEqualTo(0));
    expect(rect.top, greaterThanOrEqualTo(0));
    expect(rect.right, lessThanOrEqualTo(_viewport.width));
    expect(rect.bottom, lessThanOrEqualTo(_viewport.height));
    result[name] = [rect.left, rect.top, rect.width, rect.height];
  }

  final desk = find.byKey(const ValueKey('resource-map-field-desk'));
  record('desk', desk);
  record('title', find.text('Resource Map'));
  record('search', find.descendant(of: desk, matching: find.byType(TextField)));
  record('opacity', _opacitySlider);
  record(
    'opacityRow',
    find.byKey(const ValueKey('resource-map-ui-opacity-control')),
  );
  for (final key in _homeActions.keys) {
    record(key, find.byKey(ValueKey(key)));
  }
  for (final paragraph in tester.renderObjectList<RenderParagraph>(
    find.descendant(of: desk, matching: find.byType(RichText)),
  )) {
    expect(paragraph.didExceedMaxLines, isFalse);
  }
  return result;
}

void _expectStableHomeBounds(
  Map<String, List<double>> current,
  Map<String, List<double>> initial,
) {
  expect(current.keys, unorderedEquals(initial.keys));
  for (final entry in initial.entries) {
    if (entry.key != 'opacity') {
      expect(current[entry.key], entry.value, reason: entry.key);
    }
  }
  final slider = current['opacity']!;
  final originalSlider = initial['opacity']!;
  final row = initial['opacityRow']!;
  // The existing Row gives the percentage label its natural width. Its
  // one/two/three digits may alter only the remaining Slider width, not the
  // control's origin, height, surrounding rail, or content placement.
  expect(slider[0], originalSlider[0]);
  expect(slider[1], originalSlider[1]);
  expect(slider[3], originalSlider[3]);
  expect(slider[2], greaterThan(0));
  expect(slider[0], greaterThanOrEqualTo(row[0]));
  expect(slider[1], greaterThanOrEqualTo(row[1]));
  expect(slider[0] + slider[2], lessThanOrEqualTo(row[0] + row[2]));
  expect(slider[1] + slider[3], lessThanOrEqualTo(row[1] + row[3]));
}

List<Map<String, Object>> _materialProbes(
  WidgetTester tester,
  Uint8List pixels,
) {
  List<double> sample(Offset center) {
    final channels = [0.0, 0.0, 0.0];
    for (var dy = -1; dy <= 1; dy++) {
      for (var dx = -1; dx <= 1; dx++) {
        final x = center.dx.floor() + dx, y = center.dy.floor() + dy;
        final offset = (y * _viewport.width.toInt() + x) * 4;
        for (var channel = 0; channel < 3; channel++) {
          channels[channel] += pixels[offset + channel] / 9;
        }
      }
    }
    return channels;
  }

  return [
    for (final entry in _homeActions.entries)
      (() {
        final rect = tester.getRect(find.byKey(ValueKey(entry.key)));
        // Both patches are below the artwork/text and above the bottom rim.
        final bayPoint = Offset(rect.left + 21, rect.bottom - 6);
        final bodyPoint = Offset(rect.right - 22, rect.bottom - 6);
        final bay = sample(bayPoint), body = sample(bodyPoint);
        final distance = math.sqrt(
          List.generate(
            3,
            (i) => math.pow(bay[i] - body[i], 2),
          ).fold<double>(0, (total, value) => total + value.toDouble()),
        );
        return <String, Object>{
          'action': entry.value,
          'bayPoint': [bayPoint.dx, bayPoint.dy],
          'bodyPoint': [bodyPoint.dx, bodyPoint.dy],
          'bayMeanRgb': bay,
          'bodyMeanRgb': body,
          'rgbDistance': distance,
        };
      })(),
  ];
}

class _TrackedAssetBundle extends CachingAssetBundle {
  int pending = 0;

  @override
  Future<ByteData> load(String key) async {
    pending++;
    try {
      return await rootBundle.load(key);
    } finally {
      pending--;
    }
  }
}

BdoMapPainter _mapPainter(WidgetTester tester) => tester
    .widgetList<CustomPaint>(
      find.descendant(
        of: find.byType(BdoMapCanvas),
        matching: find.byType(CustomPaint),
      ),
    )
    .map((paint) => paint.painter)
    .whereType<BdoMapPainter>()
    .single;

Future<void> _settleScene(
  WidgetTester tester,
  _TrackedAssetBundle assets,
  int Function() requestCount,
) async {
  final watch = Stopwatch()..start();
  var stable = 0, previousRequests = -1;
  while (watch.elapsed < const Duration(seconds: 20)) {
    await tester.pump(const Duration(milliseconds: 32));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    final manager = tester
        .widget<BdoMapCanvas>(find.byType(BdoMapCanvas))
        .tileManager;
    final nodeImages = _mapPainter(tester).nodeIconImages;
    final artwork = tester.widgetList<RawImage>(find.byType(RawImage)).toList();
    final ready =
        requestCount() > 0 &&
        manager.visibleCoordinates.isNotEmpty &&
        manager.visibleCoordinates.every((key) => manager.tile(key) != null) &&
        manager.activeRequestCount == 0 &&
        manager.queuedRequestCount == 0 &&
        nodeImages.length == _expectedNodeArtwork.length &&
        _expectedNodeArtwork.every(nodeImages.containsKey) &&
        assets.pending == 0 &&
        artwork.length >= 3 &&
        artwork.every((item) => item.image != null) &&
        PaintingBinding.instance.imageCache.pendingImageCount == 0 &&
        tester.binding.transientCallbackCount == 0 &&
        !tester.binding.hasScheduledFrame;
    stable = ready && previousRequests == requestCount() ? stable + 1 : 0;
    previousRequests = requestCount();
    if (stable == 3) return;
  }
  throw TestFailure('Full Resource Map home did not settle in 20 seconds.');
}

Future<Uint8List> _capture(WidgetTester tester, String name) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_sceneKey),
  );
  expect(boundary.debugNeedsPaint, isFalse);
  return (await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      expect(image.width, _viewport.width.toInt());
      expect(image.height, _viewport.height.toInt());
      final rgba = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      final output = Platform.environment['MATERIAL_MATCH_CAPTURE_DIR'];
      if (output != null) {
        await Directory(output).create(recursive: true);
        final png = (await image.toByteData(format: ui.ImageByteFormat.png))!;
        await File(
          '$output/$name.png',
        ).writeAsBytes(Uint8List.sublistView(png));
      }
      return Uint8List.fromList(Uint8List.sublistView(rgba));
    } finally {
      image.dispose();
    }
  }))!;
}

int _differentPixels(Uint8List left, Uint8List right) {
  expect(left.length, right.length);
  var count = 0;
  for (var i = 0; i < left.length; i += 4) {
    if (left[i] != right[i] ||
        left[i + 1] != right[i + 1] ||
        left[i + 2] != right[i + 2] ||
        left[i + 3] != right[i + 3]) {
      count++;
    }
  }
  return count;
}

Future<void> _loadFonts() async {
  if (Platform.isWindows) {
    final windows = Platform.environment['WINDIR'] ?? 'C:/Windows';
    for (final entry in {
      'Segoe UI': ['segoeui.ttf', 'seguisb.ttf', 'segoeuib.ttf'],
      'Georgia': ['georgia.ttf', 'georgiab.ttf'],
    }.entries) {
      final loader = FontLoader(entry.key);
      for (final name in entry.value) {
        loader.addFont(
          File('$windows/Fonts/$name').readAsBytes().then(ByteData.sublistView),
        );
      }
      await loader.load();
    }
  }
  var sdk = File(Platform.resolvedExecutable).parent;
  while (!Directory(
    '${sdk.path}/bin/cache/artifacts/material_fonts',
  ).existsSync()) {
    if (sdk.parent.path == sdk.path) {
      throw StateError('Flutter fonts not found.');
    }
    sdk = sdk.parent;
  }
  for (final entry in {
    'Roboto': ['roboto-regular.ttf', 'roboto-bold.ttf'],
    'MaterialIcons': ['materialicons-regular.otf'],
  }.entries) {
    final loader = FontLoader(entry.key);
    for (final name in entry.value) {
      loader.addFont(
        File(
          '${sdk.path}/bin/cache/artifacts/material_fonts/$name',
        ).readAsBytes().then(ByteData.sublistView),
      );
    }
    await loader.load();
  }
}

Future<Uint8List> _terrainTile() async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, 256, 256),
    Paint()..color = const Color(0xFF385051),
  );
  canvas.drawPath(
    Path()
      ..moveTo(0, 110)
      ..cubicTo(76, 70, 103, 164, 174, 77)
      ..cubicTo(211, 22, 251, 82, 256, 58)
      ..lineTo(256, 256)
      ..lineTo(0, 256)
      ..close(),
    Paint()..color = const Color(0xFF7E806A),
  );
  canvas.drawPath(
    Path()
      ..moveTo(0, 213)
      ..cubicTo(71, 109, 164, 245, 256, 123),
    Paint()
      ..color = const Color(0xFFE2CA9A)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3,
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(256, 256);
  try {
    final data = (await image.toByteData(format: ui.ImageByteFormat.png))!;
    return Uint8List.fromList(Uint8List.sublistView(data));
  } finally {
    image.dispose();
    picture.dispose();
  }
}
