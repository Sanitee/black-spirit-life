import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bdo_map_core/bdo_map_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const writePreview = bool.fromEnvironment('BSL_VENDOR_PORTRAIT_PREVIEW');
  late BdoResourceMapDataset dataset;
  late List<int> previewTile;

  setUpAll(() async {
    await _loadReviewFonts();
    dataset = await BdoResourceMapLoader.loadBundled();
    previewTile = await _makePreviewTile();
  });

  testWidgets(
    'writes the real David Finto and Salt vendor-card preview',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 752));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      const davidId = 'npc:40013:1:location:0';
      final david = dataset.vendorNpcsById[davidId]!;
      final davidSalt = dataset
          .vendorListingsForItem('Salt')
          .singleWhere((listing) => listing.vendorId == davidId);
      final focusedDataset = BdoResourceMapDataset(
        manifest: dataset.manifest,
        resources: dataset.resources,
        workerNodes: dataset.workerNodes,
        gatheringSpots: dataset.gatheringSpots,
        gatheringPoints: dataset.gatheringPoints,
        gatheringRoutes: dataset.gatheringRoutes,
        fieldSources: dataset.fieldSources,
        vendorNpcs: <BdoVendorNpc>[david],
        vendorListings: <BdoVendorListing>[davidSalt],
      );
      final appData =
          jsonDecode(File('assets/data/app-data.json').readAsStringSync())
              as Map<String, dynamic>;
      final saltDataUri =
          (appData['itemIcons']! as Map<String, dynamic>)['Salt']! as String;
      final saltIcon = base64Decode(saltDataUri.split(',').last);
      final davidPortraitAsset = bdoBundledVendorPortraitAsset(
        david.sourceVendorId,
      )!;
      final davidPortrait = (await rootBundle.load(
        davidPortraitAsset,
      )).buffer.asUint8List();
      final tileClient = MockClient(
        (request) async => http.Response.bytes(
          previewTile,
          HttpStatus.ok,
          headers: const <String, String>{'content-type': 'image/png'},
        ),
      );
      addTearDown(tileClient.close);
      final cache = Directory.systemTemp.createTempSync(
        'bsl_vendor_portrait_preview_',
      );
      addTearDown(() async {
        if (cache.existsSync()) await cache.delete(recursive: true);
      });
      final controller = BdoResourceMapController()
        ..focus(
          const BdoResourceMapFocusRequest(
            materialName: 'Salt',
            source: BdoResourceMapFocusSource.npcVendors,
          ),
        );
      addTearDown(controller.dispose);
      final tileSource = BdoTileSource(
        id: 'vendor-portrait-review',
        displayName: 'Vendor portrait review',
        urlTemplate: 'https://preview.invalid/{z}/{x}_{y}.png',
        worldBounds: BdoTileSource.workermanCommunity.worldBounds,
        attribution: 'Generated terrain for visual review',
        usageNotice: 'Visual review only.',
        fileExtension: 'png',
      );
      const rootKey = ValueKey<String>('vendor-portrait-preview-root');

      await tester.pumpWidget(
        RepaintBoundary(
          key: rootKey,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData.dark(useMaterial3: true).copyWith(
              textTheme: ThemeData.dark().textTheme.apply(
                fontFamily: 'Segoe UI',
              ),
            ),
            home: MediaQuery(
              data: const MediaQueryData(disableAnimations: true),
              child: ResourceMapChromeTheme(
                data: ResourceMapChromeThemeData.sakuraCartographer,
                child: BdoResourceMap(
                  dataset: focusedDataset,
                  cacheDirectory: cache,
                  tileSource: tileSource,
                  tileHttpClient: tileClient,
                  showSourceNotice: false,
                  controller: controller,
                  vendorItemIconBuilder: (context, itemName, size) =>
                      Image.memory(
                        saltIcon,
                        width: size,
                        height: size,
                        fit: BoxFit.cover,
                        filterQuality: FilterQuality.high,
                      ),
                  vendorPortraitBuilder: (context, vendor, size) {
                    return Image.memory(
                      davidPortrait,
                      width: size,
                      height: size,
                      alignment: Alignment.bottomCenter,
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.high,
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      );
      for (var frame = 0; frame < 20; frame += 1) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      final marker = find.byKey(
        const ValueKey<String>('resource-map-vendor-marker-$davidId'),
      );
      await tester.tap(
        find.descendant(of: marker, matching: find.byType(InkResponse)),
      );
      for (var frame = 0; frame < 6; frame += 1) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('David Finto'), findsOneWidget);
      expect(find.text('Salt'), findsWidgets);

      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(rootKey),
      );
      final image = await boundary.toImage(pixelRatio: 1);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      final output = File(
        'build/private-ui-previews/'
        'review_sakura_salt_vendor_david_portrait_1200x752.png',
      );
      output.parent.createSync(recursive: true);
      output.writeAsBytesSync(bytes!.buffer.asUint8List(), flush: true);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
    skip: !writePreview,
  );
}

Future<void> _loadReviewFonts() async {
  if (!Platform.isWindows) return;
  final windowsRoot =
      Platform.environment['WINDIR'] ??
      Platform.environment['SystemRoot'] ??
      r'C:\Windows';
  final windowsFonts = Directory(
    windowsRoot,
  ).uri.resolve('Fonts/').toFilePath();
  final materialFonts = _flutterMaterialFontsDirectory();
  await _loadFontFamily('Segoe UI', <String>[
    '$windowsFonts${Platform.pathSeparator}segoeui.ttf',
    '$windowsFonts${Platform.pathSeparator}seguisb.ttf',
    '$windowsFonts${Platform.pathSeparator}segoeuib.ttf',
  ]);
  await _loadFontFamily('MaterialIcons', <String>[
    '$materialFonts${Platform.pathSeparator}materialicons-regular.otf',
  ]);
}

String _flutterMaterialFontsDirectory() {
  final candidates = <Directory>[];
  final configured = Platform.environment['FLUTTER_ROOT']?.trim();
  if (configured != null && configured.isNotEmpty) {
    candidates.add(Directory(configured));
  }
  var ancestor = File(Platform.resolvedExecutable).parent;
  while (true) {
    candidates.add(ancestor);
    final parent = ancestor.parent;
    if (parent.path == ancestor.path) break;
    ancestor = parent;
  }
  for (final candidate in candidates) {
    final path = candidate.uri
        .resolve('bin/cache/artifacts/material_fonts/')
        .toFilePath();
    if (Directory(path).existsSync()) return path;
  }
  throw StateError('Could not locate Flutter material fonts.');
}

Future<void> _loadFontFamily(String family, List<String> paths) async {
  final loader = FontLoader(family);
  for (final path in paths) {
    loader.addFont(
      File(path).readAsBytes().then(
        (bytes) => ByteData.sublistView(Uint8List.fromList(bytes)),
      ),
    );
  }
  await loader.load();
}

Future<List<int>> _makePreviewTile() async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  const size = Size.square(256);
  canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF24363A));
  final land = Path()
    ..moveTo(0, 202)
    ..cubicTo(28, 159, 62, 182, 91, 125)
    ..cubicTo(131, 48, 175, 112, 208, 57)
    ..cubicTo(228, 23, 244, 41, 256, 25)
    ..lineTo(256, 256)
    ..lineTo(0, 256)
    ..close();
  canvas.drawPath(land, Paint()..color = const Color(0xFF4D5C4B));
  canvas.drawPath(
    land,
    Paint()
      ..color = const Color(0xFF879171)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2,
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(256, 256);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  picture.dispose();
  return bytes!.buffer.asUint8List();
}
