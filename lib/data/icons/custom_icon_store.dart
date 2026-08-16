import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';

import '../../domain/state/planner_state.dart';
import '../persistence/atomic_file_store.dart';

final class CustomIconValidationException implements Exception {
  const CustomIconValidationException(this.message);

  final String message;

  @override
  String toString() => 'CustomIconValidationException: $message';
}

enum CustomIconFit { centerCrop, contain }

/// Validates user-selected raster files, decodes the first frame, normalizes
/// it to a square, and persists a bounded app-owned PNG outside the state JSON.
final class CustomIconStore {
  CustomIconStore({
    required this.applicationDirectory,
    this.maxSourceBytes = 8 * 1024 * 1024,
    this.maxSourceDimension = 8192,
    this.outputDimension = 512,
    this.maxCachedEntries = 128,
    this.maxCachedBytes = 32 * 1024 * 1024,
  }) : assert(maxCachedEntries > 0),
       assert(maxCachedBytes > 0);

  final Directory applicationDirectory;
  final int maxSourceBytes;
  final int maxSourceDimension;
  final int outputDimension;
  final int maxCachedEntries;
  final int maxCachedBytes;

  final LinkedHashMap<String, _ValidatedIconCacheEntry> _validatedBytes =
      LinkedHashMap<String, _ValidatedIconCacheEntry>();
  final Map<String, Future<Uint8List>> _pendingReads =
      <String, Future<Uint8List>>{};
  int _cachedByteCount = 0;
  bool _disposed = false;

  Directory get iconDirectory =>
      Directory('${applicationDirectory.path}${Platform.pathSeparator}icons');

  Future<CustomIconReference> importFile(File source) async {
    final bytes = await source.readAsBytes();
    return importBytes(bytes, sourceName: source.uri.pathSegments.last);
  }

  Future<CustomIconReference> importDataUri(
    String source, {
    required String sourceName,
    CustomIconFit fit = CustomIconFit.centerCrop,
  }) async {
    final UriData data;
    try {
      data = UriData.parse(source);
    } on FormatException {
      throw const CustomIconValidationException(
        'The custom icon is not a valid data URI.',
      );
    }
    if (!data.mimeType.toLowerCase().startsWith('image/') || !data.isBase64) {
      throw const CustomIconValidationException(
        'The custom icon must be a base64 image data URI.',
      );
    }
    return importBytes(data.contentAsBytes(), sourceName: sourceName, fit: fit);
  }

  /// Copies a previously normalized app-owned icon without re-encoding it.
  ///
  /// This is used when a renamed application adopts a former profile. The
  /// source reference and bytes are fully validated first, so the content hash
  /// and reference remain stable across the copy.
  Future<CustomIconCopyResult> copyValidatedReferenceFrom({
    required CustomIconReference reference,
    required Directory sourceApplicationDirectory,
  }) async {
    final sourceStore = CustomIconStore(
      applicationDirectory: sourceApplicationDirectory,
      maxSourceBytes: maxSourceBytes,
      maxSourceDimension: maxSourceDimension,
      outputDimension: outputDimension,
      maxCachedEntries: maxCachedEntries,
      maxCachedBytes: maxCachedBytes,
    );
    try {
      final bytes = sourceStore.readValidatedBytes(reference);
      final fileName = _appOwnedFileName(reference);
      final destination = File(
        '${iconDirectory.path}${Platform.pathSeparator}$fileName',
      );
      if (await destination.exists()) {
        final existing = await destination.readAsBytes();
        final problem = _storedIconValidationProblem(
          bytes: existing,
          expectedByteCount: reference.byteCount,
          expectedDimension: outputDimension,
          declaredWidth: reference.width,
          declaredHeight: reference.height,
          expectedSha256: reference.sha256,
        );
        if (problem != null) throw CustomIconValidationException(problem);
        return CustomIconCopyResult(reference: reference, created: false);
      }
      final store = AtomicFileStore(
        directory: iconDirectory,
        fileName: fileName,
      );
      await store.writeBytes(
        Uint8List.fromList(bytes),
        validate: (candidate) async {
          final problem = _storedIconValidationProblem(
            bytes: candidate,
            expectedByteCount: reference.byteCount,
            expectedDimension: outputDimension,
            declaredWidth: reference.width,
            declaredHeight: reference.height,
            expectedSha256: reference.sha256,
          );
          if (problem != null) throw CustomIconValidationException(problem);
        },
      );
      return CustomIconCopyResult(reference: reference, created: true);
    } finally {
      sourceStore.dispose();
    }
  }

