import 'dart:convert';
import 'dart:typed_data';

import 'package:bdo_map_core/bdo_map_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'offers worker-node and town-house modes and cancellation changes nothing',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 752));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(useMaterial3: true),
          home: ResourceMapChromeTheme(
            data: ResourceMapChromeThemeData.sakuraCartographer,
            child: _DialogHarness(
              dataset: _mapDataset(),
              lodgingDataset: _lodgingDataset(),
              picker: () async => null,
            ),
          ),
        ),
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('open-screenshot-import')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Scan screenshots'), findsOneWidget);
      expect(find.text('Worker nodes'), findsOneWidget);
      expect(find.text('Town houses'), findsOneWidget);
      final dialogSize = tester.getSize(
        find
            .descendant(
              of: find.byKey(
                const ValueKey<String>('setup-screenshot-import-dialog'),
              ),
              matching: find.byType(Material),
            )
            .first,
      );
      expect(dialogSize.width, lessThanOrEqualTo(640));
      expect(dialogSize.height, lessThanOrEqualTo(430));
      await tester.tap(
        find.byKey(const ValueKey<String>('setup-import-mode-nodes')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey<String>('setup-import-region-selector')),
        findsOneWidget,
      );
      expect(find.text('Anywhere / sea'), findsOneWidget);
      expect(
        tester
            .widget<Checkbox>(
              find.byKey(
                const ValueKey<String>('setup-import-anywhere-checkbox'),
              ),
            )
            .value,
        isTrue,
      );
      expect(
        find.byKey(const ValueKey<String>('setup-import-region-search')),
        findsNothing,
      );

      await tester.tap(
        find.byKey(const ValueKey<String>('setup-import-anywhere-toggle')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey<String>('setup-import-region-search')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const ValueKey<String>('setup-import-mode-houses')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey<String>('setup-import-town-selector')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('setup-import-town-search')),
        findsOneWidget,
      );
      await tester.enterText(
        find.byKey(const ValueKey<String>('setup-import-town-search')),
        'test',
      );
      await tester.pumpAndSettle();
      expect(find.text('Test Town'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Scan screenshots'), findsNothing);
      expect(find.text('cancelled'), findsOneWidget);
      expect(find.text('nodes:0 houses:0'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'default Anywhere scan decodes, reviews, and returns checked nodes',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final screenshot = _workerNodeScreenshot();
      var pickerCalls = 0;

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(useMaterial3: true),
          home: ResourceMapChromeTheme(
            data: ResourceMapChromeThemeData.sakuraCartographer,
            child: _DialogHarness(
              dataset: _mapDataset(),
              lodgingDataset: _lodgingDataset(),
              picker: () async {
                pickerCalls += 1;
                return screenshot;
              },
              initialMode: BdoSetupScreenshotImportMode.workerNodes,
            ),
          ),
        ),
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('open-screenshot-import')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Anywhere / sea'), findsOneWidget);
      await _pickAndAnalyze(tester);
      expect(pickerCalls, 1);
      expect(
        find.byKey(const ValueKey<String>('setup-screenshot-import-review')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('setup-import-review-center')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const ValueKey<String>('setup-import-confirm')),
      );
      await tester.pumpAndSettle();

      expect(find.text('saved:workerNodes'), findsOneWidget);
      expect(find.text('nodes:3 houses:0'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('offers broad land and ocean regions', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        home: ResourceMapChromeTheme(
          data: ResourceMapChromeThemeData.sakuraCartographer,
          child: _DialogHarness(
            dataset: _regionalMapDataset(),
            lodgingDataset: _lodgingDataset(),
            picker: () async => null,
            initialMode: BdoSetupScreenshotImportMode.workerNodes,
          ),
        ),
      ),
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('open-screenshot-import')),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey<String>('setup-import-anywhere-toggle')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey<String>('setup-import-region-search')),
      'ocean',
    );
    await tester.pumpAndSettle();

    expect(find.text('Great Ocean & islands'), findsOneWidget);
    final suggestions = find.byKey(
      const ValueKey<String>('setup-import-region-suggestions'),
    );
    expect(suggestions, findsOneWidget);
    expect(tester.getSize(suggestions).height, lessThanOrEqualTo(228));
    await tester.tap(find.text('Great Ocean & islands'));
    await tester.pumpAndSettle();
    expect(find.text('Great Ocean & islands'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'offers the Activated-list recording route and returns reviewed nodes',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(useMaterial3: true),
          home: ResourceMapChromeTheme(
            data: ResourceMapChromeThemeData.sakuraCartographer,
            child: _DialogHarness(
              dataset: _activeRecordingMapDataset(),
              lodgingDataset: _lodgingDataset(),
              picker: () async => null,
              activeNodeRecordingPicker: () async => 'activated.mp4',
              activeNodeRecordingScanner: (_, {onProgress}) async =>
                  BdoActiveNodeVideoOcrResult(
                    sourcePath: 'activated.mp4',
                    ocrLanguage: 'en-US',
                    sourceWidth: 360,
                    sourceHeight: 620,
                    durationMilliseconds: 900,
                    frames: <BdoActiveNodeOcrFrame>[
                      BdoActiveNodeOcrFrame(
                        frameIndex: 0,
                        timestampMilliseconds: 100,
                        sharpness: .2,
                        lines: const <BdoActiveNodeOcrLine>[
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
              initialMode: BdoSetupScreenshotImportMode.workerNodes,
            ),
          ),
        ),
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('open-screenshot-import')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Activated list recording'), findsOneWidget);
      expect(find.text('Recommended'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey<String>('setup-import-active-list-open')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Read Activated nodes'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey<String>('active-node-recording-choose')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey<String>('active-node-recording-confirm')),
      );
      await tester.pumpAndSettle();

      expect(find.text('saved:workerNodes'), findsOneWidget);
      expect(find.text('nodes:1 houses:0'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'pastes a Lightshot-style clipboard image through the same flow',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var pickerCalls = 0;
      var clipboardCalls = 0;

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(useMaterial3: true),
          home: ResourceMapChromeTheme(
            data: ResourceMapChromeThemeData.sakuraCartographer,
            child: _DialogHarness(
              dataset: _mapDataset(),
              lodgingDataset: _lodgingDataset(),
              picker: () async {
                pickerCalls += 1;
                return null;
              },
              clipboardReader: () async {
                clipboardCalls += 1;
                return _workerNodeScreenshot();
              },
              initialMode: BdoSetupScreenshotImportMode.workerNodes,
            ),
          ),
        ),
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('open-screenshot-import')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('setup-import-paste-screenshot')),
        findsOneWidget,
      );
      await _pickAndAnalyze(
        tester,
        sourceKey: const ValueKey<String>('setup-import-paste-screenshot'),
      );
      expect(clipboardCalls, 1);
      expect(pickerCalls, 0);
      expect(
        find.byKey(const ValueKey<String>('setup-screenshot-import-review')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('empty clipboard stays compact and explains what to copy', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        home: ResourceMapChromeTheme(
          data: ResourceMapChromeThemeData.sakuraCartographer,
          child: _DialogHarness(
            dataset: _mapDataset(),
            lodgingDataset: _lodgingDataset(),
            picker: () async => null,
            clipboardReader: () async => null,
            initialMode: BdoSetupScreenshotImportMode.workerNodes,
          ),
        ),
      ),
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('open-screenshot-import')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('setup-import-paste-screenshot')),
    );
    await tester.pumpAndSettle();

    expect(
      find.textContaining('No screenshot image was found'),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('setup-screenshot-import-choose')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'combines overlapping screenshots and preserves a manual uncheck',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final screenshot = _workerNodeScreenshot();
      var pickerCalls = 0;

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(useMaterial3: true),
          home: ResourceMapChromeTheme(
            data: ResourceMapChromeThemeData.sakuraCartographer,
            child: _DialogHarness(
              dataset: _mapDataset(),
              lodgingDataset: _lodgingDataset(),
              picker: () async {
                pickerCalls += 1;
                return screenshot;
              },
              initialMode: BdoSetupScreenshotImportMode.workerNodes,
            ),
          ),
        ),
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('open-screenshot-import')),
      );
      await tester.pumpAndSettle();
      await _pickAndAnalyze(tester);

      final centerRow = find.byKey(
        const ValueKey<String>('setup-import-review-center'),
      );
      expect(centerRow, findsOneWidget);
      var centerCheckbox = find.descendant(
        of: centerRow,
        matching: find.byType(Checkbox),
      );
      expect(centerCheckbox, findsOneWidget);
      expect(tester.widget<Checkbox>(centerCheckbox).value, isTrue);
      await tester.tap(centerCheckbox);
      await tester.pumpAndSettle();
      expect(tester.widget<Checkbox>(centerCheckbox).value, isFalse);

      await tester.tap(
        find.byKey(const ValueKey<String>('setup-import-add-another')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Parts in this scan'), findsOneWidget);
      expect(find.text('Screenshot 1'), findsOneWidget);
      expect(find.text('Scan another part'), findsOneWidget);

      await _pickAndAnalyze(tester);
      expect(pickerCalls, 2);
      expect(centerRow, findsOneWidget);
      expect(
        find.textContaining('Confirmed in 2 screenshots'),
        findsNWidgets(3),
      );
      centerCheckbox = find.descendant(
        of: centerRow,
        matching: find.byType(Checkbox),
      );
      expect(tester.widget<Checkbox>(centerCheckbox).value, isFalse);

      await tester.tap(
        find.byKey(const ValueKey<String>('setup-import-confirm')),
      );
      await tester.pumpAndSettle();
      expect(find.text('saved:workerNodes'), findsOneWidget);
      expect(find.text('nodes:2 houses:0'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

Future<void> _pickAndAnalyze(
  WidgetTester tester, {
  Key sourceKey = const ValueKey<String>('setup-import-pick-screenshot'),
}) async {
  await tester.tap(find.byKey(sourceKey));
  await tester.pump();
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 250)),
  );
  await tester.pumpAndSettle();
  expect(
    find.byKey(const ValueKey<String>('setup-screenshot-import-align')),
    findsOneWidget,
  );
  expect(
    find.byKey(const ValueKey<String>('setup-import-screenshot-preview')),
    findsOneWidget,
  );
  expect(find.textContaining('alignment guides'), findsOneWidget);
  expect(find.textContaining('not scan results'), findsOneWidget);
  await tester.tap(find.byKey(const ValueKey<String>('setup-import-analyze')));
  await tester.pumpAndSettle();
  expect(
    find.byKey(const ValueKey<String>('setup-screenshot-import-review')),
    findsOneWidget,
  );
}

class _DialogHarness extends StatefulWidget {
  const _DialogHarness({
    required this.dataset,
    required this.lodgingDataset,
    required this.picker,
    this.clipboardReader,
    this.initialMode,
    this.activeNodeRecordingPicker,
    this.activeNodeRecordingScanner,
  });

  final BdoResourceMapDataset dataset;
  final LodgingDataset lodgingDataset;
  final Future<Uint8List?> Function() picker;
  final Future<Uint8List?> Function()? clipboardReader;
  final BdoSetupScreenshotImportMode? initialMode;
  final BdoActiveNodeRecordingPicker? activeNodeRecordingPicker;
  final BdoActiveNodeRecordingScanner? activeNodeRecordingScanner;

  @override
  State<_DialogHarness> createState() => _DialogHarnessState();
}

class _DialogHarnessState extends State<_DialogHarness> {
  BdoSetupScreenshotImportSelection? _selection;
  bool _completed = false;

  Future<void> _open() async {
    final result = await showDialog<BdoSetupScreenshotImportSelection>(
      context: context,
      barrierDismissible: false,
      builder: (context) => BdoSetupScreenshotImportDialog(
        dataset: widget.dataset,
        lodgingDataset: widget.lodgingDataset,
        picker: widget.picker,
        clipboardReader: widget.clipboardReader,
        activeNodeRecordingPicker: widget.activeNodeRecordingPicker,
        activeNodeRecordingScanner: widget.activeNodeRecordingScanner,
        existingWorkerNodeIds: const <String>{},
        existingHouseIds: const <String>{},
        initialMode: widget.initialMode,
      ),
    );
    if (!mounted) return;
    setState(() {
      _selection = result;
      _completed = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final selection = _selection;
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            FilledButton(
              key: const ValueKey<String>('open-screenshot-import'),
              onPressed: _open,
              child: const Text('Open import'),
            ),
            Text(
              !_completed
                  ? 'waiting'
                  : selection == null
                  ? 'cancelled'
                  : 'saved:${selection.mode.name}',
            ),
            Text(
              'nodes:${selection?.workerNodeIds.length ?? 0} '
              'houses:${selection?.houseIds.length ?? 0}',
            ),
          ],
        ),
      ),
    );
  }
}

BdoResourceMapDataset _mapDataset() => BdoResourceMapDataset(
  manifest: BdoDatasetManifest(
    schemaVersion: 1,
    datasetVersion: 'screenshot-dialog-test',
    generatedAt: DateTime.utc(2026),
    coordinateReference: 'widget test',
    provenance: const <BdoProvenanceRecord>[],
  ),
  resources: const <BdoResourceDefinition>[],
  workerNodes: const <BdoWorkerNode>[
    BdoWorkerNode(
      id: 'west',
      name: 'West Gateway',
      nodeType: 'Gateway',
      region: 'Test',
      location: BdoWorldPoint(-50, 0),
      contributionPoints: 1,
      linkIds: <String>['center'],
      outputs: <BdoNodeOutput>[],
      isResourceNode: false,
    ),
    BdoWorkerNode(
      id: 'center',
      name: 'Center City',
      nodeType: 'City',
      region: 'Test',
      location: BdoWorldPoint(0, 0),
      contributionPoints: 0,
      linkIds: <String>['west', 'east'],
      outputs: <BdoNodeOutput>[],
      isResourceNode: false,
    ),
    BdoWorkerNode(
      id: 'east',
      name: 'East Gateway',
      nodeType: 'Gateway',
      region: 'Test',
      location: BdoWorldPoint(50, 0),
      contributionPoints: 1,
      linkIds: <String>['center'],
      outputs: <BdoNodeOutput>[],
      isResourceNode: false,
    ),
  ],
  gatheringSpots: const <BdoGatheringSpot>[],
  gatheringRoutes: const <BdoGatheringRoute>[],
);

BdoResourceMapDataset _regionalMapDataset() => BdoResourceMapDataset(
  manifest: BdoDatasetManifest(
    schemaVersion: 1,
    datasetVersion: 'screenshot-region-test',
    generatedAt: DateTime.utc(2026),
    coordinateReference: 'widget test',
    provenance: const <BdoProvenanceRecord>[],
  ),
  resources: const <BdoResourceDefinition>[],
  workerNodes: const <BdoWorkerNode>[
    BdoWorkerNode(
      id: 'velia',
      name: 'Velia',
      nodeType: 'City',
      region: 'Balenos',
      location: BdoWorldPoint(0, 0),
      contributionPoints: 0,
      linkIds: <String>['iliya'],
      outputs: <BdoNodeOutput>[],
      isResourceNode: false,
    ),
    BdoWorkerNode(
      id: 'iliya',
      name: 'Iliya Island',
      nodeType: 'City',
      region: 'Balenos',
      location: BdoWorldPoint(100, 0),
      contributionPoints: 0,
      linkIds: <String>['velia', 'oquilla'],
      outputs: <BdoNodeOutput>[],
      isResourceNode: false,
    ),
    BdoWorkerNode(
      id: 'oquilla',
      name: "Oquilla's Eye",
      nodeType: 'City',
      region: 'Great Ocean',
      location: BdoWorldPoint(200, 0),
      contributionPoints: 0,
      linkIds: <String>['iliya', 'lema'],
      outputs: <BdoNodeOutput>[],
      isResourceNode: false,
    ),
    BdoWorkerNode(
      id: 'lema',
      name: 'Lema Island',
      nodeType: 'City',
      region: 'Great Ocean',
      location: BdoWorldPoint(300, 0),
      contributionPoints: 0,
      linkIds: <String>['oquilla'],
      outputs: <BdoNodeOutput>[],
      isResourceNode: false,
    ),
  ],
  gatheringSpots: const <BdoGatheringSpot>[],
  gatheringRoutes: const <BdoGatheringRoute>[],
);

BdoResourceMapDataset _activeRecordingMapDataset() => BdoResourceMapDataset(
  manifest: BdoDatasetManifest(
    schemaVersion: 1,
    datasetVersion: 'active-recording-outer-dialog-test',
    generatedAt: DateTime.utc(2026),
    coordinateReference: 'widget test',
    provenance: const <BdoProvenanceRecord>[],
  ),
  resources: const <BdoResourceDefinition>[],
  workerNodes: const <BdoWorkerNode>[
    BdoWorkerNode(
      id: 'behr-mining',
      name: 'Behr Riverhead - Mining',
      nodeType: 'Mining',
      region: 'Test',
      location: BdoWorldPoint(0, 0),
      contributionPoints: 1,
      linkIds: <String>[],
      outputs: <BdoNodeOutput>[
        BdoNodeOutput(
          resourceId: 'iron-ore',
          name: 'Iron Ore',
          isPrimary: true,
        ),
      ],
      isResourceNode: true,
      isProductionNode: true,
    ),
  ],
  gatheringSpots: const <BdoGatheringSpot>[],
  gatheringRoutes: const <BdoGatheringRoute>[],
);

LodgingDataset _lodgingDataset() {
  final houses = <LodgingHouse>[
    LodgingHouse(
      id: 'house:1',
      sourceKey: 1,
      name: 'Test Town 1-1',
      regionId: 1,
      townNodeId: 'town',
      parentNodeId: 'town',
      contributionPoints: 1,
      lodgingSpaces: 0,
      isLodging: false,
      usages: const <HouseUsage>[
        HouseUsage(typeId: 2, label: 'Storage', level: 1),
      ],
      prerequisiteHouseId: null,
      position: const LodgingPosition(x: -30, y: 0, z: 0),
    ),
    LodgingHouse(
      id: 'house:2',
      sourceKey: 2,
      name: 'Test Town 1-2',
      regionId: 1,
      townNodeId: 'town',
      parentNodeId: 'town',
      contributionPoints: 1,
      lodgingSpaces: 1,
      isLodging: true,
      usages: const <HouseUsage>[
        HouseUsage(typeId: 1, label: 'Lodging', level: 1),
      ],
      prerequisiteHouseId: 'house:1',
      position: const LodgingPosition(x: 30, y: 0, z: 0),
    ),
  ];
  return LodgingDataset(
    schemaVersion: 2,
    manifest: LodgingDataManifest(
      datasetVersion: 'screenshot-dialog-test',
      generatedAt: DateTime.utc(2026),
      sourceRepository: Uri.parse('https://example.invalid'),
      sourceCommit: 'test',
      sourceLicenseExpression: 'test',
      permittedUse: 'test',
      sourceSha256: const <String, String>{},
      townCount: 1,
      workerTownCount: 1,
      lodgingHouseCount: 1,
      nonLodgingHouseCount: 1,
      houseCount: 2,
      assumptions: const <String>[],
    ),
    towns: <LodgingTown>[
      LodgingTown(
        regionId: 1,
        townNodeId: 'town',
        name: 'Test Town',
        baseWorkerSlots: 1,
        position: const LodgingPosition(x: 0, y: 0, z: 0),
        houses: houses,
      ),
    ],
  );
}

Uint8List _workerNodeScreenshot() => base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAKAAAABkCAYAAAABtjuPAAAAAXNSR0IArs4c6QAAAARnQU1BAACx'
  'jwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAAKvSURBVHhe7dIxbttAFEVRLcJA3AepsoEswJ23'
  'mcqryKZc22ChgLgSh5zRFx8J3OI0gkj+B9zL+9ufLynlwh+kPRmgogxQUQaoKANUlAEqygAVZYCK'
  'MkBFGaCiDFBRBqgoA1SUASrKABVlgIoyQEUZoKIMUFEGqCgDVJQBKsoAFWWAijJARRmgogxQUQao'
  'KANUlAEqygAVZYCKMkBFGaCiDFBRBqiosgBffrw28f9nxV3E/58VdxH/P+rhAHnYGj5/Ftyxhs+f'
  'BXes4fO9hgPkIb34vqPi3b34vqPi3b34vq2GAuTHJ5ePvzc+//3+j/9/5Oi98F531u/sDpAf5ZFL'
  'By8dzvcfBe/kNnfW7OwKkB/jgcRjq45+Nt7HXcR97rz91pLhAHncPTz06vXnr+GD9+DO+7ivYufm'
  'AHuPXTv4kaOfyZ3LuK9ipwGCO5dxX8XOTQGOHLvl4NGjn8WdbdxXsdMAZ9zZxn0VOw1wxp1t3Fex'
  '0wBn3NnGfRU7DXDGnW3cV7HTAGfc2cZ9FTsNcMadbdxXsdMAZ9zZxn0VOzcFOBk5mofy4N5j9+DO'
  'ZdxXsdMAwZ3LuK9i5+YAJ71H89D5wSPH7sWd93Ffxc7hALcczUOv+B5+J433cRdxnztvv7WkK8AJ'
  'P8Yj1w7m83z/UfBObnNnzc7uACf86NLhrUNHjt0b73Vn/c6hACf8eC++76h4dy++76h4dy++b6vh'
  'AK94yBo+fxbcsYbPnwV3rOHzvR4O8IqHEf9/VtxF/P9ZcRfx/6PKApRGGKCiDFBRBqgoA1SUASrK'
  'ABVlgIoyQEUZoKIMUFEGqCgDVJQBKsoAFWWAijJARRmgogxQUQaoKANUlAEqygAVZYCKMkBFGaCi'
  'DFBRBqgoA1SUASrKABVlgIoyQEUZoKIMUFEGqCgDVNQ3nL0J2eEJDmEAAAAASUVORK5CYII=',
);
