import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:image/image.dart' as image;

import '../../domain/models/catalog_models.dart';
import '../../features/inventory/inventory_screenshot_recognition.dart';

const int _maximumScreenshotBytes = 16 * 1024 * 1024;
const int _maximumResponseBytes = 8 * 1024 * 1024;
const int _maximumErrorBytes = 4096;
const int _maximumTemplateCacheIndexBytes = 2 * 1024 * 1024;
const int _maximumTemplateCacheRgbBytes = 64 * 1024 * 1024;

final class _InventoryOcrArtworkConfiguration {
  const _InventoryOcrArtworkConfiguration({
    this.nativeArtworkBytes = const <String, Uint8List>{},
    this.preprocessedIndexJson,
    this.preprocessedRgbBytes,
  });

  final Map<String, Uint8List> nativeArtworkBytes;
  final String? preprocessedIndexJson;
  final Uint8List? preprocessedRgbBytes;

  bool get isEmpty =>
      nativeArtworkBytes.isEmpty &&
      preprocessedIndexJson == null &&
      preprocessedRgbBytes == null;
}

/// Runs the shared Black Spirit storage recognizer in its isolated native
/// process. The old Windows OCR path is intentionally not used as a fallback.
final class NativeInventoryOcrService {
  NativeInventoryOcrService({
    this.timeout = const Duration(seconds: 95),
    String? helperPath,
    this.timingObserver,
    this.usePreprocessedArtworkCache = true,
  }) : _helperPathOverride = helperPath;

  final Duration timeout;
  final void Function(String stage, Duration elapsed)? timingObserver;
  @visibleForTesting
  final bool usePreprocessedArtworkCache;
  final String? _helperPathOverride;

  bool _operationActive = false;
  bool _disposed = false;
  int _operationEpoch = 0;
  _NativeInventoryOcrWorker? _nativeWorker;
  Future<_NativeInventoryOcrWorker>? _nativeWorkerStarting;
  int _nativeWorkerGeneration = 0;
  bool _nativeActive = false;
  Timer? _nativeIdleTimer;
  String? _cachedCatalogKey;
  InventoryOcrMaterialCatalog? _cachedCatalog;
  String? _cachedArtworkKey;
  Map<String, Uint8List>? _cachedArtworkBytes;
  _InventoryScreenshotPostProcessWorkerPool? _postProcessWorker;
  Future<_InventoryScreenshotPostProcessWorkerPool>? _postProcessWorkerStarting;
  int _postProcessWorkerGeneration = 0;
  bool _postProcessActive = false;
  Timer? _postProcessIdleTimer;
  Future<void>? _prewarmFuture;

  Future<InventoryScreenshotAnalysis> scanPath(
    String path, {
    required CatalogSnapshot catalog,
  }) async {
    final normalized = path.trim();
    if (normalized.isEmpty) {
      throw const FormatException('Choose a storage screenshot first.');
    }
    final file = File(normalized);
    final stat = await file.stat();
    if (stat.type != FileSystemEntityType.file) {
      throw const FormatException(
        'The selected screenshot could not be found.',
      );
    }
    if (stat.size <= 0 || stat.size > _maximumScreenshotBytes) {
      throw const FormatException(
        'Choose a PNG, JPEG, or BMP screenshot smaller than 16 MB.',
      );
    }
    final fileName = _safeBaseName(file.path);
    final mimeType = _mimeTypeForFileName(fileName);
    final bytes = await file.readAsBytes();
    return _scan(
      bytes,
      fileName: fileName,
      mimeType: mimeType,
      catalog: catalog,
    );
  }

  Future<InventoryScreenshotAnalysis> scanPngBytes(
    Uint8List bytes, {
    required CatalogSnapshot catalog,
  }) => _scan(
    bytes,
    fileName: 'storage-screenshot.png',
    mimeType: 'image/png',
    catalog: catalog,
  );

  /// Initializes immutable OCR assets while Inventory is already open.
  /// Recognition later reuses these exact workers, pixels, and model state.
  Future<void> prewarm({required CatalogSnapshot catalog}) {
    if (_disposed) return Future<void>.value();
    final existing = _prewarmFuture;
    if (existing != null) return existing;
    late final Future<void> future;
    future = _prewarm(catalog).whenComplete(() {
      if (identical(_prewarmFuture, future)) _prewarmFuture = null;
    });
    _prewarmFuture = future;
    return future;
  }

  Future<void> _prewarm(CatalogSnapshot catalog) async {
    final helper = await _resolveHelper();
    if (_disposed) return;
    final nativeWorkerFuture = _nativeWorkerFor(helper);
    final materialCatalog = await _loadMaterialCatalog(helper, catalog);
    final configurationKey =
        '${_cachedCatalogKey ?? catalog.sourceSha256}:${helper.path}';
    final artworkFuture =
        _postProcessWorker?.isConfiguredFor(configurationKey) == true
        ? Future<_InventoryOcrArtworkConfiguration>.value(
            const _InventoryOcrArtworkConfiguration(),
          )
        : _loadArtworkConfiguration(helper, materialCatalog);
    final postProcessWorkerFuture = _postProcessWorkerForCurrentConfiguration();
    final nativeWorker = await nativeWorkerFuture;
    final nativeWarm = nativeWorker.warm().timeout(timeout);
    final artwork = await artworkFuture;
    final postProcessWorker = await postProcessWorkerFuture;
    await Future.wait<void>(<Future<void>>[
      nativeWarm,
      postProcessWorker
          .prewarm(
            configurationKey: configurationKey,
            catalog: materialCatalog,
            artworkConfiguration: artwork,
          )
          .timeout(timeout),
    ]);
    if (_disposed) return;
    _scheduleNativeWorkerRelease();
    _schedulePostProcessWorkerRelease();
  }

