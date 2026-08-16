import 'dart:io';

import 'package:bdo_craft_planner_flutter/data/portable/portable_file_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('saves and validates a portable JSON object atomically', () async {
    final temp = await Directory.systemTemp.createTemp('bdo-portable-file-');
    addTearDown(() async {
      if (await temp.exists()) await temp.delete(recursive: true);
    });
    final path = '${temp.path}${Platform.pathSeparator}backup.json';

    final result = await const PortableFileService().saveJson(
      path,
      '{"type":"fixture"}',
    );

    expect(result.targetPath, path);
    expect(
      await const PortableFileService().loadJson(path),
      contains('fixture'),
    );
  });
}
