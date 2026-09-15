import 'dart:async';

import 'package:bdo_map_core/bdo_map_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('compact recording dialog remains readable at double text size', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 820));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var pickerCalls = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: ResourceMapChromeTheme(
          data: ResourceMapChromeThemeData.sakuraCartographer,
          child: _RecordingHarness(
            launcher: () async => true,
            finder: (_) async => null,
            picker: () async {
              pickerCalls++;
              return null;
            },
            scanner: (path, {onProgress}) async => _scan(path, <String>[]),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('open-recording-import')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(pickerCalls, 0);
    expect(find.text('Cancel').hitTestable(), findsOneWidget);
    expect(
      tester.widget<Text>(find.text('Import Activated nodes')).style?.fontSize,
      16,
    );
    await tester.tap(find.byKey(const ValueKey('active-node-recording-start')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('active-node-recording-find-latest')),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('No new recording found'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('waiting'), findsOneWidget);
  });

  testWidgets(
    'combines recordings and requires explicit duplicate-label choices',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1100, 820));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final pickedPaths = <String>['first.mp4', 'second.mp4'];

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(useMaterial3: true),
          home: ResourceMapChromeTheme(
            data: ResourceMapChromeThemeData.sakuraCartographer,
            child: _RecordingHarness(
              picker: () async => pickedPaths.removeAt(0),
              scanner: (path, {onProgress}) async => path == 'first.mp4'
                  ? _scan(path, <String>[
                      'Behr Riverhead - Mining',
                      'Godu Village - Farming',
                    ])
                  : _scan(path, <String>[
                      "Pilgrim's Sanctum: Sincerity - Excavation",
                    ]),
            ),
          ),
        ),
      );

      await tester.tap(
        find.byKey(const ValueKey<String>('open-recording-import')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Import Activated nodes'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey<String>('active-node-recording-choose')),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('recording added'), findsNothing);
      expect(find.text('Rice'), findsOneWidget);
      expect(find.text('Wheat'), findsOneWidget);
      final savedRice = tester.widget<CheckboxListTile>(
        find.byKey(const ValueKey<String>('active-node-candidate-godu-rice')),
      );
      expect(savedRice.value, isTrue);
      expect(savedRice.onChanged, isNull);

      final wheat = find.byKey(
        const ValueKey<String>('active-node-candidate-godu-wheat'),
      );
      await tester.ensureVisible(wheat);
      await tester.pumpAndSettle();
      await tester.tap(wheat);
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey<String>('active-node-recording-choose')),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('recordings added'), findsNothing);
      await tester.ensureVisible(
        find.text("Pilgrim's Sanctum: Sincerity - Excavation"),
      );
      expect(
        find.text("Pilgrim's Sanctum: Sincerity - Excavation"),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const ValueKey<String>('active-node-recording-confirm')),
      );
      await tester.pumpAndSettle();

      expect(find.text('behr,godu-rice,godu-wheat,sincerity'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('launches rectangle recording and finds its saved MP4', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1100, 820));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    DateTime? modifiedAfter;
    var launches = 0;

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        home: ResourceMapChromeTheme(
          data: ResourceMapChromeThemeData.sakuraCartographer,
          child: _RecordingHarness(
            launcher: () async {
              launches += 1;
              return true;
            },
            finder: (value) async {
              modifiedAfter = value;
              return 'latest.mp4';
            },
            picker: () async => null,
            scanner: (path, {onProgress}) async =>
                _scan(path, <String>['Behr Riverhead - Mining']),
          ),
        ),
      ),
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('open-recording-import')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('active-node-recording-start')),
    );
    await tester.pumpAndSettle();
    expect(launches, 1);
    expect(
      find.textContaining('Record the Activated list from top to bottom'),
      findsNothing,
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('active-node-recording-find-latest')),
    );
    await tester.pumpAndSettle();
    expect(modifiedAfter, isNotNull);
    expect(find.text('Behr Riverhead - Mining'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows determinate native OCR progress while reading names', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1100, 820));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final completed = Completer<BdoActiveNodeVideoOcrResult>();
    ValueChanged<BdoActiveNodeScanProgress>? progressCallback;

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        home: ResourceMapChromeTheme(
          data: ResourceMapChromeThemeData.sakuraCartographer,
          child: _RecordingHarness(
            picker: () async => 'progress.mp4',
            scanner: (path, {onProgress}) {
              progressCallback = onProgress;
              return completed.future;
            },
          ),
        ),
      ),
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('open-recording-import')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('active-node-recording-choose')),
    );
    await tester.pump();
    expect(progressCallback, isNotNull);

    progressCallback!(
      const BdoActiveNodeScanProgress(
        fraction: .22,
        completedFrames: 0,
        estimatedFrames: 18,
      ),
    );
    await tester.pump();
    expect(find.text('Checking video frames  0 of 18'), findsOneWidget);

    progressCallback!(
      const BdoActiveNodeScanProgress(
        fraction: .42,
        completedFrames: 7,
        estimatedFrames: 18,
      ),
    );
    await tester.pump();

    expect(find.text('Reading node names  7 of 18'), findsOneWidget);
    expect(find.text('42%'), findsOneWidget);
    final indicator = tester.widget<LinearProgressIndicator>(
      find.byKey(const ValueKey<String>('active-node-recording-progress')),
    );
    expect(indicator.value, .42);

    progressCallback!(
      const BdoActiveNodeScanProgress(
        fraction: .97,
        completedFrames: 18,
        estimatedFrames: 18,
      ),
    );
    await tester.pump();
    expect(find.text('Finishing scan  18 of 18'), findsOneWidget);
    expect(find.text('97%'), findsOneWidget);

    completed.complete(
      _scan('progress.mp4', <String>['Behr Riverhead - Mining']),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('active-node-recording-progress')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });
}