  Future<InventoryScreenshotAnalysis> _scan(
    Uint8List bytes, {
    required String fileName,
    required String mimeType,
    required CatalogSnapshot catalog,
  }) async {
    final totalStopwatch = Stopwatch()..start();
    if (_disposed) {
      throw const FormatException('Storage screenshot recognition is closed.');
    }
    if (_operationActive) {
      throw const FormatException(
        'A storage screenshot is already being recognized.',
      );
    }
    _operationActive = true;
    _nativeIdleTimer?.cancel();
    _nativeIdleTimer = null;
    _postProcessIdleTimer?.cancel();
    _postProcessIdleTimer = null;
    final epoch = ++_operationEpoch;
    try {
      final prewarm = _prewarmFuture;
      if (prewarm != null) {
        try {
          await prewarm;
        } on Object {
          // Warm-up is speculative. A real scan retries through the guarded
          // initialization path below if it was interrupted or unavailable.
        }
        _ensureOperationCurrent(epoch);
      }
      _validateImage(bytes, fileName: fileName, mimeType: mimeType);
      final helper = await _resolveHelper();
      _ensureOperationCurrent(epoch);
      final nativeWorkerFuture = _nativeWorkerFor(helper);
      final catalogStopwatch = Stopwatch()..start();
      final materialCatalog = await _loadMaterialCatalog(helper, catalog);
      _reportTiming('catalog', catalogStopwatch);
      final postProcessConfigurationKey =
          '${_cachedCatalogKey ?? catalog.sourceSha256}:${helper.path}';
      // The complete eligible native gallery is small enough to cache. Warm it
      // while the isolated recognizer processes the screenshot so the more
      // accurate source-resolution pass does not add its disk-I/O cost to the
      // end of every scan.
      final artworkStopwatch = Stopwatch()..start();
      final artworkConfigurationFuture =
          _postProcessWorker?.isConfiguredFor(postProcessConfigurationKey) ==
              true
          ? Future<_InventoryOcrArtworkConfiguration>.value(
              const _InventoryOcrArtworkConfiguration(),
            )
          : _loadArtworkConfiguration(helper, materialCatalog);
      _ensureOperationCurrent(epoch);
      final nativeStopwatch = Stopwatch()..start();
      final nativeWorker = await nativeWorkerFuture;
      _ensureOperationCurrent(epoch);
      _nativeActive = true;
      late final String stdoutText;
      try {
        stdoutText = await nativeWorker
            .recognize(
              jsonEncode(<String, Object>{
                'fileName': fileName,
                'mimeType': mimeType,
                'dataBase64': base64Encode(bytes),
              }),
            )
            .timeout(timeout);
      } on TimeoutException {
        _discardNativeWorker(
          TimeoutException('Storage screenshot recognition timed out.'),
        );
        rethrow;
      } finally {
        _nativeActive = false;
      }
      _reportTiming('native', nativeStopwatch);
      _ensureOperationCurrent(epoch);
      if (stdoutText.trim().isEmpty) {
        throw const FormatException(
          'Storage screenshot recognition returned an invalid response.',
        );
      }
      var artworkConfiguration = await artworkConfigurationFuture;
      _reportTiming('artwork', artworkStopwatch);
      _ensureOperationCurrent(epoch);
      // Source-resolution matching deliberately compares every admitted game
      // icon when the helper's small atlas is uncertain. Keep that CPU work
      // away from Flutter's UI isolate so the progress indicator, title bar,
      // and window remain responsive throughout recognition.
      _postProcessActive = true;
      final postProcessStopwatch = Stopwatch()..start();
      late final InventoryScreenshotDraft draft;
      try {
        final worker = await _postProcessWorkerForCurrentConfiguration();
        if (!worker.isConfiguredFor(postProcessConfigurationKey) &&
            artworkConfiguration.isEmpty &&
            materialCatalog.nativeArtworkPaths.isNotEmpty) {
          artworkConfiguration = await _loadArtworkConfiguration(
            helper,
            materialCatalog,
          );
          _ensureOperationCurrent(epoch);
        }
        draft = await worker
            .sanitize(
              configurationKey: postProcessConfigurationKey,
              rawResultJson: stdoutText,
              screenshotBytes: bytes,
              catalog: materialCatalog,
              artworkConfiguration: artworkConfiguration,
            )
            .timeout(timeout);
      } on TimeoutException {
        _discardPostProcessWorker(
          TimeoutException('Storage screenshot post-processing timed out.'),
        );
        rethrow;
      } on Object {
        _ensureOperationCurrent(epoch);
        rethrow;
      } finally {
        _postProcessActive = false;
        _reportTiming('postprocess', postProcessStopwatch);
      }
      _ensureOperationCurrent(epoch);
      if (_postProcessWorker?.isConfiguredFor(postProcessConfigurationKey) ==
          true) {
        // The worker now owns the only warm copy that matters. Avoid keeping
        // a second compressed gallery in Flutter's UI isolate.
        _cachedArtworkKey = null;
        _cachedArtworkBytes = null;
      }
      final analysis = InventoryScreenshotAnalysis(
        fileName: fileName,
        mimeType: mimeType,
        sourceByteCount: bytes.length,
        screenshotBytes: Uint8List.fromList(bytes),
        plannerItemNames: materialCatalog.names,
        plannerItemIds: materialCatalog.itemIds,
        plannerItemOrderGroups: materialCatalog.itemOrderGroups,
        draft: draft,
      );
      return analysis;
    } on TimeoutException {
      throw TimeoutException(
        'Storage screenshot recognition took too long. Try a smaller screenshot.',
      );
    } on ProcessException catch (error) {
      throw FormatException(
        'The storage recognizer could not start: ${error.message}',
      );
    } finally {
      _reportTiming('total', totalStopwatch);
      _operationActive = false;
      final survivingNativeWorker = _nativeWorker;
      if (!_disposed &&
          survivingNativeWorker != null &&
          !survivingNativeWorker.isClosed) {
        _scheduleNativeWorkerRelease();
      }
      final survivingWorker = _postProcessWorker;
      if (!_disposed && survivingWorker != null && !survivingWorker.isClosed) {
        _schedulePostProcessWorkerRelease();
      }
    }
  }

  void _reportTiming(String stage, Stopwatch stopwatch) {
    stopwatch.stop();
    try {
      timingObserver?.call(stage, stopwatch.elapsed);
    } on Object {
      // Diagnostics must never affect recognition.
    }
  }

