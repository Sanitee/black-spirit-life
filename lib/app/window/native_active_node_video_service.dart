import 'dart:async';

import 'package:bdo_map_core/bdo_map_core.dart';
import 'package:flutter/services.dart';

/// Windows-native bridge for importing BDO's Activated production-node list.
///
/// Video decoding and OCR run in an isolated native helper process. If a
/// Windows decoder hangs during cleanup, the helper can be stopped without
/// freezing the planner or losing an OCR result that was already completed.
final class NativeActiveNodeVideoService {
  const NativeActiveNodeVideoService({
    this.pollInterval = const Duration(milliseconds: 50),
    this.finalizationTimeout = const Duration(seconds: 10),
    this.scanTimeout = const Duration(minutes: 2),
  });

  final Duration pollInterval;
  final Duration finalizationTimeout;
  final Duration scanTimeout;

  static const MethodChannel _channel = MethodChannel(
    'com.bdocraftplanner.flutter/window',
  );
  static const MethodChannel _progressChannel = MethodChannel(
    'com.bdocraftplanner.flutter/active_node_video_progress',
  );

  Future<bool> launchRectangleRecording() async {
    try {
      return await _channel.invokeMethod<bool>('launchActiveNodeRecording') ??
          false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<String?> findLatestRecording({DateTime? modifiedAfter}) async {
    try {
      final result = await _channel.invokeMethod<String>(
        'findLatestActiveNodeRecording',
        <String, Object?>{
          'modifiedAfterMilliseconds':
              modifiedAfter?.millisecondsSinceEpoch ?? 0,
        },
      );
      final path = result?.trim();
      return path == null || path.isEmpty ? null : path;
    } on MissingPluginException {
      return null;
    }
  }

  Future<BdoActiveNodeVideoOcrResult> scanRecording(
    String path, {
    void Function(BdoActiveNodeScanProgress progress)? onProgress,
  }) async {
    final normalizedPath = path.trim();
    if (normalizedPath.isEmpty) {
      throw const FormatException('Choose an MP4 recording first.');
    }
    final scanTimer = Stopwatch()..start();
    DateTime? finalizingSince;
    var nativeResultCollected = false;
    _progressChannel.setMethodCallHandler((call) async {
      if (call.method != 'scanProgress') return;
      final values = _map(call.arguments);
      final progress = BdoActiveNodeScanProgress(
        fraction: _number(values['fraction']).clamp(0.0, 1.0),
        completedFrames: _integer(values['completedFrames']),
        estimatedFrames: _integer(values['estimatedFrames']),
      );
      if (progress.fraction >= .97) {
        finalizingSince ??= DateTime.now();
      }
      onProgress?.call(progress);
    });
    try {
      final started = await _channel.invokeMethod<bool>(
        'scanActiveNodeRecording',
        <String, Object?>{'path': normalizedPath},
      );
      if (started != true) {
        throw const FormatException('Windows could not start the MP4 scan.');
      }
      while (true) {
        final raw = await _channel.invokeMapMethod<Object?, Object?>(
          'pollActiveNodeRecordingScan',
        );
        if (raw != null) {
          nativeResultCollected = true;
          return _decodeResult(raw);
        }
        final finalizingAt = finalizingSince;
        if (finalizingAt != null &&
            DateTime.now().difference(finalizingAt) >= finalizationTimeout) {
          throw TimeoutException(
            'The isolated scanner read every frame but did not return its OCR '
            'result. It was stopped safely instead of remaining stuck.',
          );
        }
        if (scanTimer.elapsed >= scanTimeout) {
          throw TimeoutException(
            'The isolated Windows scanner did not return a result within two '
            'minutes and was stopped. The planner remained responsive.',
          );
        }
        await Future<void>.delayed(pollInterval);
      }
    } finally {
      _progressChannel.setMethodCallHandler(null);
      if (!nativeResultCollected) {
        try {
          await _channel.invokeMethod<void>('cancelActiveNodeRecordingScan');
        } on PlatformException {
          // Preserve the original scan error.
        } on MissingPluginException {
          // The app may be shutting down.
        }
      }
    }
  }

  static BdoActiveNodeVideoOcrResult _decodeResult(Map<Object?, Object?> raw) {
    final frames = <BdoActiveNodeOcrFrame>[];
    for (final rawFrame in _list(raw['frames'])) {
      final frame = _map(rawFrame);
      final frameIndex = _integer(frame['index']);
      final timestamp = _integer(frame['timestampMilliseconds']);
      final sharpness = _number(frame['sharpness']);
      frames.add(
        BdoActiveNodeOcrFrame(
          frameIndex: frameIndex,
          timestampMilliseconds: timestamp,
          sharpness: sharpness,
          lines: <BdoActiveNodeOcrLine>[
            for (final rawLine in _list(frame['lines']))
              BdoActiveNodeOcrLine(
                text: _map(rawLine)['text']?.toString() ?? '',
                frameIndex: frameIndex,
                timestampMilliseconds: timestamp,
                frameSharpness: sharpness,
                left: _number(_map(rawLine)['left']),
                top: _number(_map(rawLine)['top']),
                width: _number(_map(rawLine)['width']),
                height: _number(_map(rawLine)['height']),
              ),
          ],
        ),
      );
    }
    if (frames.isEmpty) {
      throw const FormatException(
        'Windows OCR did not return any readable video frames.',
      );
    }
    return BdoActiveNodeVideoOcrResult(
      sourcePath: raw['sourcePath']?.toString() ?? '',
      ocrLanguage: raw['ocrLanguage']?.toString() ?? '',
      sourceWidth: _integer(raw['sourceWidth']),
      sourceHeight: _integer(raw['sourceHeight']),
      durationMilliseconds: _integer(raw['durationMilliseconds']),
      frames: frames,
      diagnostics: <String>[
        for (final value in _list(raw['diagnostics'])) value.toString(),
      ],
    );
  }

  static Map<Object?, Object?> _map(Object? value) =>
      value is Map ? Map<Object?, Object?>.from(value) : <Object?, Object?>{};

  static List<Object?> _list(Object? value) =>
      value is List ? List<Object?>.from(value) : const <Object?>[];

  static int _integer(Object? value) => value is num ? value.toInt() : 0;

  static double _number(Object? value) => value is num ? value.toDouble() : 0;
}
