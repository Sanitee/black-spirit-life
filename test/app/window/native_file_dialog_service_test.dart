import 'dart:io';

import 'package:bdo_craft_planner_flutter/app/window/native_file_dialog_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.bdocraftplanner.flutter/window');
  const service = NativeFileDialogService();

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
    'uses native JSON, image, video, folder, and save dialog contracts',
    () async {
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return ' C:\\chosen\\file.json ';
          });

      expect(await service.pickJsonToOpen(), r'C:\chosen\file.json');
      expect(await service.pickImageToOpen(), r'C:\chosen\file.json');
      expect(await service.pickVideoToOpen(), r'C:\chosen\file.json');
      expect(
        await service.pickDirectory(initialPath: r'C:\current\profile'),
        r'C:\chosen\file.json',
      );
      expect(
        await service.pickJsonDestination(defaultName: 'backup.json'),
        r'C:\chosen\file.json',
      );
      expect(calls[0].arguments, {'kind': 'json'});
      expect(calls[1].arguments, {'kind': 'image'});
      expect(calls[2].arguments, {'kind': 'video'});
      expect(calls[3].arguments, {'initialPath': r'C:\current\profile'});
      expect(calls[4].arguments, {'defaultName': 'backup.json'});
    },
  );

  test('returns null when the user cancels', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => null);
    expect(await service.pickJsonToOpen(), isNull);
  });

  test('Windows folder picker fails closed unless folder flags are set', () {
    final source = File('windows/runner/flutter_window.cpp').readAsStringSync();

    expect(source, contains('const HRESULT get_options_result'));
    expect(source, contains('if (FAILED(get_options_result))'));
    expect(source, contains('const HRESULT set_options_result'));
    expect(source, contains('if (FAILED(set_options_result))'));
    expect(source, contains('FOS_PICKFOLDERS | FOS_FORCEFILESYSTEM'));
    expect(source, contains('result->Error("folder_picker_unavailable"'));
  });
}