  void cancelCurrent() {
    _operationEpoch += 1;
    if (_nativeActive) {
      _discardNativeWorker(
        const FormatException('Storage screenshot recognition was cancelled.'),
      );
    }
    if (_postProcessActive) {
      _discardPostProcessWorker(
        const FormatException('Storage screenshot recognition was cancelled.'),
      );
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    cancelCurrent();
    _nativeIdleTimer?.cancel();
    _discardNativeWorker(
      const FormatException('Storage screenshot recognition is closed.'),
    );
    _postProcessIdleTimer?.cancel();
    _discardPostProcessWorker(
      const FormatException('Storage screenshot recognition is closed.'),
    );
  }

  void _ensureOperationCurrent(int epoch) {
    if (_disposed || epoch != _operationEpoch) {
      throw const FormatException(
        'Storage screenshot recognition was cancelled.',
      );
    }
  }

  Future<File> _resolveHelper() async {
    final explicit = _helperPathOverride?.trim().isNotEmpty == true
        ? _helperPathOverride!.trim()
        : Platform.environment['BSL_STORAGE_OCR_HELPER']?.trim();
    final candidates = <String>[
      if (explicit != null && explicit.isNotEmpty) explicit,
      '${File(Platform.resolvedExecutable).parent.path}'
          '${Platform.pathSeparator}storage_ocr'
          '${Platform.pathSeparator}BlackSpiritStorageOcr.exe',
      '${Directory.current.path}'
          '${Platform.pathSeparator}build'
          '${Platform.pathSeparator}windows'
          '${Platform.pathSeparator}x64'
          '${Platform.pathSeparator}storage_ocr'
          '${Platform.pathSeparator}BlackSpiritStorageOcr.exe',
    ];
    for (final candidate in candidates) {
      final file = File(candidate);
      if (await file.exists()) return file;
    }
    throw const FormatException(
      'The storage recognizer is missing from this build. Reinstall or rebuild the Beta.',
    );
  }

  Future<InventoryOcrMaterialCatalog> _loadMaterialCatalog(
    File helper,
    CatalogSnapshot catalog,
  ) async {
    final recipeBook = File(
      '${helper.parent.path}${Platform.pathSeparator}Assets'
      '${Platform.pathSeparator}RecipeBook'
      '${Platform.pathSeparator}recipes.json',
    );
    final iconIndex = File(
      '${recipeBook.parent.path}${Platform.pathSeparator}ocr'
      '${Platform.pathSeparator}icon-index.json',
    );
    final stat = await recipeBook.stat();
    final iconIndexStat = await iconIndex.stat();
    if (stat.type != FileSystemEntityType.file ||
        stat.size <= 0 ||
        iconIndexStat.type != FileSystemEntityType.file ||
        iconIndexStat.size <= 0) {
      throw const FormatException(
        'The storage recognizer item catalog is missing from this build.',
      );
    }
    final cacheKey =
        '${catalog.sourceSha256}:${recipeBook.path}:${stat.size}'
        ':${stat.modified.millisecondsSinceEpoch}'
        ':${iconIndexStat.size}:${iconIndexStat.modified.millisecondsSinceEpoch}';
    if (_cachedCatalogKey == cacheKey && _cachedCatalog != null) {
      return _cachedCatalog!;
    }
    final parsed = InventoryOcrMaterialCatalog.fromRecipeBookJson(
      catalog: catalog,
      recipeBookJson: await recipeBook.readAsString(),
      recipeBookIconIndexJson: await iconIndex.readAsString(),
    );
    _cachedCatalogKey = cacheKey;
    _cachedCatalog = parsed;
    return parsed;
  }

  Future<Map<String, Uint8List>> _loadCatalogArtworkBytes(
    File helper,
    InventoryOcrMaterialCatalog catalog,
  ) async {
    final key = '${identityHashCode(catalog)}:${helper.path}';
    if (_cachedArtworkKey == key && _cachedArtworkBytes != null) {
      return _cachedArtworkBytes!;
    }
    final loaded = await loadNativeInventoryArtworkGalleryForTesting(
      helper: helper,
      eligibleArtworkPaths: catalog.nativeArtworkPaths,
    );
    _cachedArtworkKey = key;
    _cachedArtworkBytes = loaded;
    return loaded;
  }

  Future<_InventoryOcrArtworkConfiguration> _loadArtworkConfiguration(
    File helper,
    InventoryOcrMaterialCatalog catalog,
  ) async {
    final cacheDirectory = Directory(
      '${helper.parent.path}${Platform.pathSeparator}Assets'
      '${Platform.pathSeparator}RecipeBook${Platform.pathSeparator}AppMatcher',
    );
    final indexFile = File(
      '${cacheDirectory.path}${Platform.pathSeparator}'
      'inventory-ocr-templates.json',
    );
    final rgbFile = File(
      '${cacheDirectory.path}${Platform.pathSeparator}'
      'inventory-ocr-templates.rgb',
    );
    final stats = await Future.wait<FileStat>(<Future<FileStat>>[
      indexFile.stat(),
      rgbFile.stat(),
    ]);
    if (usePreprocessedArtworkCache &&
        stats[0].type == FileSystemEntityType.file &&
        stats[0].size > 0 &&
        stats[0].size <= _maximumTemplateCacheIndexBytes &&
        stats[1].type == FileSystemEntityType.file &&
        stats[1].size > 0 &&
        stats[1].size <= _maximumTemplateCacheRgbBytes) {
      final contents = await Future.wait<Object>(<Future<Object>>[
        indexFile.readAsString(),
        rgbFile.readAsBytes(),
      ]);
      return _InventoryOcrArtworkConfiguration(
        preprocessedIndexJson: contents[0] as String,
        preprocessedRgbBytes: contents[1] as Uint8List,
      );
    }
    return _InventoryOcrArtworkConfiguration(
      nativeArtworkBytes: await _loadCatalogArtworkBytes(helper, catalog),
    );
  }

  Future<_NativeInventoryOcrWorker> _nativeWorkerFor(File helper) async {
    final existing = _nativeWorker;
    if (existing != null && !existing.isClosed && existing.isFor(helper.path)) {
      return existing;
    }
    if (existing != null) {
      _discardNativeWorker(
        const FormatException('Storage screenshot recognizer changed.'),
      );
    }
    final starting = _nativeWorkerStarting;
    if (starting != null) return starting;

    final generation = _nativeWorkerGeneration;
    final future = _NativeInventoryOcrWorker.start(helper);
    _nativeWorkerStarting = future;
    try {
      final worker = await future;
      if (_disposed || generation != _nativeWorkerGeneration) {
        worker.dispose(
          const FormatException(
            'Storage screenshot recognition was cancelled.',
          ),
        );
        throw const FormatException(
          'Storage screenshot recognition was cancelled.',
        );
      }
      _nativeWorker = worker;
      return worker;
    } finally {
      if (identical(_nativeWorkerStarting, future)) {
        _nativeWorkerStarting = null;
      }
    }
  }

  void _discardNativeWorker(Object error) {
    _nativeWorkerGeneration += 1;
    _nativeIdleTimer?.cancel();
    _nativeIdleTimer = null;
    final worker = _nativeWorker;
    _nativeWorker = null;
    _nativeWorkerStarting = null;
    worker?.dispose(error);
  }

  void _scheduleNativeWorkerRelease() {
    _nativeIdleTimer?.cancel();
    _nativeIdleTimer = Timer(const Duration(hours: 1), () {
      if (_nativeActive || _disposed) return;
      _discardNativeWorker(
        const FormatException('Storage screenshot recognizer cache expired.'),
      );
    });
  }

  Future<_InventoryScreenshotPostProcessWorkerPool>
  _postProcessWorkerForCurrentConfiguration() async {
    final existing = _postProcessWorker;
    if (existing != null && !existing.isClosed) return existing;
    final starting = _postProcessWorkerStarting;
    if (starting != null) return starting;

    final generation = _postProcessWorkerGeneration;
    final future = _InventoryScreenshotPostProcessWorkerPool.start();
    _postProcessWorkerStarting = future;
    try {
      final worker = await future;
      if (_disposed || generation != _postProcessWorkerGeneration) {
        worker.dispose(
          const FormatException(
            'Storage screenshot recognition was cancelled.',
          ),
        );
        throw const FormatException(
          'Storage screenshot recognition was cancelled.',
        );
      }
      _postProcessWorker = worker;
      return worker;
    } finally {
      if (identical(_postProcessWorkerStarting, future)) {
        _postProcessWorkerStarting = null;
      }
    }
  }

  void _discardPostProcessWorker(Object error) {
    _postProcessWorkerGeneration += 1;
    _postProcessIdleTimer?.cancel();
    _postProcessIdleTimer = null;
    final worker = _postProcessWorker;
    _postProcessWorker = null;
    _postProcessWorkerStarting = null;
    worker?.dispose(error);
  }

  void _schedulePostProcessWorkerRelease() {
    _postProcessIdleTimer?.cancel();
    _postProcessIdleTimer = Timer(const Duration(hours: 1), () {
      if (_postProcessActive || _disposed) return;
      _discardPostProcessWorker(
        const FormatException('Storage screenshot cache expired.'),
      );
    });
  }
}

final class _NativeInventoryOcrWorker {
  _NativeInventoryOcrWorker._(this._process, this.helperPath) {
    _stdoutSubscription = _process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_handleLine, onError: _handleStreamError);
    _stderrSubscription = _process.stderr
        .transform(utf8.decoder)
        .listen(_handleStderr, onError: _handleStreamError);
    unawaited(
      _process.exitCode.then((exitCode) {
        if (_closed) return;
        final detail = _stderrText.toString().trim();
        _close(
          FormatException(
            detail.isEmpty
                ? 'Storage screenshot recognition stopped unexpectedly (exit $exitCode).'
                : detail,
          ),
          kill: false,
        );
      }),
    );
  }

