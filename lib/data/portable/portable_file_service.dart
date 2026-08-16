import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../persistence/atomic_file_store.dart';

final class PortableFileService {
  const PortableFileService();

  Future<AtomicWriteResult> saveJson(String path, String source) async {
    final target = File(path);
    final name = target.uri.pathSegments.last;
    if (name.isEmpty) {
      throw const FileSystemException('The export path has no file name.');
    }
    final store = AtomicFileStore(directory: target.parent, fileName: name);
    return store.writeBytes(
      Uint8List.fromList(utf8.encode(source)),
      validate: (bytes) {
        final decoded = jsonDecode(utf8.decode(bytes, allowMalformed: false));
        if (decoded is! Map) {
          throw const FormatException('Portable JSON root must be an object.');
        }
      },
    );
  }

  Future<String> loadJson(String path) async {
    final source = await File(path).readAsString();
    final decoded = jsonDecode(source);
    if (decoded is! Map) {
      throw const FormatException('Portable JSON root must be an object.');
    }
    return source;
  }
}
