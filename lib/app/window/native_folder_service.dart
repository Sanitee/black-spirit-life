import 'dart:io';

/// Opens an existing local profile folder. Never creates or relocates data.
final class NativeFolderService {
  const NativeFolderService({
    this.isWindows,
    this.windowsDirectory,
    this.directoryExists,
    this.launch,
  });

  final bool? isWindows;
  final String? windowsDirectory;
  final Future<bool> Function(String path)? directoryExists;
  final Future<void> Function(String executable, List<String> arguments)?
  launch;

  Future<void> open(String folderPath) async {
    if (!(isWindows ?? Platform.isWindows)) {
      throw UnsupportedError('Opening the data folder requires Windows.');
    }
    final folder = folderPath.trim();
    final absolute = RegExp(
      r'^(?:[A-Za-z]:[\\/]|\\\\[^\\]+\\[^\\]+)',
    ).hasMatch(folder);
    if (!absolute ||
        RegExp('[\\x00-\\x1f"]').hasMatch(folder) ||
        folder.contains('"')) {
      throw const FormatException('The personal data folder path is invalid.');
    }
    final exists =
        await (directoryExists?.call(folder) ?? Directory(folder).exists());
    if (!exists) {
      throw FileSystemException(
        'The personal data folder is unavailable.',
        folder,
      );
    }
    final systemRoot =
        windowsDirectory ?? Platform.environment['SystemRoot'] ?? r'C:\Windows';
    final executable = '$systemRoot\\explorer.exe';
    final launcher = launch;
    if (launcher != null) {
      await launcher(executable, [folder]);
    } else {
      // Separate arguments, no shell or interpolated command. Do not wait for
      // Explorer to exit: it can remain open for the rest of the user's session.
      await Process.start(
        executable,
        [folder],
        runInShell: false,
        mode: ProcessStartMode.detached,
      );
    }
  }
}