  static Future<_NativeInventoryOcrWorker> start(File helper) async {
    final process = await Process.start(
      helper.path,
      const <String>['--server'],
      workingDirectory: helper.parent.path,
      runInShell: false,
      mode: ProcessStartMode.normal,
    );
    final worker = _NativeInventoryOcrWorker._(process, helper.path);
    try {
      await worker._ready.future.timeout(const Duration(seconds: 30));
      return worker;
    } on Object {
      worker.dispose(
        const FormatException('Storage screenshot recognizer could not start.'),
      );
      rethrow;
    }
  }

  final Process _process;
  final String helperPath;
  final Completer<void> _ready = Completer<void>();
  final Map<int, Completer<String>> _pending = <int, Completer<String>>{};
  final StringBuffer _stderrText = StringBuffer();
  late final StreamSubscription<String> _stdoutSubscription;
  late final StreamSubscription<String> _stderrSubscription;
  int _nextRequestId = 0;
  bool _closed = false;
  bool _warmed = false;

  bool get isClosed => _closed;

  bool isFor(String path) =>
      !_closed &&
      helperPath.toLowerCase() == File(path).absolute.path.toLowerCase();

  Future<String> recognize(String requestJson) async {
    return _request(requestJson);
  }

  Future<void> warm() async {
    if (_warmed) return;
    final response = await _request('WARM');
    if (response != 'WARM') {
      throw const FormatException(
        'Storage screenshot recognizer returned an invalid warm-up response.',
      );
    }
    _warmed = true;
  }

  Future<String> _request(String payload) async {
    if (_closed) {
      throw const FormatException(
        'Storage screenshot recognizer is unavailable.',
      );
    }
    if (_pending.isNotEmpty) {
      throw const FormatException(
        'A storage screenshot is already being recognized.',
      );
    }
    final requestId = ++_nextRequestId;
    final completer = Completer<String>();
    _pending[requestId] = completer;
    try {
      _process.stdin.writeln('$requestId\t$payload');
      await _process.stdin.flush();
    } on Object catch (error) {
      _pending.remove(requestId);
      _close(
        FormatException(
          'Storage screenshot recognition could not start: $error',
        ),
        kill: true,
      );
      rethrow;
    }
    return completer.future;
  }