  /// Reads an app-owned normalized icon for the synchronous portable encoder.
  /// The declared metadata, normalized dimensions, and content hash are
  /// checked before any data leaves the application boundary.
  Uint8List readValidatedBytes(CustomIconReference reference) {
    final file = _validatedFile(reference);
    final Uint8List bytes;
    try {
      bytes = file.readAsBytesSync();
    } on FileSystemException catch (error) {
      throw CustomIconValidationException(
        'The app-owned custom icon could not be read: ${error.message}',
      );
    }
    final problem = _storedIconValidationProblem(
      bytes: bytes,
      expectedByteCount: reference.byteCount,
      expectedDimension: outputDimension,
      declaredWidth: reference.width,
      declaredHeight: reference.height,
      expectedSha256: reference.sha256,
    );
    if (problem != null) throw CustomIconValidationException(problem);
    return bytes;
  }

  /// Loads and validates an app-owned icon without performing file or hash
  /// work on the UI isolate.
  ///
  /// Validated bytes are cached by reference and file stamp. Each lookup still
  /// performs an asynchronous stat so a missing, replaced, or modified file
  /// cannot be hidden indefinitely by the memory cache. Concurrent reads of
  /// the same version share one validation task.
  Future<Uint8List> readValidatedBytesAsync(
    CustomIconReference reference,
  ) async {
    if (_disposed) {
      throw const CustomIconValidationException(
        'The app-owned custom icon store is no longer available.',
      );
    }
    final file = _validatedFile(reference);
    final cacheKey = _cacheKey(reference);
    final stamp = await _fileStamp(file);
    final cached = _validatedBytes.remove(cacheKey);
    if (cached != null) {
      if (cached.stamp == stamp) {
        _validatedBytes[cacheKey] = cached;
        return cached.bytes;
      }
      _cachedByteCount -= cached.bytes.length;
    }

    final pendingKey = '$cacheKey\u0000${stamp.cacheKey}';
    final pending = _pendingReads[pendingKey];
    if (pending != null) return pending;

    final read = _readAndValidate(file, reference, stamp);
    _pendingReads[pendingKey] = read;
    try {
      final bytes = await read;
      if (!_disposed) _remember(cacheKey, stamp, bytes);
      return bytes;
    } finally {
      if (identical(_pendingReads[pendingKey], read)) {
        _pendingReads.remove(pendingKey)?.ignore();
      }
    }
  }

  /// Produces the portable representation only after the same validation used
  /// by live UI consumers has succeeded.
  String exportDataUri(CustomIconReference reference) =>
      'data:image/png;base64,${base64Encode(readValidatedBytes(reference))}';

