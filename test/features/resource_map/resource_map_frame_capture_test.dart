import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bdo_craft_planner_flutter/features/resource_map/diagnostics/resource_map_frame_capture.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _fieldKey = ValueKey('capture-fixture-search');
const _bodyKey = ValueKey('capture-fixture-body');
const _outsideColor = Color(0xFFFF00FF);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('mounting and ordinary frames never initiate a capture', (
    tester,
  ) async {
    var reads = 0;
    final records = <ResourceFrameRecord>[];
    await _install(
      tester,
      readback: (boundary, ratio) async {
        reads++;
        return _pixels(boundary, ratio);
      },
      writer: (record) async => records.add(record),
    );
    for (var frame = 0; frame < 5; frame++) {
      await tester.pump(const Duration(milliseconds: 400));
    }
    expect(reads, 0);
    expect(records, isEmpty);
    expect(find.byType(SnackBar), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets(
    'F8 readback schedules no frame and never repaints a stable child',
    (tester) async {
      final focus = FocusNode();
      final records = <ResourceFrameRecord>[];
      var paints = 0;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        focus.dispose();
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: ResourceMapFrameCapture(
              active: true,
              writer: (record) async => records.add(record),
              child: Focus(
                focusNode: focus,
                child: CustomPaint(
                  painter: _CountingPainter(() => paints++),
                  child: const SizedBox(width: 120, height: 80),
                ),
              ),
            ),
          ),
        ),
      );
      focus.requestFocus();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      final before = paints;
      expect(before, greaterThan(0));
      expect(tester.binding.hasScheduledFrame, isFalse);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.f8);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.f8);
      // Check before any test pump: the hotkey itself must not request a frame.
      expect(tester.binding.hasScheduledFrame, isFalse);
      expect(paints, before);
      await _until(tester, () => records.isNotEmpty);
      expect(records.single.metadata['status'], 'captured');
      expect(records.single.metadata['hasScheduledFrame'], false);
      expect(paints, before);
      expect(tester.binding.hasScheduledFrame, isFalse);
      expect(focus.hasFocus, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'F8 captures only local pixels at DPR2 without changing editing',
    (tester) async {
      final records = <ResourceFrameRecord>[];
      final fixture = await _install(
        tester,
        writer: (record) async => records.add(record),
      );
      tester.view.devicePixelRatio = 2;
      tester.view.physicalSize = const Size(1600, 1200);
      await tester.pump();
      fixture.text.text = 'local fixture query';
      fixture.text.selection = const TextSelection(
        baseOffset: 2,
        extentOffset: 7,
      );
      fixture.focus.requestFocus();
      await tester.pump();
      fixture.scroll.jumpTo(76);
      await tester.pump();
      final selection = fixture.text.selection;
      final offset = fixture.scroll.offset;
      final bounds = tester.getRect(find.byKey(_bodyKey));
      expect(bounds.size, const Size(300, 220));
      expect(records, isEmpty);

      await _f8(tester);
      await _until(tester, () => records.isNotEmpty);
      expect(records, hasLength(1));
      final record = records.single;
      expect(record.metadata['requestIndex'], 1);
      expect(record.metadata['status'], 'captured');
      final pixels = record.pixels!;
      expect(pixels.width, 600);
      expect(pixels.height, 440);
      expect(fixture.focus.hasFocus, isTrue);
      expect(fixture.text.text, 'local fixture query');
      expect(fixture.text.selection, selection);
      expect(fixture.scroll.offset, offset);
      expect(tester.getRect(find.byKey(_bodyKey)), bounds);
      expect(find.byType(SnackBar), findsNothing);
      expect(find.byType(AlertDialog), findsNothing);

      await tester.runAsync(() async {
        final codec = await ui.instantiateImageCodec(pixels.png);
        final image = (await codec.getNextFrame()).image;
        try {
          expect(image.width, 600);
          expect(image.height, 440);
          final data = (await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          ))!;
          final rgba = Uint8List.sublistView(data);
          var outsidePixels = 0;
          for (var i = 0; i < rgba.length; i += 4) {
            if (rgba[i] == 255 && rgba[i + 1] == 0 && rgba[i + 2] == 255) {
              outsidePixels++;
            }
          }
          expect(
            outsidePixels,
            0,
            reason: 'The magenta sibling is outside Resource.',
          );
        } finally {
          image.dispose();
          codec.dispose();
        }
      });
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('busy, repeat and modifier keys do not spend extra attempts', (
    tester,
  ) async {
    final requests = <_PendingReadback>[];
    final records = <ResourceFrameRecord>[];
    await _install(
      tester,
      readback: (boundary, ratio) {
        final request = _PendingReadback(_pixels(boundary, ratio));
        requests.add(request);
        return request.result.future;
      },
      writer: (record) async => records.add(record),
    );
    for (final modifier in [
      LogicalKeyboardKey.shiftLeft,
      LogicalKeyboardKey.controlLeft,
      LogicalKeyboardKey.altLeft,
      LogicalKeyboardKey.metaLeft,
    ]) {
      await tester.sendKeyDownEvent(modifier);
      await _f8(tester);
      await tester.sendKeyUpEvent(modifier);
    }
    expect(requests, isEmpty);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.f8);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.f8);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.f8);
    await tester.pump();
    expect(requests, hasLength(1));
    await _f8(tester);
    expect(
      requests,
      hasLength(1),
      reason: 'Busy must not queue another readback.',
    );
    requests[0].complete();
    await _until(tester, () => records.length == 1);
    await _f8(tester);
    expect(requests, hasLength(2));
    requests[1].complete();
    await _until(tester, () => records.length == 2);
    await _f8(tester);
    expect(requests, hasLength(2));
    expect(records.map((record) => record.metadata['requestIndex']), [1, 2]);
    expect(records.map((record) => record.metadata['status']), [
      'captured',
      'captured',
    ]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('inactive, hidden ticker and inactive lifecycle reject F8', (
    tester,
  ) async {
    var reads = 0;
    final records = <ResourceFrameRecord>[];
    final fixture = await _install(
      tester,
      readback: (boundary, ratio) async {
        reads++;
        return _pixels(boundary, ratio);
      },
      writer: (record) async => records.add(record),
    );
    fixture.visibility.value = const _Visibility(active: false);
    await tester.pump();
    await _f8(tester);
    fixture.visibility.value = const _Visibility(tickerEnabled: false);
    await tester.pump();
    await _f8(tester);
    fixture.visibility.value = const _Visibility();
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await _f8(tester);
    expect(reads, 0);
    expect(records, isEmpty);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await _f8(tester);
    await _until(tester, () => records.isNotEmpty);
    expect(reads, 1);
    expect(records.single.metadata['requestIndex'], 1);
  });

  testWidgets('F8 works from sibling app chrome without moving focus', (
    tester,
  ) async {
    var reads = 0;
    final records = <ResourceFrameRecord>[];
    final fixture = await _install(
      tester,
      readback: (boundary, ratio) async {
        reads++;
        return _pixels(boundary, ratio);
      },
      writer: (record) async => records.add(record),
    );
    fixture.chromeFocus.requestFocus();
    await tester.pump();
    expect(fixture.chromeFocus.hasFocus, isTrue);
    expect(fixture.focus.hasFocus, isFalse);
    await _f8(tester);
    await _until(tester, () => records.isNotEmpty);
    expect(reads, 1);
    expect(records.single.metadata['status'], 'captured');
    expect(fixture.chromeFocus.hasFocus, isTrue);
    expect(fixture.focus.hasFocus, isFalse);
  });

  testWidgets('a modal route blocks F8 without spending a capture attempt', (
    tester,
  ) async {
    var reads = 0;
    final records = <ResourceFrameRecord>[];
    final fixture = await _install(
      tester,
      readback: (boundary, ratio) async {
        reads++;
        return _pixels(boundary, ratio);
      },
      writer: (record) async => records.add(record),
    );
    final context = tester.element(find.byKey(_fieldKey));
    unawaited(
      showDialog<void>(
        context: context,
        builder: (_) => const AlertDialog(title: Text('Fixture modal')),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(AlertDialog), findsOneWidget);
    await _f8(tester);
    expect(reads, 0);
    expect(records, isEmpty);
    Navigator.of(context).pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    fixture.chromeFocus.requestFocus();
    await tester.pump();
    await _f8(tester);
    await _until(tester, () => records.isNotEmpty);
    expect(reads, 1);
    expect(records.single.metadata['requestIndex'], 1);
  });

  for (final change in ['tab', 'ticker', 'lifecycle', 'metrics', 'dispose']) {
    testWidgets('$change change during readback discards image bytes', (
      tester,
    ) async {
      final requests = <_PendingReadback>[];
      final records = <ResourceFrameRecord>[];
      final fixture = await _install(
        tester,
        readback: (boundary, ratio) {
          final request = _PendingReadback(_pixels(boundary, ratio));
          requests.add(request);
          return request.result.future;
        },
        writer: (record) async => records.add(record),
      );
      await _f8(tester);
      expect(requests, hasLength(1));
      switch (change) {
        case 'tab':
          fixture.visibility.value = const _Visibility(active: false);
        case 'ticker':
          fixture.visibility.value = const _Visibility(tickerEnabled: false);
        case 'lifecycle':
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.inactive,
          );
        case 'metrics':
          tester.view.devicePixelRatio = 2;
        case 'dispose':
          fixture.visibility.value = const _Visibility(present: false);
      }
      await tester.pump();
      requests.single.complete();
      await _until(tester, () => records.isNotEmpty);
      expect(records, hasLength(1));
      expect(records.single.metadata['requestIndex'], 1);
      expect(records.single.metadata['status'], 'cancelled');
      expect(records.single.pixels, isNull);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'leaving and returning cannot revive an earlier pending capture',
    (tester) async {
      final requests = <_PendingReadback>[];
      final records = <ResourceFrameRecord>[];
      final fixture = await _install(
        tester,
        readback: (boundary, ratio) {
          final request = _PendingReadback(_pixels(boundary, ratio));
          requests.add(request);
          return request.result.future;
        },
        writer: (record) async => records.add(record),
      );
      await _f8(tester);
      fixture.visibility.value = const _Visibility(active: false);
      await tester.pump();
      fixture.visibility.value = const _Visibility();
      await tester.pump();
      requests.single.complete();
      await _until(tester, () => records.isNotEmpty);
      expect(records.single.metadata['status'], 'cancelled');
      expect(records.single.pixels, isNull);
      await _f8(tester);
      expect(requests, hasLength(2));
      requests.last.complete();
      await _until(tester, () => records.length == 2);
      expect(records.last.metadata['requestIndex'], 2);
      expect(records.last.metadata['status'], 'captured');
      await _f8(tester);
      expect(requests, hasLength(2));
    },
  );

  testWidgets('readback failures are sanitized and still count toward two', (
    tester,
  ) async {
    var reads = 0;
    final records = <ResourceFrameRecord>[];
    await _install(
      tester,
      readback: (_, _) async {
        reads++;
        throw StateError('private-path-or-query-must-not-be-logged');
      },
      writer: (record) async => records.add(record),
    );
    for (var attempt = 1; attempt <= 2; attempt++) {
      await _f8(tester);
      await _until(tester, () => records.length == attempt);
    }
    await _f8(tester);
    expect(reads, 2);
    expect(records, hasLength(2));
    for (final record in records) {
      expect(record.metadata['status'], 'readback-failed');
      expect(record.pixels, isNull);
      expect(
        jsonEncode(record.metadata),
        isNot(contains('private-path-or-query')),
      );
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('writer failure never escapes the hotkey or retries readback', (
    tester,
  ) async {
    var reads = 0;
    var writes = 0;
    await _install(
      tester,
      readback: (boundary, ratio) async {
        reads++;
        return _pixels(boundary, ratio);
      },
      writer: (_) async {
        writes++;
        throw _TestStorageFailure();
      },
    );
    await _f8(tester);
    await _until(tester, () => writes > 0);
    await tester.pump(const Duration(milliseconds: 100));
    expect(reads, 1);
    expect(tester.takeException(), isNull);
    expect(find.byType(SnackBar), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
  });

  test(
    'file stores isolate runs and keep the two numbered record pairs',
    () async {
      final parent = await Directory.systemTemp.createTemp(
        'resource_capture_store_',
      );
      addTearDown(() => parent.delete(recursive: true));
      final first = ResourceFrameFileStore(parent: parent);
      final second = ResourceFrameFileStore(parent: parent);
      final pixels = _storedPixels();
      await first.write(
        ResourceFrameRecord(
          metadata: const {'requestIndex': 1, 'status': 'captured'},
          pixels: pixels,
        ),
      );
      final firstDirectory = (await parent.list().toList()).single as Directory;
      await first.write(
        ResourceFrameRecord(
          metadata: const {'requestIndex': 2, 'status': 'captured'},
          pixels: pixels,
        ),
      );
      await second.write(
        const ResourceFrameRecord(
          metadata: {'requestIndex': 1, 'status': 'cancelled'},
        ),
      );
      final directories = (await parent.list().toList())
          .whereType<Directory>()
          .toList();
      expect(directories, hasLength(2));
      final secondDirectory = directories.singleWhere(
        (entry) => entry.path != firstDirectory.path,
      );
      expect(
        (await firstDirectory.list().toList()).map(
          (entry) => entry.uri.pathSegments.last,
        ),
        unorderedEquals(['01.png', '01.json', '02.png', '02.json']),
      );
      expect(
        (await secondDirectory.list().toList()).map(
          (entry) => entry.uri.pathSegments.last,
        ),
        ['01.json'],
      );
      for (final index in [1, 2]) {
        expect(
          await File('${firstDirectory.path}/0$index.png').readAsBytes(),
          pixels.png,
        );
        final metadata = jsonDecode(
          await File('${firstDirectory.path}/0$index.json').readAsString(),
        );
        expect(metadata, {'requestIndex': index, 'status': 'captured'});
      }
      expect(
        jsonDecode(
          await File('${secondDirectory.path}/01.json').readAsString(),
        ),
        {'requestIndex': 1, 'status': 'cancelled'},
      );
    },
  );

  test(
    'PNG storage errors write a fixed status without exception details',
    () async {
      final parent = await Directory.systemTemp.createTemp(
        'resource_capture_failure_',
      );
      addTearDown(() => parent.delete(recursive: true));
      final store = ResourceFrameFileStore(parent: parent);
      await store.write(
        const ResourceFrameRecord(
          metadata: {'requestIndex': 1, 'status': 'cancelled'},
        ),
      );
      final directory = (await parent.list().toList()).single as Directory;
      // Occupy only this temporary test destination with a directory. This makes
      // File.writeAsBytes fail deterministically without altering permissions.
      await Directory('${directory.path}/02.png').create();
      final metadata = <String, Object?>{
        'requestIndex': 2,
        'status': 'captured',
      };
      await store.write(
        ResourceFrameRecord(metadata: metadata, pixels: _storedPixels()),
      );
      final encoded = await File('${directory.path}/02.json').readAsString();
      expect(jsonDecode(encoded), {
        'requestIndex': 2,
        'status': 'storage-failed',
      });
      expect(encoded, isNot(contains(parent.path)));
      expect(encoded, isNot(contains('FileSystemException')));
      expect(
        metadata['status'],
        'captured',
        reason: 'The caller record is not mutated.',
      );
      expect(await File('${directory.path}/01.png').exists(), isFalse);
      expect(
        await FileSystemEntity.type('${directory.path}/02.png'),
        FileSystemEntityType.directory,
      );
    },
  );

  test(
    'file store rejects record indices outside the two allowed names',
    () async {
      final parent = await Directory.systemTemp.createTemp(
        'resource_capture_indices_',
      );
      addTearDown(() => parent.delete(recursive: true));
      final store = ResourceFrameFileStore(parent: parent);
      for (final index in <Object>[0, 3, '../outside']) {
        await expectLater(
          store.write(
            ResourceFrameRecord(
              metadata: {'requestIndex': index, 'status': 'captured'},
              pixels: _storedPixels(),
            ),
          ),
          throwsArgumentError,
        );
      }
      expect(
        (await parent.list(recursive: true).toList()).whereType<File>(),
        isEmpty,
      );
    },
  );
}

ResourceFramePixels _storedPixels() => ResourceFramePixels(
  png: Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10]),
  width: 1,
  height: 1,
);

class _CountingPainter extends CustomPainter {
  _CountingPainter(this.onPaint);
  final VoidCallback onPaint;

  @override
  void paint(Canvas canvas, Size size) {
    onPaint();
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFF185436),
    );
  }

  @override
  bool shouldRepaint(_CountingPainter oldDelegate) => false;
}

// A distinctive exception avoids reading/writing the filesystem in error tests.
class _TestStorageFailure implements Exception {}

class _PendingReadback {
  _PendingReadback(this.pixels);
  final ResourceFramePixels pixels;
  final result = Completer<ResourceFramePixels>();
  void complete() => result.complete(pixels);
}

class _Visibility {
  const _Visibility({
    this.active = true,
    this.tickerEnabled = true,
    this.present = true,
  });
  final bool active;
  final bool tickerEnabled;
  final bool present;
}

class _Fixture {
  final visibility = ValueNotifier(const _Visibility());
  final text = TextEditingController();
  final focus = FocusNode();
  final chromeFocus = FocusNode();
  final scroll = ScrollController();

  void dispose() {
    visibility.dispose();
    text.dispose();
    focus.dispose();
    chromeFocus.dispose();
    scroll.dispose();
  }
}

Future<_Fixture> _install(
  WidgetTester tester, {
  ResourceFrameReadback? readback,
  required ResourceFrameWriter writer,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(800, 600);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  final fixture = _Fixture();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    fixture.dispose();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    tester.view.resetDevicePixelRatio();
    tester.view.resetPhysicalSize();
  });
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Focus(
                focusNode: fixture.chromeFocus,
                child: const SizedBox(
                  width: 80,
                  height: 220,
                  child: ColoredBox(color: _outsideColor),
                ),
              ),
              ValueListenableBuilder<_Visibility>(
                valueListenable: fixture.visibility,
                builder: (context, value, child) => TickerMode(
                  enabled: value.tickerEnabled,
                  child: value.present
                      ? ResourceMapFrameCapture(
                          active: value.active,
                          readback: readback,
                          writer: writer,
                          child: child!,
                        )
                      : const Text('Other workspace'),
                ),
                child: SizedBox(
                  key: _bodyKey,
                  width: 300,
                  height: 220,
                  child: Material(
                    color: const Color(0xFF185436),
                    child: Column(
                      children: [
                        TextField(
                          key: _fieldKey,
                          controller: fixture.text,
                          focusNode: fixture.focus,
                          decoration: const InputDecoration(
                            isDense: true,
                            hintText: 'Local fixture search',
                          ),
                        ),
                        Expanded(
                          child: ListView.builder(
                            controller: fixture.scroll,
                            itemExtent: 32,
                            itemCount: 20,
                            itemBuilder: (_, index) =>
                                Text('Fixture row $index'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  fixture.focus.requestFocus();
  await tester.pump();
  return fixture;
}

ResourceFramePixels _pixels(RenderRepaintBoundary boundary, double ratio) =>
    ResourceFramePixels(
      // The injected writer only inspects data; the actual PNG test uses the
      // production readback and independently decodes its complete payload.
      png: Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10]),
      width: (boundary.size.width * ratio).ceil(),
      height: (boundary.size.height * ratio).ceil(),
    );

Future<void> _f8(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.f8);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.f8);
  await tester.pump();
}

Future<void> _until(WidgetTester tester, bool Function() ready) async {
  final clock = Stopwatch()..start();
  while (clock.elapsed < const Duration(seconds: 10)) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 16));
    if (ready()) return;
  }
  throw TestFailure('Diagnostic capture did not complete within 10 seconds.');
}