  void dispose(Object error) => _close(error, kill: true);

  void _handleLine(String line) {
    if (_closed) return;
    if (!_ready.isCompleted) {
      if (line == 'READY\t1') {
        _ready.complete();
        return;
      }
      _close(
        const FormatException(
          'Storage screenshot recognizer returned an invalid startup response.',
        ),
        kill: true,
      );
      return;
    }
    if (line.length > _maximumResponseBytes + _maximumErrorBytes + 64) {
      _close(
        const FormatException(
          'Storage screenshot recognition result was too large.',
        ),
        kill: true,
      );
      return;
    }
    final firstSeparator = line.indexOf('\t');
    final secondSeparator = firstSeparator < 0
        ? -1
        : line.indexOf('\t', firstSeparator + 1);
    if (firstSeparator <= 0 || secondSeparator <= firstSeparator + 1) {
      _close(
        const FormatException(
          'Storage screenshot recognizer returned an invalid response.',
        ),
        kill: true,
      );
      return;
    }
    final requestId = int.tryParse(
      line.substring(firstSeparator + 1, secondSeparator),
    );
    final completer = requestId == null ? null : _pending.remove(requestId);
    if (completer == null || completer.isCompleted) return;
    final status = line.substring(0, firstSeparator);
    final payload = line.substring(secondSeparator + 1);
    if (status == 'OK' && payload.isNotEmpty) {
      completer.complete(payload);
    } else if (status == 'ERR') {
      completer.completeError(
        FormatException(
          payload.trim().isEmpty
              ? 'Storage screenshot recognition failed.'
              : payload.trim(),
        ),
      );
    } else {
      completer.completeError(
        const FormatException(
          'Storage screenshot recognizer returned an invalid response.',
        ),
      );
    }
  }

  void _handleStderr(String chunk) {
    if (_stderrText.length >= _maximumErrorBytes) return;
    final remaining = _maximumErrorBytes - _stderrText.length;
    _stderrText.write(
      chunk.length <= remaining ? chunk : chunk.substring(0, remaining),
    );
  }

  void _handleStreamError(Object error) {
    _close(
      FormatException('Storage screenshot recognition failed: $error'),
      kill: true,
    );
  }

  void _close(Object error, {required bool kill}) {
    if (_closed) return;
    _closed = true;
    if (kill) _process.kill();
    if (!_ready.isCompleted) _ready.completeError(error);
    for (final completer in _pending.values) {
      if (!completer.isCompleted) completer.completeError(error);
    }
    _pending.clear();
    unawaited(_process.stdin.close());
    unawaited(_stdoutSubscription.cancel());
    unawaited(_stderrSubscription.cancel());
  }
}

final class _InventoryScreenshotPostProcessWorkerPool {
  _InventoryScreenshotPostProcessWorkerPool._(this._workers);

  static Future<_InventoryScreenshotPostProcessWorkerPool> start() async {
    final workers = <_InventoryScreenshotPostProcessWorker>[];
    try {
      // Three workers keep the exact per-slot matcher unchanged while using
      // modern multi-core PCs. A fourth copy has a much larger memory cost for
      // little additional latency improvement on a typical 88-slot storage.
      for (var index = 0; index < 3; index += 1) {
        workers.add(await _InventoryScreenshotPostProcessWorker.start());
      }
      return _InventoryScreenshotPostProcessWorkerPool._(
        List<_InventoryScreenshotPostProcessWorker>.unmodifiable(workers),
      );
    } on Object {
      for (final worker in workers) {
        worker.dispose(
          const FormatException(
            'Storage screenshot post-processing could not start.',
          ),
        );
      }
      rethrow;
    }
  }

  final List<_InventoryScreenshotPostProcessWorker> _workers;

  bool get isClosed => _workers.any((worker) => worker.isClosed);

  bool isConfiguredFor(String configurationKey) =>
      !isClosed &&
      _workers.every((worker) => worker.isConfiguredFor(configurationKey));

  Future<void> prewarm({
    required String configurationKey,
    required InventoryOcrMaterialCatalog catalog,
    required _InventoryOcrArtworkConfiguration artworkConfiguration,
  }) => Future.wait<void>(<Future<void>>[
    for (final worker in _workers)
      worker.prewarm(
        configurationKey: configurationKey,
        catalog: catalog,
        artworkConfiguration: artworkConfiguration,
      ),
  ]);

  Future<InventoryScreenshotDraft> sanitize({
    required String configurationKey,
    required String rawResultJson,
    required Uint8List screenshotBytes,
    required InventoryOcrMaterialCatalog catalog,
    required _InventoryOcrArtworkConfiguration artworkConfiguration,
  }) async {
    final drafts = await Future.wait<InventoryScreenshotDraft>(
      <Future<InventoryScreenshotDraft>>[
        for (var index = 0; index < _workers.length; index += 1)
          _workers[index].sanitize(
            configurationKey: configurationKey,
            rawResultJson: rawResultJson,
            screenshotBytes: screenshotBytes,
            catalog: catalog,
            artworkConfiguration: artworkConfiguration,
            partitionIndex: index,
            partitionCount: _workers.length,
          ),
      ],
    );
    return _mergeInventoryScreenshotDrafts(drafts);
  }

  void dispose(Object error) {
    for (final worker in _workers) {
      worker.dispose(error);
    }
  }
}

InventoryScreenshotDraft _mergeInventoryScreenshotDrafts(
  List<InventoryScreenshotDraft> drafts,
) {
  if (drafts.isEmpty) {
    throw const FormatException('Storage screenshot post-processing failed.');
  }
  final first = drafts.first;
  final rows = <InventoryScreenshotRow>[
    for (final draft in drafts) ...draft.rows,
  ];
  final hiddenRows = <InventoryScreenshotRow>[
    for (final draft in drafts) ...draft.hiddenRows,
  ];
  int byGridPosition(
    InventoryScreenshotRow left,
    InventoryScreenshotRow right,
  ) {
    final row = left.row.compareTo(right.row);
    return row != 0 ? row : left.column.compareTo(right.column);
  }

  rows.sort(byGridPosition);
  hiddenRows.sort(byGridPosition);
  return InventoryScreenshotDraft(
    imageFingerprint: first.imageFingerprint,
    sourceWidth: first.sourceWidth,
    sourceHeight: first.sourceHeight,
    gridColumns: first.gridColumns,
    gridRows: first.gridRows,
    gridConfidence: first.gridConfidence,
    rows: List<InventoryScreenshotRow>.unmodifiable(rows),
    hiddenRows: List<InventoryScreenshotRow>.unmodifiable(hiddenRows),
    warnings: first.warnings,
  );
}

