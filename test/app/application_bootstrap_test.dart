import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:bdo_craft_planner_flutter/app/application_bootstrap.dart';
import 'package:bdo_craft_planner_flutter/data/persistence/planner_state_repository.dart';
import 'package:bdo_craft_planner_flutter/domain/models/catalog_models.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temporaryDirectory;
  late Directory applicationDirectory;
  late File legacyStateFile;
  late PlannerStatePathPolicy paths;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'bdo-bootstrap-icons-',
    );
    applicationDirectory = Directory(
      '${temporaryDirectory.path}${Platform.pathSeparator}flutter',
    );
    legacyStateFile = File(
      '${temporaryDirectory.path}${Platform.pathSeparator}avalonia${Platform.pathSeparator}planner-state.json',
    );
    paths = PlannerStatePathPolicy(
      applicationDirectory: applicationDirectory,
      legacyStateFile: legacyStateFile,
    );
  });

  tearDown(() async {
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  test(
    'startup keeps saved editor tools off until explicitly enabled',
    () async {
      final repository = PlannerStateRepository(
        paths: paths,
        applicationVersion: 'test',
      );
      final fresh = await repository.load(_catalog());
      await repository.save(fresh.state.copyWith(showDeleteTools: true));

      final bundle = await const ApplicationBootstrapService(
        applicationVersion: 'test',
      ).load(catalogFuture: Future.value(_catalog()), pathPolicy: paths);
      addTearDown(bundle.controller.dispose);

      expect(bundle.stateLoad.state.showDeleteTools, isTrue);
      expect(bundle.controller.documentSnapshot.showDeleteTools, isFalse);
      expect(bundle.controller.deleteToolsEnabled.value, isFalse);
    },
  );

  test('first run previews before approved icon-preserving import', () async {
    final sourcePng = await _png(9, 5);
    final legacyBytes = _legacyBytes(
      'data:image/png;base64,${base64Encode(sourcePng)}',
    );
    await legacyStateFile.parent.create(recursive: true);
    await legacyStateFile.writeAsBytes(legacyBytes, flush: true);

    final bundle = await const ApplicationBootstrapService(
      applicationVersion: 'test',
    ).load(catalogFuture: Future.value(_catalog()), pathPolicy: paths);
    addTearDown(bundle.controller.dispose);

    expect(bundle.stateLoad.origin, PlannerStateLoadOrigin.awaitingMigration);
    expect(bundle.firstLaunchMigration, isNotNull);
    expect(bundle.stateLoad.pendingCustomIcons, isEmpty);
    expect(
      bundle.firstLaunchMigration!.preview.pendingCustomIcons,
      hasLength(1),
    );
    expect(
      await File(
        '${applicationDirectory.path}${Platform.pathSeparator}${PlannerStateRepository.stateFileName}',
      ).exists(),
      isFalse,
    );
    expect(await _ownedIconFiles(applicationDirectory), isEmpty);
    expect(await _migrationArchives(applicationDirectory), isEmpty);
    expect(await legacyStateFile.readAsBytes(), legacyBytes);

    final resolved = await bundle.firstLaunchMigration!.accept();
    addTearDown(resolved.controller.dispose);

    expect(resolved.stateLoad.origin, PlannerStateLoadOrigin.migratedAvalonia);
    expect(resolved.firstLaunchMigration, isNull);
    expect(
      resolved.stateLoad.notices,
      contains('Imported 1 custom icon file(s).'),
    );
    expect(resolved.stateLoad.sourceUnchangedAfterMigration, isTrue);
    expect(await legacyStateFile.readAsBytes(), legacyBytes);

    final reference =
        resolved.stateLoad.state.alchemy.customIcons['Migrated Icon']!;
    expect(reference.mediaType, 'image/png');
    expect(reference.width, 512);
    expect(reference.height, 512);
    final iconFile = File(
      '${applicationDirectory.path}${Platform.pathSeparator}${reference.relativePath.replaceAll('/', Platform.pathSeparator)}',
    );
    final storedBytes = await iconFile.readAsBytes();
    expect(storedBytes, hasLength(reference.byteCount));
    expect(
      sha256.convert(storedBytes).toString().toUpperCase(),
      reference.sha256,
    );
    expect(await _alphaAt(storedBytes, 1, 1), 0);
    expect(await _alphaAt(storedBytes, 256, 256), greaterThan(0));

    final nativeState = File(
      '${applicationDirectory.path}${Platform.pathSeparator}${PlannerStateRepository.stateFileName}',
    );
    final nativeJson = await nativeState.readAsString();
    expect(nativeJson, isNot(contains('data:image/')));
    expect(nativeJson, contains(reference.relativePath));
    final nativeBytes = await nativeState.readAsBytes();
    expect(
      resolved.stateLoad.migrationReport!.targetByteCount,
      nativeBytes.length,
    );
    expect(
      resolved.stateLoad.migrationReport!.targetSha256,
      sha256.convert(nativeBytes).toString().toUpperCase(),
    );

    final restarted = await const ApplicationBootstrapService(
      applicationVersion: 'test',
    ).load(catalogFuture: Future.value(_catalog()), pathPolicy: paths);
    addTearDown(restarted.controller.dispose);
    expect(restarted.stateLoad.origin, PlannerStateLoadOrigin.native);
    expect(restarted.firstLaunchMigration, isNull);
    expect(
      restarted.stateLoad.state.alchemy.customIcons['Migrated Icon']!.toJson(),
      reference.toJson(),
    );
    expect(await iconFile.exists(), isTrue);
    expect(await legacyStateFile.readAsBytes(), legacyBytes);
  });

  test('failed state write rolls back icons and remains retryable', () async {
    final sourcePng = await _png(9, 5);
    final legacyBytes = _legacyBytes(
      'data:image/png;base64,${base64Encode(sourcePng)}',
    );
    await legacyStateFile.parent.create(recursive: true);
    await legacyStateFile.writeAsBytes(legacyBytes, flush: true);
    final bundle = await const ApplicationBootstrapService(
      applicationVersion: 'test',
    ).load(catalogFuture: Future.value(_catalog()), pathPolicy: paths);
    addTearDown(bundle.controller.dispose);
    final blockingTarget = Directory(
      '${applicationDirectory.path}${Platform.pathSeparator}${PlannerStateRepository.stateFileName}',
    );
    await blockingTarget.create(recursive: true);

    await expectLater(
      bundle.firstLaunchMigration!.accept(),
      throwsA(isA<Object>()),
    );

    expect(await _ownedIconFiles(applicationDirectory), isEmpty);
    expect(await _migrationArchives(applicationDirectory), isEmpty);
    expect(await legacyStateFile.readAsBytes(), legacyBytes);
    await blockingTarget.delete();

    final retried = await bundle.firstLaunchMigration!.accept();
    addTearDown(retried.controller.dispose);
    expect(retried.stateLoad.origin, PlannerStateLoadOrigin.migratedAvalonia);
    expect(
      retried.stateLoad.state.alchemy.customIcons,
      contains('Migrated Icon'),
    );
    expect(await _ownedIconFiles(applicationDirectory), hasLength(1));
  });
}

Uint8List _legacyBytes(String iconDataUri) => Uint8List.fromList(
  utf8.encode(
    jsonEncode({
      'version': 1,
      'activeMode': 'alchemy',
      'alchemy': {
        'version': 1,
        'target': 'Alchemy Target',
        'want': 7,
        'customIcons': {'Migrated Icon': iconDataUri},
      },
      'cooking': {'version': 1, 'target': 'Cooking Target'},
      'processing': {'version': 1, 'target': 'Processing Target'},
    }),
  ),
);

Future<List<File>> _ownedIconFiles(Directory applicationDirectory) async {
  final directory = Directory(
    '${applicationDirectory.path}${Platform.pathSeparator}icons',
  );
  if (!await directory.exists()) return const <File>[];
  return directory
      .list(followLinks: false)
      .where((entity) => entity is File)
      .cast<File>()
      .toList();
}

Future<List<File>> _migrationArchives(Directory applicationDirectory) async {
  final directory = Directory(
    '${applicationDirectory.path}${Platform.pathSeparator}migration',
  );
  if (!await directory.exists()) return const <File>[];
  return directory
      .list(followLinks: false)
      .where((entity) => entity is File)
      .cast<File>()
      .toList();
}

Future<int> _alphaAt(Uint8List png, int x, int y) async {
  final buffer = await ui.ImmutableBuffer.fromUint8List(png);
  ui.ImageDescriptor? descriptor;
  ui.Codec? codec;
  ui.Image? image;
  try {
    descriptor = await ui.ImageDescriptor.encoded(buffer);
    codec = await descriptor.instantiateCodec();
    image = (await codec.getNextFrame()).image;
    final pixels = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    return pixels!.getUint8(((y * image.width) + x) * 4 + 3);
  } finally {
    image?.dispose();
    codec?.dispose();
    descriptor?.dispose();
    buffer.dispose();
  }
}

CatalogSnapshot _catalog() => CatalogSnapshot(
  sourceSha256: 'fixture',
  sourceByteCount: 1,
  alchemy: _mode(CraftMode.alchemy, 'Alchemy Target'),
  cooking: _mode(CraftMode.cooking, 'Cooking Target'),
  processing: _mode(CraftMode.processing, 'Processing Target'),
  supportingData: const {},
  collisions: const [],
);

ModeCatalog _mode(CraftMode mode, String target) => ModeCatalog(
  mode: mode,
  items: {target: _recipe(target, mode)},
  iconDataUris: const {},
  defaults: {
    'target': target,
    'want': 100,
    'yieldMult': mode == CraftMode.alchemy ? 3.2 : 1,
    'inv': const <String, double>{},
    'favoriteRecipes': <String>[target],
  },
  metadata: const {},
  searchAliases: const {},
);

Recipe _recipe(String name, CraftMode mode) => Recipe(
  name: name,
  type: mode.key,
  baseOutput: 1,
  group: null,
  method: null,
  ingredients: [
    Ingredient(
      name: 'Base',
      quantity: 1,
      options: const [],
      substituteGroup: null,
      substituteRatios: const {},
    ),
  ],
  marketId: null,
  sourceNote: null,
  vendor: null,
  location: null,
  npcPrice: 0,
  qualityBase: null,
  qualityGrade: null,
  outputMinimum: 1,
  outputMaximum: 1,
);

Future<Uint8List> _png(int width, int height) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    ui.Paint()..color = const ui.Color(0xff9265d6),
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