class _RecordingHarness extends StatefulWidget {
  const _RecordingHarness({
    required this.picker,
    required this.scanner,
    this.launcher,
    this.finder,
  });

  final BdoActiveNodeRecordingLauncher? launcher;
  final BdoActiveNodeRecordingFinder? finder;
  final BdoActiveNodeRecordingPicker picker;
  final BdoActiveNodeRecordingScanner scanner;

  @override
  State<_RecordingHarness> createState() => _RecordingHarnessState();
}

class _RecordingHarnessState extends State<_RecordingHarness> {
  Set<String>? _selected;

  String get _selectionLabel {
    final selected = _selected;
    if (selected == null) return 'waiting';
    final sorted = selected.toList()..sort();
    return sorted.join(',');
  }

  Future<void> _open() async {
    final selected = await showDialog<Set<String>>(
      context: context,
      barrierDismissible: false,
      builder: (context) => BdoActiveNodeRecordingImportDialog(
        dataset: _dataset(),
        existingNodeIds: const <String>{'godu-rice'},
        launchRecording: widget.launcher,
        findLatestRecording: widget.finder,
        pickRecording: widget.picker,
        scanRecording: widget.scanner,
      ),
    );
    if (mounted) setState(() => _selected = selected);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Column(
      children: <Widget>[
        FilledButton(
          key: const ValueKey<String>('open-recording-import'),
          onPressed: _open,
          child: const Text('Open'),
        ),
        Text(_selectionLabel),
      ],
    ),
  );
}

BdoActiveNodeVideoOcrResult _scan(String path, List<String> rows) =>
    BdoActiveNodeVideoOcrResult(
      sourcePath: path,
      ocrLanguage: 'en-US',
      sourceWidth: 360,
      sourceHeight: 620,
      durationMilliseconds: 1200,
      frames: <BdoActiveNodeOcrFrame>[
        BdoActiveNodeOcrFrame(
          frameIndex: 0,
          timestampMilliseconds: 100,
          sharpness: .2,
          lines: <BdoActiveNodeOcrLine>[
            for (final row in rows)
              BdoActiveNodeOcrLine(
                text: row,
                frameIndex: 0,
                timestampMilliseconds: 100,
                frameSharpness: .2,
              ),
          ],
        ),
      ],
    );

BdoResourceMapDataset _dataset() => BdoResourceMapDataset(
  manifest: BdoDatasetManifest(
    schemaVersion: 1,
    datasetVersion: 'active-recording-dialog-test',
    generatedAt: DateTime.utc(2026),
    coordinateReference: 'widget test',
    provenance: const <BdoProvenanceRecord>[],
  ),
  resources: const <BdoResourceDefinition>[],
  workerNodes: <BdoWorkerNode>[
    _bankNode(),
    _node('behr', 'Behr Riverhead', 'Mining', 'Iron Ore'),
    _node(
      'sincerity',
      "Pilgrim's Sanctum: Sincerity",
      'Excavation',
      'Trace of Ascension',
    ),
    _node('godu-rice', 'Godu Village', 'Farming', 'Rice'),
    _node('godu-wheat', 'Godu Village', 'Farming', 'Wheat'),
  ],
  gatheringSpots: const <BdoGatheringSpot>[],
  gatheringRoutes: const <BdoGatheringRoute>[],
);

BdoWorkerNode _node(String id, String site, String activity, String output) =>
    BdoWorkerNode(
      id: id,
      name: '$site - $activity',
      nodeType: switch (activity) {
        'Excavation' => 'Excavation',
        'Farming' => 'Farm',
        _ => 'Mining',
      },
      region: 'Test',
      location: const BdoWorldPoint(0, 0),
      contributionPoints: 1,
      linkIds: const <String>[],
      outputs: <BdoNodeOutput>[
        BdoNodeOutput(resourceId: id, name: output, isPrimary: true),
      ],
      isResourceNode: true,
      isProductionNode: true,
    );

BdoWorkerNode _bankNode() => BdoWorkerNode(
  id: '102',
  name: 'Velia - Santo Manzi Investment Bank',
  nodeType: 'Bank',
  region: 'Balenos',
  location: const BdoWorldPoint(0, 0),
  contributionPoints: 1,
  linkIds: const <String>[],
  outputs: const <BdoNodeOutput>[],
  isResourceNode: false,
  isProductionNode: true,
);
