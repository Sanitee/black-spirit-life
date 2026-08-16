import 'package:flutter/services.dart';

/// Reads a Windows clipboard bitmap as encoded PNG bytes.
///
/// The native runner accepts both applications that publish PNG directly and
/// applications (including screenshot tools) that only publish a Windows DIB
/// or bitmap. Unsupported platforms and a clipboard without an image are
/// represented by `null`, so callers can keep a normal file-picker fallback.
final class NativeClipboardImageReader {
  const NativeClipboardImageReader({this.maximumBytes = defaultMaximumBytes})
    : assert(maximumBytes > 0);

  static const int defaultMaximumBytes = 40 * 1024 * 1024;

  static const MethodChannel _channel = MethodChannel(
    'com.bdocraftplanner.flutter/window',
  );

  final int maximumBytes;

  /// Allows an instance to be passed directly where a screenshot callback is
  /// expected.
  Future<Uint8List?> call() => readPng();

  Future<Uint8List?> readPng() async {
    try {
      final bytes = await _channel.invokeMethod<Uint8List>(
        'readClipboardImagePng',
      );
      if (bytes == null || bytes.isEmpty) return null;
      if (bytes.lengthInBytes > maximumBytes) {
        throw const FormatException(
          'That screenshot is larger than 40 MB. Crop it to the relevant '
          'window or area and try again.',
        );
      }
      return bytes;
    } on MissingPluginException {
      return null;
    }
  }
}
