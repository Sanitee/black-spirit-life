import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:bdo_craft_planner_flutter/data/icons/custom_icon_store.dart';
import 'package:bdo_craft_planner_flutter/domain/state/planner_state.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('bdo-custom-icons-');
  });

  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  test('normalizes a rectangular image into an app-owned square PNG', () async {
    final source = await _png(width: 12, height: 8);
    final store = CustomIconStore(
      applicationDirectory: temp,
      outputDimension: 32,
    );

    final reference = await store.importBytes(
      source,
      sourceName: 'selected.png',
    );

    expect(reference.relativePath, startsWith('icons/'));
    expect(reference.mediaType, 'image/png');
    expect(reference.width, 32);
    expect(reference.height, 32);
    final file = File(
      '${temp.path}${Platform.pathSeparator}${reference.relativePath.replaceAll('/', Platform.pathSeparator)}',
    );
    expect(await file.exists(), isTrue);
    expect(await file.length(), reference.byteCount);

    await store.remove(reference);
    expect(await file.exists(), isFalse);
  });

  test(
    'rejects unsupported and oversized source bytes without writing',
    () async {
      final store = CustomIconStore(
        applicationDirectory: temp,
        maxSourceBytes: 16,
        outputDimension: 8,
      );

      await expectLater(
        store.importBytes(Uint8List.fromList([1, 2, 3]), sourceName: 'bad.bin'),
        throwsA(isA<CustomIconValidationException>()),
      );
      await expectLater(
        store.importBytes(Uint8List(17), sourceName: 'large.png'),
        throwsA(isA<CustomIconValidationException>()),
      );
      expect(await store.iconDirectory.exists(), isFalse);
    },
  );

  test(
    'export verifies the normalized PNG bytes and all declared metadata',
    () async {
      final store = CustomIconStore(
        applicationDirectory: temp,
        outputDimension: 32,
      );
      final reference = await store.importBytes(
        await _png(width: 12, height: 8),
        sourceName: 'selected.png',
      );
      final file = File(
        '${temp.path}${Platform.pathSeparator}${reference.relativePath.replaceAll('/', Platform.pathSeparator)}',
      );
      final bytes = await file.readAsBytes();

      final exported = UriData.parse(store.exportDataUri(reference));
      expect(exported.mimeType, 'image/png');
      expect(exported.contentAsBytes(), bytes);
      expect(reference.byteCount, bytes.length);
      expect(reference.sha256, sha256.convert(bytes).toString().toUpperCase());

      expect(
        () => store.exportDataUri(
          _referenceLike(reference, mediaType: 'image/jpeg'),
        ),
        throwsA(isA<CustomIconValidationException>()),
      );
      expect(
        () => store.exportDataUri(_referenceLike(reference, width: 31)),
        throwsA(isA<CustomIconValidationException>()),
      );
      expect(
        () => store.exportDataUri(_referenceLike(reference, height: 31)),
        throwsA(isA<CustomIconValidationException>()),
      );
      expect(
        () => store.exportDataUri(
          _referenceLike(reference, byteCount: reference.byteCount + 1),
        ),
        throwsA(isA<CustomIconValidationException>()),
      );

      final corrupted = Uint8List.fromList(bytes);
      corrupted[corrupted.length - 1] ^= 0xff;
      await file.writeAsBytes(corrupted, flush: true);
      expect(
        () => store.exportDataUri(reference),
        throwsA(isA<CustomIconValidationException>()),
      );
    },
  );

  test('rejects a forged hash path before export or removal', () async {
    final store = CustomIconStore(
      applicationDirectory: temp,
      outputDimension: 8,
    );
    final outside = File('${temp.path}${Platform.pathSeparator}outside.png');
    await outside.writeAsBytes(await _png(width: 8, height: 8), flush: true);
    final forged = CustomIconReference(
      relativePath: 'icons/../outside.png',
      sha256: '../outside',
      mediaType: 'image/png',
      byteCount: await outside.length(),
      width: 8,
      height: 8,
    );

    expect(
      () => store.exportDataUri(forged),
      throwsA(isA<CustomIconValidationException>()),
    );
    await expectLater(
      store.remove(forged),
      throwsA(isA<CustomIconValidationException>()),
    );
    expect(await outside.exists(), isTrue);
  });

  test(
    'async reads cache validated bytes but reject stale or missing files',
    () async {
      final store = CustomIconStore(
        applicationDirectory: temp,
        outputDimension: 32,
      );
      final reference = await store.importBytes(
        await _png(width: 12, height: 8),
        sourceName: 'selected.png',
      );
      final file = File(
        '${temp.path}${Platform.pathSeparator}${reference.relativePath.replaceAll('/', Platform.pathSeparator)}',
      );

      final first = await store.readValidatedBytesAsync(reference);
      final cached = await store.readValidatedBytesAsync(reference);
      expect(identical(first, cached), isTrue);

      final corrupted = Uint8List.fromList(first);
      corrupted[corrupted.length - 1] ^= 0xff;
      await file.writeAsBytes(corrupted, flush: true);
      await file.setLastModified(DateTime.utc(2026, 7, 20, 12));
      await expectLater(
        store.readValidatedBytesAsync(reference),
        throwsA(isA<CustomIconValidationException>()),
      );

      await file.writeAsBytes(first, flush: true);
      await file.setLastModified(DateTime.utc(2026, 7, 20, 12, 1));
      final restored = await store.readValidatedBytesAsync(reference);
      expect(restored, orderedEquals(first));
      expect(identical(restored, first), isFalse);

      await file.delete();
      await expectLater(
        store.readValidatedBytesAsync(reference),
        throwsA(isA<CustomIconValidationException>()),
      );
      store.dispose();
    },
  );

  test('async cache is bounded and disposed stores reject new loads', () async {
    final store = CustomIconStore(
      applicationDirectory: temp,
      outputDimension: 16,
      maxCachedEntries: 1,
    );
    final firstReference = await store.importBytes(
      await _png(width: 8, height: 8),
      sourceName: 'first.png',
    );
    final secondReference = await store.importBytes(
      await _png(width: 8, height: 8, color: const ui.Color(0xffcc7854)),
      sourceName: 'second.png',
    );

    final first = await store.readValidatedBytesAsync(firstReference);
    await store.readValidatedBytesAsync(secondReference);
    final reloaded = await store.readValidatedBytesAsync(firstReference);
    expect(reloaded, orderedEquals(first));
    expect(identical(reloaded, first), isFalse);

    store.dispose();
    await expectLater(
      store.readValidatedBytesAsync(firstReference),
      throwsA(isA<CustomIconValidationException>()),
    );
  });

  test(
    'copies a validated normalized icon without changing its reference',
    () async {
      final sourceDirectory = Directory(
        '${temp.path}${Platform.pathSeparator}former',
      );
      final destinationDirectory = Directory(
        '${temp.path}${Platform.pathSeparator}beta',
      );
      final sourceStore = CustomIconStore(
        applicationDirectory: sourceDirectory,
        outputDimension: 32,
      );
      final destinationStore = CustomIconStore(
        applicationDirectory: destinationDirectory,
        outputDimension: 32,
      );
      final reference = await sourceStore.importBytes(
        await _png(width: 12, height: 8),
        sourceName: 'former.png',
      );

      final copied = await destinationStore.copyValidatedReferenceFrom(
        reference: reference,
        sourceApplicationDirectory: sourceDirectory,
      );
      final repeated = await destinationStore.copyValidatedReferenceFrom(
        reference: reference,
        sourceApplicationDirectory: sourceDirectory,
      );

      expect(copied.reference.toJson(), reference.toJson());
      expect(copied.created, isTrue);
      expect(repeated.created, isFalse);
      expect(
        destinationStore.readValidatedBytes(reference),
        sourceStore.readValidatedBytes(reference),
      );
    },
  );
}

CustomIconReference _referenceLike(
  CustomIconReference source, {
  String? mediaType,
  int? byteCount,
  int? width,
  int? height,
}) => CustomIconReference(
  relativePath: source.relativePath,
  sha256: source.sha256,
  mediaType: mediaType ?? source.mediaType,
  byteCount: byteCount ?? source.byteCount,
  width: width ?? source.width,
  height: height ?? source.height,
);

Future<Uint8List> _png({
  required int width,
  required int height,
  ui.Color color = const ui.Color(0xff4cb89b),
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    ui.Paint()..color = color,
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  } finally {
    image.dispose();
    picture.dispose();
  }
}
