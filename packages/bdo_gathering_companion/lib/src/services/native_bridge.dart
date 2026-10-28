import 'package:flutter/services.dart';
import '../ui/visual_palette.dart';

/// Explicit, user-triggered desktop actions. Never captures the game itself.
abstract final class NativeBridge {
  static const _channel = MethodChannel('bdo_gathering/native');
  static const maximumScreenshotBytes = 16 * 1024 * 1024;
  static bool _sessionImportMayBeRunning = false;

  static Future<Uint8List?> readClipboardImage() async {
    final bytes = await _channel.invokeMethod<Uint8List>('readClipboardImage');
    if (bytes != null && bytes.length > maximumScreenshotBytes) {
      throw const FormatException('Choose a screenshot smaller than 16 MB.');
    }
    return bytes;
  }

  static Future<String?> pickImage() =>
      _channel.invokeMethod<String>('pickImage');

  static Future<bool> openExternal(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null ||
        !const {'https', 'http'}.contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      return false;
    }
    return await _channel.invokeMethod<bool>('openExternal', {'url': url}) ??
        false;
  }

  static Future<bool> openReferenceWindow({
    required int glassOpacityPercent,
    CompanionVisualPalette? visualPalette,
  }) async =>
      await _channel.invokeMethod<bool>('openReferenceWindow', {
        'glassOpacityPercent': glassOpacityPercent.clamp(0, 100),
        if (visualPalette != null) 'visualPalette': visualPalette.encode(),
      }) ??
      false;

  static Future<bool> openSessionImport({
    required String receiptDirectory,
  }) async {
    final opened =
        await _channel.invokeMethod<bool>('openSessionImport', {
          'receiptDirectory': receiptDirectory,
        }) ??
        false;
    if (opened) _sessionImportMayBeRunning = true;
    return opened;
  }

  /// Requests graceful shutdown of the app-owned Session Import helper.
  static Future<void> shutdownSessionImport() async {
    try {
      final stopped =
          await _channel.invokeMethod<bool>('shutdownSessionImport') ?? false;
      if (!stopped) {
        throw StateError(
          'The Session Import helper did not confirm a safe shutdown.',
        );
      }
      _sessionImportMayBeRunning = false;
    } on MissingPluginException {
      if (!_sessionImportMayBeRunning) return;
      throw StateError(
        'The Session Import helper may still be running because this host '
        'does not support safe shutdown.',
      );
    }
  }

  static Future<bool> setAlwaysOnTop(bool enabled) async =>
      await _channel.invokeMethod<bool>('setAlwaysOnTop', {
        'enabled': enabled,
      }) ??
      false;
}
