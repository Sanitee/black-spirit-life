import 'dart:io';
import 'package:bdo_craft_planner_flutter/app/window/native_folder_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'opens only the existing folder using separate Explorer arguments',
    () async {
      final calls = <(String, List<String>)>[];
      final service = NativeFolderService(
        isWindows: true,
        windowsDirectory: r'C:\Windows',
        directoryExists: (_) async => true,
        launch: (executable, arguments) async =>
            calls.add((executable, arguments)),
      );
      await service.open(r'Q:\Example\BS Life App & settings');
      expect(calls, hasLength(1));
      expect(calls.single.$1, r'C:\Windows\explorer.exe');
      expect(calls.single.$2, [
        r'Q:\Example\BS Life App & settings',
      ]);
      await service.open(r'\\server\profiles\BS Life App');
      expect(calls.last.$2, [r'\\server\profiles\BS Life App']);
    },
  );

  test('invalid and missing paths never launch or create anything', () async {
    var launches = 0;
    final service = NativeFolderService(
      isWindows: true,
      directoryExists: (_) async => false,
      launch: (_, _) async => launches++,
    );
    for (final path in [
      '',
      'relative',
      '/select,C:\\data',
      'https://example.com',
      'C:\\data\nx',
      'C:\\data"x',
    ]) {
      await expectLater(service.open(path), throwsFormatException);
    }
    await expectLater(
      service.open(r'D:\Unavailable'),
      throwsA(isA<FileSystemException>()),
    );
    expect(launches, 0);
  });

  test('unsupported platforms do not launch', () async {
    await expectLater(
      const NativeFolderService(isWindows: false).open(r'C:\Data'),
      throwsUnsupportedError,
    );
  });

  test('launch failures propagate for the UI to report', () async {
    final service = NativeFolderService(
      isWindows: true,
      directoryExists: (_) async => true,
      launch: (_, _) async =>
          throw const ProcessException('explorer', [], 'Unavailable'),
    );
    await expectLater(
      service.open(r'C:\Data'),
      throwsA(isA<ProcessException>()),
    );
  });
}
