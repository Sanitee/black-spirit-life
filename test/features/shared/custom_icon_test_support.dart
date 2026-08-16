import 'dart:io';
import 'dart:typed_data';

import 'package:bdo_craft_planner_flutter/data/icons/custom_icon_store.dart';
import 'package:bdo_craft_planner_flutter/domain/state/planner_state.dart';
import 'package:flutter_test/flutter_test.dart';

const String customIconTestDataUri =
    'data:image/png;base64,'
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8A'
    'AQUBAScY42YAAAAASUVORK5CYII=';

final class StoredIconTestFixture {
  const StoredIconTestFixture({
    required this.directory,
    required this.store,
    required this.reference,
    required this.bytes,
  });

  final Directory directory;
  final CustomIconStore store;
  final CustomIconReference reference;
  final Uint8List bytes;

  static Future<StoredIconTestFixture> create() async {
    final directory = await Directory.systemTemp.createTemp(
      'bdo-custom-icon-widget-',
    );
    final store = CustomIconStore(
      applicationDirectory: directory,
      outputDimension: 1,
    );
    final reference = await store.importDataUri(
      customIconTestDataUri,
      sourceName: 'test-custom-icon.png',
    );
    return StoredIconTestFixture(
      directory: directory,
      store: store,
      reference: reference,
      bytes: store.readValidatedBytes(reference),
    );
  }

  Future<void> dispose() async {
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  }
}

/// Lets real file/isolate work progress while retaining deterministic widget
/// pumping. A fake-time duration alone cannot complete asynchronous disk I/O.
Future<void> pumpUntilIconState(
  WidgetTester tester,
  Finder stateFinder, {
  int maximumAttempts = 100,
}) async {
  for (var attempt = 0; attempt < maximumAttempts; attempt += 1) {
    if (stateFinder.evaluate().isNotEmpty) return;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
  }
  throw TestFailure(
    'The expected icon state did not appear after $maximumAttempts attempts.',
  );
}
