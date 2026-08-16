import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:bdo_craft_planner_flutter/data/icons/custom_icon_store.dart';
import 'package:bdo_craft_planner_flutter/data/portable/portable_custom_icon_bridge.dart';
import 'package:bdo_craft_planner_flutter/domain/models/craft_mode.dart';
import 'package:bdo_craft_planner_flutter/domain/state/planner_state.dart';
import 'package:bdo_craft_planner_flutter/domain/state/state_copy.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../domain/state/state_test_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temporaryDirectory;
  late Directory applicationDirectory;
  late PortableCustomIconBridge bridge;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'bdo-portable-icons-',
    );
    applicationDirectory = Directory(
      '${temporaryDirectory.path}${Platform.pathSeparator}application',
    );
    bridge = PortableCustomIconBridge(
      iconStore: CustomIconStore(
        applicationDirectory: applicationDirectory,
        outputDimension: 32,
      ),
    );
  });

  tearDown(() async {
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  test(
    'preview is read-only and confirmation materializes app-owned PNG',
    () async {
      final current = _withoutCustomIcons();
      final before = current.toJson();
      final source = _portableSource(
        'data:image/png;base64,${base64Encode(await _png(12, 8))}',
      );

      final preview = bridge.preview(
        current,
        source,
        confirmLegacyFullReplacement: false,
      );

      expect(preview.pendingIcons, hasLength(1));
      expect(preview.pendingIcons.single.itemName, 'Imported Icon');
      expect(
        preview.result.state.alchemy.customIcons,
        contains('Imported Icon'),
      );
      expect(current.toJson(), before, reason: 'preview must not mutate state');
      expect(
        await applicationDirectory.exists(),
        isFalse,
        reason: 'preview must not create the destination directory',
      );

      final materialized = await bridge.materializeImport(
        current,
        source,
        confirmLegacyFullReplacement: false,
      );

      final reference =
          materialized.state.alchemy.customIcons['Imported Icon']!;
      expect(reference.relativePath, startsWith('icons/'));
      expect(reference.mediaType, 'image/png');
      expect(reference.width, 32);
      expect(reference.height, 32);
      final file = File(
        '${applicationDirectory.path}${Platform.pathSeparator}${reference.relativePath.replaceAll('/', Platform.pathSeparator)}',
      );
      expect(await file.exists(), isTrue);
      expect(await file.length(), reference.byteCount);
      expect(
        bridge.export(reference),
        'data:image/png;base64,${base64Encode(await file.readAsBytes())}',
      );
      expect(current.toJson(), before, reason: 'confirmation returns a clone');
    },
  );

  test(
    'invalid confirmed icon leaves destination and state untouched',
    () async {
      final current = _withoutCustomIcons();
      final before = current.toJson();
      final source = _portableSource('data:image/png;base64,AQID');

      final preview = bridge.preview(
        current,
        source,
        confirmLegacyFullReplacement: false,
      );

      expect(preview.pendingIcons, hasLength(1));
      await expectLater(
        bridge.materializeImport(
          current,
          source,
          confirmLegacyFullReplacement: false,
        ),
        throwsA(isA<CustomIconValidationException>()),
      );
      expect(current.toJson(), before);
      expect(await applicationDirectory.exists(), isFalse);
    },
  );
}

String _portableSource(String dataUri) => jsonEncode({
  'type': 'bdo-tool-portable',
  'version': 4,
  'app': 'BDO Craft Planner',
  'included': {'recipes': true},
  'data': {
    'alchemy': {
      'customIcons': {'Imported Icon': dataUri},
    },
  },
});

PlannerState _withoutCustomIcons() {
  final source = buildStateFixture();
  return source.copyWith(
    alchemy: source.alchemy.copyWith(customIcons: const {}),
    cooking: source.cooking.copyWith(customIcons: const {}),
    processing: source.processing.copyWith(customIcons: const {}),
    activeMode: CraftMode.alchemy,
  );
}

Future<Uint8List> _png(int width, int height) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    ui.Paint()..color = const ui.Color(0xff4cb89b),
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