final class _InventoryScreenshotPostProcessWorker {
  _InventoryScreenshotPostProcessWorker._({
    required this._isolate,
    required this._commandPort,
    required this._replies,
    required this._errors,
    required this._exits,
  }) {
    _replySubscription = _replies.listen(_handleReply);
    _errorSubscription = _errors.listen((Object? error) {
      _close(
        FormatException(
          'Storage screenshot post-processing failed: ${_isolateError(error)}',
        ),
        kill: false,
      );
    });
    _exitSubscription = _exits.listen((Object? _) {
      _close(
        const FormatException(
          'Storage screenshot post-processing stopped unexpectedly.',
        ),
        kill: false,
      );
    });
  }

  static Future<_InventoryScreenshotPostProcessWorker> start() async {
    final ready = ReceivePort();
    final replies = ReceivePort();
    final errors = ReceivePort();
    final exits = ReceivePort();
    Isolate? isolate;
    try {
      isolate = await Isolate.spawn<(SendPort, SendPort)>(
        _inventoryScreenshotPostProcessWorkerMain,
        (ready.sendPort, replies.sendPort),
        debugName: 'inventory-screenshot-post-process',
        errorsAreFatal: true,
        onError: errors.sendPort,
        onExit: exits.sendPort,
      );
      final command = await ready.first.timeout(const Duration(seconds: 10));
      if (command is! SendPort) {
        throw const FormatException(
          'Storage screenshot post-processing could not start.',
        );
      }
      ready.close();
      return _InventoryScreenshotPostProcessWorker._(
        isolate: isolate,
        commandPort: command,
        replies: replies,
        errors: errors,
        exits: exits,
      );
    } on Object {
      isolate?.kill(priority: Isolate.immediate);
      ready.close();
      replies.close();
      errors.close();
      exits.close();
      rethrow;
    }
  }

  final Isolate _isolate;
  final SendPort _commandPort;
  final ReceivePort _replies;
  final ReceivePort _errors;
  final ReceivePort _exits;
  final Map<int, Completer<InventoryScreenshotDraft>> _pending =
      <int, Completer<InventoryScreenshotDraft>>{};
  final Map<int, Completer<void>> _prewarmPending = <int, Completer<void>>{};
  late final StreamSubscription<Object?> _replySubscription;
  late final StreamSubscription<Object?> _errorSubscription;
  late final StreamSubscription<Object?> _exitSubscription;
  int _nextRequestId = 0;
  String? _configuredKey;
  bool _closed = false;

  bool get isClosed => _closed;

  bool isConfiguredFor(String configurationKey) =>
      !_closed && _configuredKey == configurationKey;

  Future<void> prewarm({
    required String configurationKey,
    required InventoryOcrMaterialCatalog catalog,
    required _InventoryOcrArtworkConfiguration artworkConfiguration,
  }) {
    if (_closed) {
      return Future<void>.error(
        const FormatException(
          'Storage screenshot post-processing is unavailable.',
        ),
      );
    }
    final requestId = ++_nextRequestId;
    final completer = Completer<void>();
    _prewarmPending[requestId] = completer;
    final needsConfiguration = _configuredKey != configurationKey;
    final rgbBytes = needsConfiguration
        ? artworkConfiguration.preprocessedRgbBytes
        : null;
    _commandPort.send(<Object?>[
      requestId,
      configurationKey,
      if (needsConfiguration) catalog else null,
      if (needsConfiguration) artworkConfiguration.nativeArtworkBytes else null,
      if (needsConfiguration)
        artworkConfiguration.preprocessedIndexJson
      else
        null,
      if (rgbBytes == null)
        null
      else
        TransferableTypedData.fromList(<Uint8List>[
          Uint8List.fromList(rgbBytes),
        ]),
      null,
      null,
      0,
      1,
    ]);
    return completer.future.then((_) {
      _configuredKey = configurationKey;
    });
  }

  Future<InventoryScreenshotDraft> sanitize({
    required String configurationKey,
    required String rawResultJson,
    required Uint8List screenshotBytes,
    required InventoryOcrMaterialCatalog catalog,
    required _InventoryOcrArtworkConfiguration artworkConfiguration,
    int partitionIndex = 0,
    int partitionCount = 1,
  }) {
    if (_closed) {
      return Future<InventoryScreenshotDraft>.error(
        const FormatException(
          'Storage screenshot post-processing is unavailable.',
        ),
      );
    }
    final requestId = ++_nextRequestId;
    final completer = Completer<InventoryScreenshotDraft>();
    _pending[requestId] = completer;
    final needsConfiguration = _configuredKey != configurationKey;
    final rgbBytes = needsConfiguration
        ? artworkConfiguration.preprocessedRgbBytes
        : null;
    _commandPort.send(<Object?>[
      requestId,
      configurationKey,
      if (needsConfiguration) catalog else null,
      if (needsConfiguration) artworkConfiguration.nativeArtworkBytes else null,
      if (needsConfiguration)
        artworkConfiguration.preprocessedIndexJson
      else
        null,
      if (rgbBytes == null)
        null
      else
        TransferableTypedData.fromList(<Uint8List>[
          Uint8List.fromList(rgbBytes),
        ]),
      rawResultJson,
      TransferableTypedData.fromList(<Uint8List>[
        Uint8List.fromList(screenshotBytes),
      ]),
      partitionIndex,
      partitionCount,
    ]);
    return completer.future.then((draft) {
      _configuredKey = configurationKey;
      return draft;
    });
  }

