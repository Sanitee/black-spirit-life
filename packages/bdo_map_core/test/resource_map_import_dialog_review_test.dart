import 'dart:io';
import 'dart:ui' as ui;

import 'package:bdo_map_core/bdo_map_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    if (!Platform.isWindows) return;
    final windows = Platform.environment['WINDIR'] ?? 'C:/Windows';
    await (FontLoader('Segoe UI')..addFont(
          File(
            '$windows/Fonts/segoeui.ttf',
          ).readAsBytes().then(ByteData.sublistView),
        ))
        .load();
    var sdk = File(Platform.resolvedExecutable).parent;
    while (!Directory(
      '${sdk.path}/bin/cache/artifacts/material_fonts',
    ).existsSync()) {
      if (sdk.parent.path == sdk.path) {
        throw StateError('Flutter font not found');
      }
      sdk = sdk.parent;
    }
    await (FontLoader('MaterialIcons')..addFont(
          File(
            '${sdk.path}/bin/cache/artifacts/material_fonts/'
            'MaterialIcons-Regular.otf',
          ).readAsBytes().then(ByteData.sublistView),
        ))
        .load();
  });

  for (final scale in [1.0, 2.0]) {
    for (final recording in [false, true]) {
      testWidgets(
        'import ${recording ? 'recording' : 'screenshot'} at $scale',
        (tester) async {
          await tester.binding.setSurfaceSize(const Size(1000, 820));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          final dataset = _dataset();
          final key = GlobalKey();
          await tester.pumpWidget(
            MaterialApp(
              theme: ThemeData.dark(useMaterial3: true).copyWith(
                colorScheme: ColorScheme.fromSeed(
                  seedColor: ResourceMapChromeThemeData.glassDock.primary,
                  brightness: Brightness.dark,
                ),
                textTheme: ThemeData.dark().textTheme.apply(
                  fontFamily: 'Segoe UI',
                ),
              ),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(scale)),
                child: RepaintBoundary(key: key, child: child!),
              ),
              home: ResourceMapChromeTheme(
                data: ResourceMapChromeThemeData.glassDock,
                child: Scaffold(
                  body: recording
                      ? BdoActiveNodeRecordingImportDialog(
                          dataset: dataset,
                          existingNodeIds: const {},
                          pickRecording: () async => 'synthetic-test.mp4',
                          scanRecording: (path, {onProgress}) async =>
                              BdoActiveNodeVideoOcrResult(
                                sourcePath: path,
                                ocrLanguage: 'en-US',
                                sourceWidth: 360,
                                sourceHeight: 620,
                                durationMilliseconds: 1200,
                                frames: [
                                  BdoActiveNodeOcrFrame(
                                    frameIndex: 0,
                                    timestampMilliseconds: 100,
                                    sharpness: .2,
                                    lines: const [
                                      BdoActiveNodeOcrLine(
                                        text: 'Behr Riverhead - Mining',
                                        frameIndex: 0,
                                        timestampMilliseconds: 100,
                                        frameSharpness: .2,
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                        )
                      : BdoSetupScreenshotImportDialog(
                          dataset: dataset,
                          existingWorkerNodeIds: const {},
                          existingHouseIds: const {},
                          initialMode: BdoSetupScreenshotImportMode.workerNodes,
                          picker: () async => null,
                          activeNodeRecordingPicker: () async => null,
                          activeNodeRecordingScanner: (path, {onProgress}) =>
                              throw StateError('Not invoked by this test'),
                        ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          if (recording) {
            await tester.tap(
              find.byKey(const ValueKey('active-node-recording-choose')),
            );
            await tester.pumpAndSettle();
            expect(find.text('Behr Riverhead - Mining'), findsOneWidget);
            expect(
              find.textContaining('Saved nodes are never removed'),
              findsNothing,
            );
            expect(find.text('Scan details'), findsNothing);
            expect(find.textContaining('Clear match'), findsNothing);
            expect(find.textContaining('selected'), findsOneWidget);
            if (scale == 1) {
              final surface = find
                  .descendant(
                    of: find.byType(Dialog),
                    matching: find.byWidgetPredicate(
                      (widget) =>
                          widget is Material &&
                          widget.type == MaterialType.card,
                    ),
                  )
                  .first;
              expect(tester.getSize(surface).height, lessThan(280));
              expect(tester.getSize(surface).width, lessThanOrEqualTo(540));
            }
          }
          expect(tester.takeException(), isNull);
          expect(find.text('Cancel').hitTestable(), findsOneWidget);
          const output = String.fromEnvironment('MAP_IMPORT_REVIEW_DIR');
          if (output.isNotEmpty) {
            final boundary =
                key.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary;
            final name = recording ? 'recording-review' : 'screenshot-choices';
            await tester.runAsync(() async {
              final image = await boundary.toImage();
              final bytes = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              final directory = Directory(output)..createSync(recursive: true);
              await File(
                '${directory.path}/$name-${scale.toInt()}x.png',
              ).writeAsBytes(bytes!.buffer.asUint8List());
              image.dispose();
            });
          }
        },
      );
    }
  }
}

BdoResourceMapDataset _dataset() => BdoResourceMapDataset(
  manifest: BdoDatasetManifest(
    schemaVersion: 1,
    datasetVersion: 'import-dialog-visual-test',
    generatedAt: DateTime.utc(2026),
    coordinateReference: 'synthetic test',
    provenance: const [],
  ),
  resources: const [],
  workerNodes: const [
    BdoWorkerNode(
      id: 'behr',
      name: 'Behr Riverhead - Mining',
      nodeType: 'Mining',
      region: 'Calpheon',
      location: BdoWorldPoint(0, 0),
      contributionPoints: 1,
      linkIds: [],
      outputs: [
        BdoNodeOutput(resourceId: 'iron', name: 'Iron Ore', isPrimary: true),
      ],
      isResourceNode: true,
      isProductionNode: true,
    ),
  ],
  gatheringSpots: const [],
  gatheringRoutes: const [],
);
