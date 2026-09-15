import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.length != 2) {
    stderr.writeln(
      'Usage: dart run tool/verify_fish_companion_payload.dart '
      '<payload-root> <integrity-json>',
    );
    exitCode = 64;
    return;
  }

  final payloadRoot = Directory(arguments.first).absolute;
  final integrity =
      jsonDecode(File(arguments.last).readAsStringSync())
          as Map<String, dynamic>;
  final files = <File>[];
  for (final subtree in const <String>[
    'static',
    'backend',
    'recognizer',
    'data',
  ]) {
    await for (final entity in Directory(
      _join(payloadRoot.path, subtree),
    ).list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final relative = _relative(payloadRoot, entity);
      if (_isGeneratedPythonCache(relative)) continue;
      files.add(entity);
    }
  }
  files.sort(
    (left, right) => _relative(
      payloadRoot,
      left,
    ).toLowerCase().compareTo(_relative(payloadRoot, right).toLowerCase()),
  );

  var byteCount = 0;
  final lines = <String>[];
  for (final file in files) {
    final bytes = await file.readAsBytes();
    byteCount += bytes.length;
    lines.add(
      '${_relative(payloadRoot, file)}|${bytes.length}|'
      '${sha256.convert(bytes)}',
    );
  }
  final aggregate = sha256.convert(utf8.encode(lines.join('\n'))).toString();
  final service = File(
    _join(payloadRoot.path, 'runtime', 'fish_companion_service.exe'),
  );
  final serviceBytes = await service.readAsBytes();
  final serviceHash = sha256.convert(serviceBytes).toString();

  stdout
    ..writeln('sourceFileCount=${files.length}')
    ..writeln('sourceByteCount=$byteCount')
    ..writeln('sourceAggregateSha256=$aggregate')
    ..writeln('serviceByteCount=${serviceBytes.length}')
    ..writeln('serviceSha256=$serviceHash');

  final valid =
      files.length == integrity['sourceFileCount'] &&
      byteCount == integrity['sourceByteCount'] &&
      aggregate == integrity['sourceAggregateSha256'] &&
      serviceBytes.length == integrity['serviceByteCount'] &&
      serviceHash == integrity['serviceSha256'];
  if (!valid) exitCode = 1;
}

String _relative(Directory root, File file) =>
    file.path.substring(root.path.length + 1).replaceAll('\\', '/');

bool _isGeneratedPythonCache(String relative) {
  final normalized = relative.replaceAll('\\', '/').toLowerCase();
  return normalized.endsWith('.pyc') ||
      normalized.split('/').contains('__pycache__');
}

String _join(String first, String second, [String? third]) {
  final base = first.endsWith(Platform.pathSeparator)
      ? '$first$second'
      : '$first${Platform.pathSeparator}$second';
  if (third == null) return base;
  return '$base${Platform.pathSeparator}$third';
}