  void dispose(Object error) => _close(error, kill: true);

  void _handleReply(Object? message) {
    if (_closed || message is! List<Object?> || message.length != 4) return;
    final requestId = message[0];
    if (requestId is! int) return;
    final prewarmCompleter = _prewarmPending.remove(requestId);
    if (prewarmCompleter != null) {
      final error = message[2];
      if (message[1] == true && error == null) {
        prewarmCompleter.complete();
      } else {
        prewarmCompleter.completeError(
          FormatException(
            error is String && error.trim().isNotEmpty
                ? error.trim()
                : 'Storage screenshot post-processing warm-up failed.',
          ),
          message[3] is String
              ? StackTrace.fromString(message[3] as String)
              : null,
        );
      }
      return;
    }
    final completer = _pending.remove(requestId);
    if (completer == null || completer.isCompleted) return;
    final draft = message[1];
    final error = message[2];
    if (draft is InventoryScreenshotDraft && error == null) {
      completer.complete(draft);
      return;
    }
    completer.completeError(
      FormatException(
        error is String && error.trim().isNotEmpty
            ? error.trim()
            : 'Storage screenshot post-processing failed.',
      ),
      message[3] is String ? StackTrace.fromString(message[3] as String) : null,
    );
  }

  void _close(Object error, {required bool kill}) {
    if (_closed) return;
    _closed = true;
    if (kill) _isolate.kill(priority: Isolate.immediate);
    for (final completer in _pending.values) {
      if (!completer.isCompleted) completer.completeError(error);
    }
    _pending.clear();
    for (final completer in _prewarmPending.values) {
      if (!completer.isCompleted) completer.completeError(error);
    }
    _prewarmPending.clear();
    unawaited(_replySubscription.cancel());
    unawaited(_errorSubscription.cancel());
    unawaited(_exitSubscription.cancel());
    _replies.close();
    _errors.close();
    _exits.close();
  }
}

String _isolateError(Object? error) {
  if (error is List<Object?> && error.isNotEmpty) return '${error.first}';
  final text = '$error'.trim();
  return text.isEmpty ? 'unknown worker error' : text;
}

@pragma('vm:entry-point')
void _inventoryScreenshotPostProcessWorkerMain((SendPort, SendPort) bootstrap) {
  final commands = ReceivePort();
  bootstrap.$1.send(commands.sendPort);
  String? configurationKey;
  InventoryScreenshotPostProcessor? processor;
  commands.listen((Object? message) {
    if (message is! List<Object?> || message.length != 10) return;
    final requestId = message[0];
    if (requestId is! int) return;
    try {
      final requestedConfigurationKey = message[1] as String;
      if (processor == null || configurationKey != requestedConfigurationKey) {
        final catalog = message[2] as InventoryOcrMaterialCatalog?;
        final artwork = message[3] as Map<String, Uint8List>?;
        final cacheIndexJson = message[4] as String?;
        final cacheTransfer = message[5] as TransferableTypedData?;
        if (catalog == null || artwork == null) {
          throw const FormatException(
            'Storage screenshot post-processing configuration is missing.',
          );
        }
        final cache = cacheIndexJson == null || cacheTransfer == null
            ? null
            : InventoryOcrPreprocessedTemplateCache.decode(
                indexJson: cacheIndexJson,
                rgbBytes: cacheTransfer.materialize().asUint8List(),
              );
        processor = InventoryScreenshotPostProcessor(
          catalog: catalog,
          nativeArtworkBytes: artwork,
          preprocessedTemplateCache: cache,
        );
        configurationKey = requestedConfigurationKey;
      }
      if (message[6] == null && message[7] == null) {
        processor!.prewarm();
        bootstrap.$2.send(<Object?>[requestId, true, null, null]);
        return;
      }
      final screenshot = (message[7] as TransferableTypedData)
          .materialize()
          .asUint8List();
      final rawResult = _partitionInventoryScreenshotResult(
        jsonDecode(message[6] as String),
        partitionIndex: message[8] as int,
        partitionCount: message[9] as int,
      );
      final draft = processor!.sanitize(
        rawResult: rawResult,
        screenshotBytes: screenshot,
      );
      bootstrap.$2.send(<Object?>[requestId, draft, null, null]);
    } on Object catch (error, stackTrace) {
      bootstrap.$2.send(<Object?>[requestId, null, '$error', '$stackTrace']);
    }
  });
}

Object? _partitionInventoryScreenshotResult(
  Object? rawResult, {
  required int partitionIndex,
  required int partitionCount,
}) {
  if (partitionCount <= 1) return rawResult;
  if (partitionIndex < 0 || partitionIndex >= partitionCount) {
    throw const FormatException(
      'Storage screenshot post-processing partition is invalid.',
    );
  }
  if (rawResult is! Map<String, Object?> ||
      rawResult['slots'] is! List<Object?>) {
    return rawResult;
  }
  final slots = rawResult['slots']! as List<Object?>;
  return <String, Object?>{
    ...rawResult,
    'slots': <Object?>[
      for (
        var index = partitionIndex;
        index < slots.length;
        index += partitionCount
      )
        slots[index],
    ],
  };
}

/// Runs the expensive pixel/colour matching pass outside Flutter's UI
/// isolate. This boundary is public for a focused responsiveness contract
/// test; recognition policy remains owned by [InventoryScreenshotResultSanitizer].
@visibleForTesting
Future<InventoryScreenshotDraft> sanitizeInventoryScreenshotInBackground({
  required Object? rawResult,
  required Uint8List screenshotBytes,
  required InventoryOcrMaterialCatalog catalog,
  required Map<String, Uint8List> nativeArtworkBytes,
}) {
  final request = (
    rawResult: rawResult,
    screenshotBytes: screenshotBytes,
    catalog: catalog,
    nativeArtworkBytes: nativeArtworkBytes,
  );
  return Isolate.run(
    () => const InventoryScreenshotResultSanitizer().sanitize(
      rawResult: request.rawResult,
      screenshotBytes: request.screenshotBytes,
      catalog: request.catalog,
      nativeArtworkBytes: request.nativeArtworkBytes,
    ),
    debugName: 'inventory-screenshot-post-process',
  );
}

