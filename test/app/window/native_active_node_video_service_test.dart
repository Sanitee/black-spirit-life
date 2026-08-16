import 'dart:async';

import 'package:bdo_craft_planner_flutter/app/window/native_active_node_video_service.dart';
import 'package:bdo_map_core/bdo_map_core.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.bdocraftplanner.flutter/window');
  const progressChannel = MethodChannel(
    'com.bdocraftplanner.flutter/active_node_video_progress',
  );
  const service = NativeActiveNodeVideoService();

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    progressChannel.setMethodCallHandler(null);
  });

  test('launches, finds, and decodes an OCR recording', () async {
    final calls = <MethodCall>[];
    final progress = <BdoActiveNodeScanProgress>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method == 'scanActiveNodeRecording') {
            await TestDefaultBinaryMessengerBinding
                .instance
                .defaultBinaryMessenger
                .handlePlatformMessage(
                  progressChannel.name,
                  progressChannel.codec.encodeMethodCall(
                    const MethodCall('scanProgress', <String, Object?>{
                      'fraction': .45,
                      'completedFrames': 9,
                      'estimatedFrames': 20,
                    }),
                  ),
                  (_) {},
                );
          }
          return switch (call.method) {
            'launchActiveNodeRecording' => true,
            'findLatestActiveNodeRecording' => r'C:\clip.mp4',
            'scanActiveNodeRecording' => true,
            'pollActiveNodeRecordingScan' => <String, Object?>{
              'sourcePath': r'C:\clip.mp4',
              'ocrLanguage': 'en-US',
              'sourceWidth': 332,
              'sourceHeight': 422,
              'durationMilliseconds': 12000,
              'frames': <Object?>[
                <String, Object?>{
                  'index': 2,
                  'timestampMilliseconds': 640,
                  'sharpness': .21,
                  'lines': <Object?>[
                    <String, Object?>{
                      'text': 'Behr Riverhead - Mining',
                      'left': 14.0,
                      'top': 88.0,
                      'width': 240.0,
                      'height': 22.0,
                    },
                  ],
                },
              ],
              'diagnostics': <Object?>['1 sharp frame'],
            },
            _ => null,
          };
        });

    expect(await service.launchRectangleRecording(), isTrue);
    final after = DateTime.fromMillisecondsSinceEpoch(1234);
    expect(
      await service.findLatestRecording(modifiedAfter: after),
      r'C:\clip.mp4',
    );
    final result = await service.scanRecording(
      r'C:\clip.mp4',
      onProgress: progress.add,
    );

    expect(result.sourceWidth, 332);
    expect(result.frames, hasLength(1));
    expect(result.frames.single.lines.single.text, 'Behr Riverhead - Mining');
    expect(result.frames.single.lines.single.frameIndex, 2);
    expect(result.diagnostics, <String>['1 sharp frame']);
    expect(progress, hasLength(1));
    expect(progress.single.fraction, .45);
    expect(progress.single.completedFrames, 9);
    expect(progress.single.estimatedFrames, 20);
    expect(calls[1].arguments, <String, Object?>{
      'modifiedAfterMilliseconds': 1234,
    });
    expect(calls[2].arguments, <String, Object?>{'path': r'C:\clip.mp4'});
    expect(calls[3].method, 'pollActiveNodeRecordingScan');
  });

  test('rejects an empty native OCR result', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          (call) async => switch (call.method) {
            'scanActiveNodeRecording' => true,
            'pollActiveNodeRecordingScan' => <String, Object?>{
              'frames': <Object?>[],
            },
            _ => null,
          },
        );

    await expectLater(
      service.scanRecording(r'C:\empty.mp4'),
      throwsA(isA<FormatException>()),
    );
  });

  test('polls independently until the native result is ready', () async {
    var polls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'scanActiveNodeRecording') return true;
          if (call.method != 'pollActiveNodeRecordingScan') return null;
          polls += 1;
          if (polls < 3) return null;
          return <String, Object?>{
            'sourcePath': r'C:\clip.mp4',
            'frames': <Object?>[
              <String, Object?>{
                'index': 0,
                'lines': <Object?>[
                  <String, Object?>{'text': 'Godu Village - Farming'},
                ],
              },
            ],
          };
        });

    final result = await service.scanRecording(r'C:\clip.mp4');

    expect(polls, 3);
    expect(result.frames.single.lines.single.text, 'Godu Village - Farming');
  });

  test('cancels instead of remaining stuck after OCR reaches 97%', () async {
    const timedService = NativeActiveNodeVideoService(
      pollInterval: Duration(milliseconds: 1),
      finalizationTimeout: Duration(milliseconds: 8),
      scanTimeout: Duration(seconds: 1),
    );
    var cancellations = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'scanActiveNodeRecording') {
            await TestDefaultBinaryMessengerBinding
                .instance
                .defaultBinaryMessenger
                .handlePlatformMessage(
                  progressChannel.name,
                  progressChannel.codec.encodeMethodCall(
                    const MethodCall('scanProgress', <String, Object?>{
                      'fraction': .97,
                      'completedFrames': 32,
                      'estimatedFrames': 32,
                    }),
                  ),
                  (_) {},
                );
            return true;
          }
          if (call.method == 'pollActiveNodeRecordingScan') return null;
          if (call.method == 'cancelActiveNodeRecordingScan') {
            cancellations += 1;
          }
          return null;
        });

    await expectLater(
      timedService.scanRecording(r'C:\stuck.mp4'),
      throwsA(isA<TimeoutException>()),
    );
    expect(cancellations, 1);
  });
}