  Future<CustomIconReference> importBytes(
    Uint8List bytes, {
    required String sourceName,
    CustomIconFit fit = CustomIconFit.centerCrop,
  }) async {
    if (bytes.isEmpty) {
      throw const CustomIconValidationException('The selected file is empty.');
    }
    if (bytes.length > maxSourceBytes) {
      throw CustomIconValidationException(
        'The selected image exceeds the $maxSourceBytes byte limit.',
      );
    }
    if (!_hasSupportedSignature(bytes)) {
      throw CustomIconValidationException(
        '$sourceName is not a supported PNG, JPEG, WebP, or GIF image.',
      );
    }

    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    ui.ImageDescriptor? descriptor;
    ui.Codec? codec;
    ui.Image? decoded;
    ui.Image? normalized;
    try {
      try {
        descriptor = await ui.ImageDescriptor.encoded(buffer);
      } on Object catch (error) {
        throw CustomIconValidationException(
          'The selected image could not be decoded: $error',
        );
      }
      if (descriptor.width < 1 || descriptor.height < 1) {
        throw const CustomIconValidationException(
          'The selected image has invalid dimensions.',
        );
      }
      if (descriptor.width > maxSourceDimension ||
          descriptor.height > maxSourceDimension) {
        throw CustomIconValidationException(
          'The selected image exceeds ${maxSourceDimension}x$maxSourceDimension pixels.',
        );
      }
      codec = await descriptor.instantiateCodec();
      decoded = (await codec.getNextFrame()).image;
      normalized = switch (fit) {
        CustomIconFit.centerCrop => await _centerCrop(decoded, outputDimension),
        CustomIconFit.contain => await _contain(decoded, outputDimension),
      };
      final byteData = await normalized.toByteData(
        format: ui.ImageByteFormat.png,
      );
      if (byteData == null) {
        throw const CustomIconValidationException(
          'The normalized PNG could not be encoded.',
        );
      }
      final png = byteData.buffer.asUint8List(
        byteData.offsetInBytes,
        byteData.lengthInBytes,
      );
      final hash = sha256.convert(png).toString().toUpperCase();
      final fileName = '${hash.toLowerCase()}.png';
      final store = AtomicFileStore(
        directory: iconDirectory,
        fileName: fileName,
      );
      await store.writeBytes(
        Uint8List.fromList(png),
        validate: _validateNormalizedPng,
      );
      return CustomIconReference(
        relativePath: 'icons/$fileName',
        sha256: hash,
        mediaType: 'image/png',
        byteCount: png.length,
        width: outputDimension,
        height: outputDimension,
      );
    } finally {
      normalized?.dispose();
      decoded?.dispose();
      codec?.dispose();
      descriptor?.dispose();
      buffer.dispose();
    }
  }

  Future<void> remove(CustomIconReference reference) async {
    final fileName = _appOwnedFileName(reference);
    _forget(_cacheKey(reference));
    final file = File(
      '${iconDirectory.path}${Platform.pathSeparator}$fileName',
    );
    if (await file.exists()) await file.delete();
  }

  /// Releases validated image bytes retained by this store instance.
  void clearMemoryCache() {
    _validatedBytes.clear();
    _cachedByteCount = 0;
  }