/// Exercises the same three-worker partition/merge path used by production.
@visibleForTesting
Future<InventoryScreenshotDraft>
sanitizeInventoryScreenshotWithWorkerPoolForTesting({
  required Object? rawResult,
  required Uint8List screenshotBytes,
  required InventoryOcrMaterialCatalog catalog,
  required Map<String, Uint8List> nativeArtworkBytes,
}) async {
  final pool = await _InventoryScreenshotPostProcessWorkerPool.start();
  try {
    return await pool.sanitize(
      configurationKey: 'test',
      rawResultJson: jsonEncode(rawResult),
      screenshotBytes: screenshotBytes,
      catalog: catalog,
      artworkConfiguration: _InventoryOcrArtworkConfiguration(
        nativeArtworkBytes: nativeArtworkBytes,
      ),
    );
  } finally {
    pool.dispose(
      const FormatException('Storage screenshot worker-pool test finished.'),
    );
  }
}

/// Loads the complete eligible RecipeBook artwork set passed to recognition.
///
/// This boundary is visible for a focused filesystem contract test. Production
/// passes [InventoryOcrMaterialCatalog.nativeArtworkPaths], independently of
/// the native helper's per-slot candidate shortlist.
@visibleForTesting
Future<Map<String, Uint8List>> loadNativeInventoryArtworkGalleryForTesting({
  required File helper,
  required Iterable<String> eligibleArtworkPaths,
}) async {
  final requested = <String>{};
  for (final rawIcon in eligibleArtworkPaths) {
    final icon = rawIcon.trim().replaceAll('\\', '/').toLowerCase();
    if (RegExp(r'^icons/items/[a-f0-9]{64}\.webp$').hasMatch(icon)) {
      requested.add(icon);
    }
  }

  final recipeBookDirectory = Directory(
    '${helper.parent.path}${Platform.pathSeparator}Assets'
    '${Platform.pathSeparator}RecipeBook',
  );
  final loaded = <String, Uint8List>{};
  var totalBytes = 0;
  for (final icon in requested.take(4096)) {
    final relative = icon.replaceAll('/', Platform.pathSeparator);
    final file = File(
      '${recipeBookDirectory.path}${Platform.pathSeparator}$relative',
    );
    final stat = await file.stat();
    if (stat.type != FileSystemEntityType.file ||
        stat.size <= 0 ||
        stat.size > 256 * 1024 ||
        totalBytes + stat.size > 32 * 1024 * 1024) {
      continue;
    }
    final bytes = await file.readAsBytes();
    totalBytes += bytes.length;
    loaded[icon] = bytes;
  }
  return Map<String, Uint8List>.unmodifiable(loaded);
}

void _validateImage(
  Uint8List bytes, {
  required String fileName,
  required String mimeType,
}) {
  if (bytes.isEmpty || bytes.length > _maximumScreenshotBytes) {
    throw const FormatException(
      'Choose a PNG, JPEG, or BMP screenshot smaller than 16 MB.',
    );
  }
  if (fileName.length > 255 ||
      fileName.contains('/') ||
      fileName.contains('\\')) {
    throw const FormatException('The screenshot filename is invalid.');
  }
  final expectedMime = _mimeTypeForFileName(fileName);
  if (mimeType != expectedMime) {
    throw const FormatException(
      'The screenshot filename and image type do not match.',
    );
  }
  final validSignature = switch (mimeType) {
    'image/png' => _isPng(bytes),
    'image/jpeg' => _isJpeg(bytes),
    'image/bmp' => _isBmp(bytes),
    _ => false,
  };
  if (!validSignature) {
    throw const FormatException(
      'Choose a valid PNG, JPEG, or BMP storage screenshot.',
    );
  }
  if (mimeType == 'image/png' && _isAnimatedPng(bytes)) {
    throw const FormatException('Animated PNG screenshots are not supported.');
  }
  final decoder = switch (mimeType) {
    'image/png' => image.PngDecoder(),
    'image/jpeg' => image.JpegDecoder(),
    'image/bmp' => image.BmpDecoder(),
    _ => null,
  };
  final info = decoder?.startDecode(bytes);
  if (info == null ||
      info.width <= 0 ||
      info.height <= 0 ||
      info.width > 7680 ||
      info.height > 4320 ||
      info.width * info.height > 24000000) {
    throw const FormatException('The screenshot dimensions are not supported.');
  }
}

String _safeBaseName(String path) {
  final normalized = path.replaceAll('\\', '/');
  final name = normalized.split('/').last.trim();
  if (name.isEmpty || name.length > 255) {
    throw const FormatException('The screenshot filename is invalid.');
  }
  return name;
}

String _mimeTypeForFileName(String fileName) {
  final folded = fileName.toLowerCase();
  if (folded.endsWith('.png')) return 'image/png';
  if (folded.endsWith('.jpg') || folded.endsWith('.jpeg')) {
    return 'image/jpeg';
  }
  if (folded.endsWith('.bmp')) return 'image/bmp';
  throw const FormatException('Choose a PNG, JPEG, or BMP screenshot.');
}

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

bool _isJpeg(Uint8List bytes) =>
    bytes.length >= 3 &&
    bytes[0] == 0xff &&
    bytes[1] == 0xd8 &&
    bytes[2] == 0xff;

bool _isBmp(Uint8List bytes) =>
    bytes.length >= 2 && bytes[0] == 0x42 && bytes[1] == 0x4d;

bool _isAnimatedPng(Uint8List bytes) {
  if (!_isPng(bytes)) return false;
  for (var index = 8; index + 12 <= bytes.length;) {
    final length =
        (bytes[index] << 24) |
        (bytes[index + 1] << 16) |
        (bytes[index + 2] << 8) |
        bytes[index + 3];
    if (length < 0 || index + 12 + length > bytes.length) return false;
    final type = ascii.decode(bytes.sublist(index + 4, index + 8));
    if (type == 'acTL') return true;
    if (type == 'IDAT' || type == 'IEND') return false;
    index += 12 + length;
  }
  return false;
}
