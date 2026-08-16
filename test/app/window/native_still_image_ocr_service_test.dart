import 'dart:async';

import 'package:bdo_craft_planner_flutter/app/window/native_still_image_ocr_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.bdocraftplanner.flutter/window');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('starts, polls, and decodes individual inventory OCR words', () async {
    final calls = <MethodCall>[];
    var polls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method == 'scanInventoryScreenshot') return true;
          if (call.method != 'pollInventoryScreenshotScan') return null;
          polls += 1;
          if (polls == 1) return null;
          return <String, Object?>{
            'sourceWidth': 1029,
            'sourceHeight': 775,
            'ocrLanguage': 'en-US',
            'frames': <Object?>[
              <String, Object?>{
                'lines': <Object?>[
                  <String, Object?>{
                    'text': 'Calpheon',
                    'left': 67.0,
                    'top': 30.0,
                    'width': 80.0,
                    'height': 18.0,
                  },
                  <String, Object?>{
                    'text': '219.5K',
                    'left': 903.0,
                    'top': 408.0,
                    'width': 48.0,
                    'height': 12.0,
                  },
                ],
              },
            ],
            'diagnostics': <Object?>['2 OCR words'],
          };
        });

    const service = NativeStillImageOcrService(
      pollInterval: Duration(milliseconds: 1),
    );
    final result = await service.scanPath(r'C:\storage.png');

    expect(result.sourceWidth, 1029);
    expect(result.sourceHeight, 775);
    expect(result.lines.map((line) => line.text), <String>[
      'Calpheon',
      '219.5K',
    ]);
    expect(result.lines.last.left, 903);
    expect(result.diagnostics, <String>['2 OCR words']);
    expect(calls.first.method, 'scanInventoryScreenshot');
    expect(calls.first.arguments, <String, Object?>{'path': r'C:\storage.png'});
    expect(polls, 2);
    expect(
      calls.where((call) => call.method == 'cancelInventoryScreenshotScan'),
      isEmpty,
    );
  });

  test('cancels an isolated still-image scan after timeout', () async {
    var cancellations = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'scanInventoryScreenshot') return true;
          if (call.method == 'pollInventoryScreenshotScan') return null;
          if (call.method == 'cancelInventoryScreenshotScan') {
            cancellations += 1;
          }
          return null;
        });

    const service = NativeStillImageOcrService(
      pollInterval: Duration(milliseconds: 1),
      scanTimeout: Duration(milliseconds: 5),
    );

    await expectLater(
      service.scanPath(r'C:\stuck.png'),
      throwsA(isA<TimeoutException>()),
    );
    expect(cancellations, 1);
  });
}