  /// Releases the instance-owned cache. In-flight reads may finish, but their
  /// results will not be retained.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    clearMemoryCache();
  }

  File _validatedFile(CustomIconReference reference) {
    final fileName = _appOwnedFileName(reference);
    if (reference.mediaType.toLowerCase() != 'image/png' ||
        reference.byteCount < 1) {
      throw const CustomIconValidationException(
        'The app-owned custom icon has invalid stored metadata.',
      );
    }
    return File('${iconDirectory.path}${Platform.pathSeparator}$fileName');
  }

  Future<_StoredFileStamp> _fileStamp(File file) async {
    final FileStat stat;
    try {
      stat = await file.stat();
    } on FileSystemException catch (error) {
      throw CustomIconValidationException(
        'The app-owned custom icon could not be read: ${error.message}',
      );
    }
    if (stat.type != FileSystemEntityType.file) {
      throw const CustomIconValidationException(
        'The app-owned custom icon could not be read: the file is missing.',
      );
    }
    return _StoredFileStamp(
      size: stat.size,
      modifiedMicros: stat.modified.microsecondsSinceEpoch,
      changedMicros: stat.changed.microsecondsSinceEpoch,
    );
  }

  Future<Uint8List> _readAndValidate(
    File file,
    CustomIconReference reference,
    _StoredFileStamp expectedStamp,
  ) async {
    final Uint8List bytes;
    try {
      bytes = await file.readAsBytes();
    } on FileSystemException catch (error) {
      throw CustomIconValidationException(
        'The app-owned custom icon could not be read: ${error.message}',
      );
    }
    final expectedByteCount = reference.byteCount;
    final expectedDimension = outputDimension;
    final declaredWidth = reference.width;
    final declaredHeight = reference.height;
    final expectedSha256 = reference.sha256;
    final problem = await Isolate.run(
      () => _storedIconValidationProblem(
        bytes: bytes,
        expectedByteCount: expectedByteCount,
        expectedDimension: expectedDimension,
        declaredWidth: declaredWidth,
        declaredHeight: declaredHeight,
        expectedSha256: expectedSha256,
      ),
    );
    if (problem != null) throw CustomIconValidationException(problem);
    final finalStamp = await _fileStamp(file);
    if (finalStamp != expectedStamp) {
      throw const CustomIconValidationException(
        'The app-owned custom icon changed while it was being read.',
      );
    }
    return bytes;
  }

  String _cacheKey(CustomIconReference reference) =>
      '${reference.relativePath}\u0000${reference.sha256.toUpperCase()}'
      '\u0000${reference.mediaType.toLowerCase()}\u0000${reference.byteCount}'
      '\u0000${reference.width ?? ''}\u0000${reference.height ?? ''}'
      '\u0000$outputDimension';

  void _remember(String key, _StoredFileStamp stamp, Uint8List bytes) {
    _forget(key);
    if (bytes.length > maxCachedBytes) return;
    _validatedBytes[key] = _ValidatedIconCacheEntry(stamp, bytes);
    _cachedByteCount += bytes.length;
    while (_validatedBytes.length > maxCachedEntries ||
        _cachedByteCount > maxCachedBytes) {
      _forget(_validatedBytes.keys.first);
    }
  }

  void _forget(String key) {
    final removed = _validatedBytes.remove(key);
    if (removed != null) _cachedByteCount -= removed.bytes.length;
  }

  Future<void> _validateNormalizedPng(Uint8List bytes) async {
    if (!_isPng(bytes)) {
      throw const CustomIconValidationException(
        'The staged custom icon is not a PNG.',
      );
    }
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    ui.ImageDescriptor? descriptor;
    try {
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      if (descriptor.width != outputDimension ||
          descriptor.height != outputDimension) {
        throw const CustomIconValidationException(
          'The staged custom icon dimensions are invalid.',
        );
      }
    } finally {
      descriptor?.dispose();
      buffer.dispose();
    }
  }
}

final class CustomIconCopyResult {
  const CustomIconCopyResult({required this.reference, required this.created});

  final CustomIconReference reference;
  final bool created;
}

final class _StoredFileStamp {
  const _StoredFileStamp({
    required this.size,
    required this.modifiedMicros,
    required this.changedMicros,
  });

  final int size;
  final int modifiedMicros;
  final int changedMicros;

  String get cacheKey => '$size:$modifiedMicros:$changedMicros';

  @override
  bool operator ==(Object other) =>
      other is _StoredFileStamp &&
      other.size == size &&
      other.modifiedMicros == modifiedMicros &&
      other.changedMicros == changedMicros;

  @override
  int get hashCode => Object.hash(size, modifiedMicros, changedMicros);
}

final class _ValidatedIconCacheEntry {
  const _ValidatedIconCacheEntry(this.stamp, this.bytes);

  final _StoredFileStamp stamp;
  final Uint8List bytes;
}

Future<ui.Image> _centerCrop(ui.Image source, int dimension) async {
  final side = source.width < source.height ? source.width : source.height;
  final left = (source.width - side) / 2;
  final top = (source.height - side) / 2;
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawImageRect(
    source,
    ui.Rect.fromLTWH(left, top, side.toDouble(), side.toDouble()),
    ui.Rect.fromLTWH(0, 0, dimension.toDouble(), dimension.toDouble()),
    ui.Paint()..filterQuality = ui.FilterQuality.high,
  );
  final picture = recorder.endRecording();
  try {
    return await picture.toImage(dimension, dimension);
  } finally {
    picture.dispose();
  }
}

