import 'package:flutter/services.dart';

final class NativeFileDialogService {
  const NativeFileDialogService();

  static const MethodChannel _channel = MethodChannel(
    'com.bdocraftplanner.flutter/window',
  );

  Future<String?> pickJsonToOpen() => _pickOpen('json');

  Future<String?> pickImageToOpen() => _pickOpen('image');

  Future<String?> pickVideoToOpen() => _pickOpen('video');

  Future<String?> pickDirectory({String? initialPath}) =>
      _invoke('pickDirectory', <String, Object?>{
        if (initialPath != null && initialPath.trim().isNotEmpty)
          'initialPath': initialPath.trim(),
      });

  Future<String?> pickJsonDestination({
    String defaultName = 'bdo-craft-planner-backup.json',
  }) => _invoke('pickSaveFile', <String, Object?>{'defaultName': defaultName});

  Future<String?> _pickOpen(String kind) =>
      _invoke('pickOpenFile', <String, Object?>{'kind': kind});

  Future<String?> _invoke(String method, Map<String, Object?> arguments) async {
    try {
      final result = await _channel.invokeMethod<String>(method, arguments);
      final path = result?.trim();
      return path == null || path.isEmpty ? null : path;
    } on MissingPluginException {
      return null;
    }
  }
}
