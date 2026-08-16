import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

final class StillImageOcrLine {
  const StillImageOcrLine({
    required this.text,
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  final String text;
  final double left;
  final double top;
  final double width;
  final double height;
}

final class StillImageOcrResult {
  const StillImageOcrResult({
    required this.sourceWidth,
    required this.sourceHeight,
    required this.ocrLanguage,
    required this.lines,
    required this.diagnostics,
  });

  final int sourceWidth;
  final int sourceHeight;
  final String ocrLanguage;
  final List<StillImageOcrLine> lines;
  final List<String> diagnostics;
}

/// Runs still-image OCR in the existing isolated Windows scanner process.
///
/// The planner remains responsive if an image decoder or OCR component stalls.
/// Clipboard bytes are written only to an app-owned temporary PNG and that
/// temporary file is removed after the helper returns.
final class NativeStillImageOcrService {
  const NativeStillImageOcrService({
    this.pollInterval = const Duration(milliseconds: 50),
    this.scanTimeout = const Duration(seconds: 45),
  });

  final Duration pollInterval;
  final Duration scanTimeout;

  static const MethodChannel _channel = MethodChannel(
    'com.bdocraftplanner.flutter/window',
  );

  Future<StillImageOcrResult> scanPath(String path) async {
    final normalized = path.trim();
    if (normalized.isEmpty) {
      throw const FormatException('Choose an inventory screenshot first.');
    }
    var resultCollected = false;
    final timer = Stopwatch()..start();
    try {
      final started = await _channel.invokeMethod<bool>(
        'scanInventoryScreenshot',
        <String, Object?>{'path': normalized},
      );
      if (started != true) {
        throw const FormatException(
          'Windows could not start reading that screenshot.',
        );
      }
      while (timer.elapsed < scanTimeout) {
        final raw = await _channel.invokeMapMethod<Object?, Object?>(
          'pollInventoryScreenshotScan',
        );
        if (raw != null) {
          resultCollected = true;
          return _decode(raw);
        }
        await Future<void>.delayed(pollInterval);
      }
      throw TimeoutException(
        'Windows did not finish reading that screenshot within 45 seconds.',
      );
    } finally {
      if (!resultCollected) {
        try {
          await _channel.invokeMethod<void>('cancelInventoryScreenshotScan');
        } on PlatformException {
          // Preserve the original OCR error.
        } on MissingPluginException {
          // The app may be shutting down.
        }
      }
    }
  }

  Future<StillImageOcrResult> scanPngBytes(Uint8List bytes) async {
    if (bytes.isEmpty) {
      throw const FormatException('The clipboard does not contain an image.');
    }
    final directory = await Directory.systemTemp.createTemp(
      'black-spirit-life-inventory-ocr-',
    );
    final file = File(
      '${directory.path}${Platform.pathSeparator}storage-screenshot.png',
    );
    try {
      await file.writeAsBytes(bytes, flush: true);
      return await scanPath(file.path);
    } finally {
      try {
        if (directory.existsSync()) directory.deleteSync(recursive: true);
      } on FileSystemException {
        // Windows may keep the decoder handle briefly. The app-owned temp is
        // harmless and the operating system can clean it later.
      }
    }
  }

  static StillImageOcrResult _decode(Map<Object?, Object?> raw) {
    final rawFrames = _list(raw['frames']);
    final lines = <StillImageOcrLine>[];
    for (final rawFrame in rawFrames) {
      final frame = _map(rawFrame);
      for (final rawLine in _list(frame['lines'])) {
        final line = _map(rawLine);
        final text = line['text']?.toString().trim() ?? '';
        if (text.isEmpty) continue;
        lines.add(
          StillImageOcrLine(
            text: text,
            left: _number(line['left']),
            top: _number(line['top']),
            width: _number(line['width']),
            height: _number(line['height']),
          ),
        );
      }
    }
    if (rawFrames.isEmpty) {
      throw const FormatException('Windows OCR returned no screenshot frame.');
    }
    return StillImageOcrResult(
      sourceWidth: _integer(raw['sourceWidth']),
      sourceHeight: _integer(raw['sourceHeight']),
      ocrLanguage: raw['ocrLanguage']?.toString() ?? '',
      lines: List<StillImageOcrLine>.unmodifiable(lines),
      diagnostics: List<String>.unmodifiable(
        _list(raw['diagnostics']).map((value) => value.toString()),
      ),
    );
  }

  static Map<Object?, Object?> _map(Object? value) =>
      value is Map ? Map<Object?, Object?>.from(value) : <Object?, Object?>{};

  static List<Object?> _list(Object? value) =>
      value is List ? List<Object?>.from(value) : const <Object?>[];

  static int _integer(Object? value) => value is num ? value.toInt() : 0;
  static double _number(Object? value) => value is num ? value.toDouble() : 0;
}