Future<ui.Image> _contain(ui.Image source, int dimension) async {
  final scale = source.width > source.height
      ? dimension / source.width
      : dimension / source.height;
  final width = source.width * scale;
  final height = source.height * scale;
  final left = (dimension - width) / 2;
  final top = (dimension - height) / 2;
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawImageRect(
    source,
    ui.Rect.fromLTWH(0, 0, source.width.toDouble(), source.height.toDouble()),
    ui.Rect.fromLTWH(left, top, width, height),
    ui.Paint()..filterQuality = ui.FilterQuality.high,
  );
  final picture = recorder.endRecording();
  try {
    return await picture.toImage(dimension, dimension);
  } finally {
    picture.dispose();
  }
}

bool _hasSupportedSignature(Uint8List bytes) =>
    _isPng(bytes) || _isJpeg(bytes) || _isWebp(bytes) || _isGif(bytes);

bool _isPng(Uint8List bytes) =>
    bytes.length >= 8 &&
    bytes[0] == 0x89 &&
    bytes[1] == 0x50 &&
    bytes[2] == 0x4e &&
    bytes[3] == 0x47 &&
    bytes[4] == 0x0d &&
    bytes[5] == 0x0a &&
    bytes[6] == 0x1a &&
    bytes[7] == 0x0a;

String? _storedIconValidationProblem({
  required Uint8List bytes,
  required int expectedByteCount,
  required int expectedDimension,
  required int? declaredWidth,
  required int? declaredHeight,
  required String expectedSha256,
}) {
  if (!_isPng(bytes) || bytes.length != expectedByteCount) {
    return 'The app-owned custom icon does not match its stored metadata.';
  }
  final dimensions = _pngDimensions(bytes);
  if (dimensions == null ||
      dimensions.width != expectedDimension ||
      dimensions.height != expectedDimension ||
      (declaredWidth != null && declaredWidth != dimensions.width) ||
      (declaredHeight != null && declaredHeight != dimensions.height)) {
    return 'The app-owned custom icon dimensions do not match its stored metadata.';
  }
  final hash = sha256.convert(bytes).toString().toUpperCase();
  if (hash != expectedSha256.toUpperCase()) {
    return 'The app-owned custom icon failed its content-hash check.';
  }
  return null;
}

final RegExp _sha256Pattern = RegExp(r'^[0-9a-fA-F]{64}$');

String _appOwnedFileName(CustomIconReference reference) {
  if (!_sha256Pattern.hasMatch(reference.sha256)) {
    throw const CustomIconValidationException(
      'The icon reference does not contain a valid SHA-256 hash.',
    );
  }
  final fileName = '${reference.sha256.toLowerCase()}.png';
  final normalized = reference.relativePath.replaceAll('\\', '/');
  if (normalized != 'icons/$fileName') {
    throw const CustomIconValidationException(
      'The icon reference is not an app-owned normalized path.',
    );
  }
  return fileName;
}

({int width, int height})? _pngDimensions(Uint8List bytes) {
  if (bytes.length < 24 ||
      String.fromCharCodes(bytes.sublist(12, 16)) != 'IHDR') {
    return null;
  }
  int readUint32(int offset) =>
      (bytes[offset] << 24) |
      (bytes[offset + 1] << 16) |
      (bytes[offset + 2] << 8) |
      bytes[offset + 3];
  final width = readUint32(16);
  final height = readUint32(20);
  if (width < 1 || height < 1) return null;
  return (width: width, height: height);
}

bool _isJpeg(Uint8List bytes) =>
    bytes.length >= 3 &&
    bytes[0] == 0xff &&
    bytes[1] == 0xd8 &&
    bytes[2] == 0xff;

bool _isWebp(Uint8List bytes) =>
    bytes.length >= 12 &&
    String.fromCharCodes(bytes.sublist(0, 4)) == 'RIFF' &&
    String.fromCharCodes(bytes.sublist(8, 12)) == 'WEBP';

bool _isGif(Uint8List bytes) {
  if (bytes.length < 6) return false;
  final signature = String.fromCharCodes(bytes.sublist(0, 6));
  return signature == 'GIF87a' || signature == 'GIF89a';
}
