import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

const String fishCompanionAcceptedPayloadVersion =
    'd9998b921bcfa92464ab59b37072ae637470d621c672e81f71f23fc60c569868:'
    'c0b5c5c84980be389420cf247d7a89ac8c256676b7313ce3a496c933cb0667a9';

/// The credited, noncommercial public release includes the reviewed reference
/// snapshot accepted from the current Beta so Fish Map retains exact offline
/// behavior. Runtime refreshes still use the separate disposable cache.
const bool fishCompanionPublicReferenceBundleIncluded = true;

/// A clean install obtains the minimum reference data directly from the
/// credited public endpoints and writes it only to [referenceCacheRoot].
const bool fishCompanionPublicOnlineBootstrapEnabled = true;

/// Native Fish host exit code meaning its complete process tree could not be
/// proven stopped. Windows may expose the DWORD as either of these Dart ints.
const int fishCompanionManagedHostCleanupFailedExitCode = 0xE04A0001;
const int fishCompanionManagedHostCleanupFailedSignedExitCode =
    fishCompanionManagedHostCleanupFailedExitCode - 0x100000000;

bool isFishCompanionManagedHostCleanupFailedExitCode(int exitCode) =>
    (exitCode & 0xFFFFFFFF) == fishCompanionManagedHostCleanupFailedExitCode;

void _throwIfFishCompanionManagedHostCleanupFailed(int exitCode) {
  if (isFishCompanionManagedHostCleanupFailedExitCode(exitCode)) {
    throw FishCompanionManagedHostCleanupFailed(exitCode);
  }
}

const String _apiTokenHeader = 'X-BSL-API-Token';

const String _criticalManifestRelativePath =
    'data/install-critical-manifest.v1.json';
const List<String> _requiredImmutableCriticalPaths = <String>[
  'static/index.html',
  'static/app.js',
  'static/app.css',
  'runtime/fish_companion_service.exe',
];
const List<String> _requiredSnapshotCriticalPaths = <String>[
  'data/cache/fish.json',
  'data/cache/zones.json',
  'data/cache/meta.json',
  'data/cache/zone_mask.v8.bin',
  'data/cache/derived-index.v1.json',
];

typedef FishCompanionRuntimeStarter =
    Future<FishCompanionServiceHandle> Function(
      FishCompanionStartupCancellation cancellation,
    );

typedef FishCompanionManagedProcessStarter =
    Future<Process> Function(
      String executable,
      List<String> arguments, {
      required String workingDirectory,
    });

Future<Process> _startFishCompanionManagedProcess(
  String executable,
  List<String> arguments, {
  required String workingDirectory,
}) => Process.start(executable, arguments, workingDirectory: workingDirectory);

/// Cooperative cancellation for one Fish Companion startup generation.
///
/// Cancellation is terminal for the generation. A starter must stop any
/// in-flight file reads or child processes, await their cleanup, and then
/// throw [FishCompanionStartupCanceled].
final class FishCompanionStartupCancellation {
  final Completer<void> _canceled = Completer<void>();
  final Set<void Function()> _listeners = <void Function()>{};

  bool get isCanceled => _canceled.isCompleted;

  Future<void> get whenCanceled => _canceled.future;

  void throwIfCanceled() {
    if (isCanceled) throw const FishCompanionStartupCanceled();
  }

  void Function() _addListener(void Function() listener) {
    if (isCanceled) {
      try {
        listener();
      } on Object {
        // The owning operation still observes cancellation below.
      }
      return () {};
    }
    _listeners.add(listener);
    return () => _listeners.remove(listener);
  }

  void _cancel() {
    if (isCanceled) return;
    _canceled.complete();
    final listeners = List<void Function()>.of(_listeners);
    _listeners.clear();
    for (final listener in listeners) {
      try {
        listener();
      } on Object {
        // Cancellation listeners are best-effort wakeups. The owning startup
        // future remains responsible for reporting and awaiting its cleanup.
      }
    }
  }
}

final class FishCompanionStartupCanceled implements Exception {
  const FishCompanionStartupCanceled();

  @override
  String toString() => 'Fish Companion startup was canceled.';
}

/// The managed native host could not prove that every Fish process stopped.
///
/// Retrying, moving personal data, or replacing application files is unsafe
/// until the owning Black Spirit Life process exits.
final class FishCompanionManagedHostCleanupFailed implements Exception {
  const FishCompanionManagedHostCleanupFailed([this.exitCode]);

  final int? exitCode;

  @override
  String toString() =>
      'Fish Companion could not stop its local process tree safely. '
      'Fully close and restart Black Spirit Life before trying Fish Map again.';
}

/// The running localhost service consumed by the exact Fish Companion UI.
abstract interface class FishCompanionServiceHandle {
  /// Immutable packaged application/reference root served by localhost.
  Directory get root;

  /// The selected Stable personal-data root used by the Fish journal.
  Directory get personalDataRoot;

  /// Explicit shared WebView2 profile directory beneath [personalDataRoot].
  Directory get webViewDataRoot;

  Uri get uri;

  /// Checkpoints durable SQLite state without stopping the service.
  Future<void> checkpoint();

  /// Checkpoints and stops the service, using termination only as a fallback.
  Future<void> shutdown();

  /// Synchronous widget-lifecycle bridge. Prefer awaiting [shutdown].
  void dispose();
}

/// A Fish surface whose native browser resources must be released before the
/// selected personal-data root can be moved or an update can replace files.
abstract interface class FishCompanionSurfaceLifecycle {
  Future<void> freezeForLifecycle();

  Future<void> resumeAfterLifecycleFailure();
}

/// App-lifetime owner for the Fish Companion localhost service.
///
/// Concurrent callers share one startup. A failed startup is cleared so a
/// later call can retry. The explicit lifecycle methods let the application
/// freeze personal data before moving it or replacing application files.
class FishCompanionRuntimeHost {
  FishCompanionRuntimeHost({
    required Directory personalDataRoot,
    required Directory referenceCacheRoot,
    required Directory webViewDataRoot,
    Directory? packagedPayloadRoot,
    File? legacyV017Journal,
    FishCompanionRuntimeStarter? starter,
    this.startupCancellationGracePeriod = const Duration(seconds: 4),
  }) : _starter =
           starter ??
           ((cancellation) => FishCompanionRuntime(
             personalDataRoot: personalDataRoot,
             packagedPayloadRoot: packagedPayloadRoot,
             referenceCacheRoot: referenceCacheRoot,
             webViewDataRoot: webViewDataRoot,
             legacyV017Journal: legacyV017Journal,
           ).start(cancellation: cancellation));

  FishCompanionRuntimeHost.withStarter(
    this._starter, {
    this.startupCancellationGracePeriod = const Duration(seconds: 4),
  });

  final FishCompanionRuntimeStarter _starter;
  final Duration startupCancellationGracePeriod;

  Future<FishCompanionServiceHandle>? _ready;
  Future<FishCompanionServiceHandle>? _pendingStartupCleanup;
  FishCompanionStartupCancellation? _startupCancellation;
  FishCompanionServiceHandle? _handle;
  FishCompanionServiceHandle? _pendingHandleCleanup;
  FishCompanionManagedHostCleanupFailed? _terminalCleanupFailure;
  Future<void>? _transition;
  bool _transitionAllowsCleanupFailureForApplicationExit = false;
  Future<void>? _shutdown;
  int _generation = 0;
  bool _disposed = false;
  bool _frozen = false;
  bool _resumeAfterFreeze = false;
  final Set<FishCompanionSurfaceLifecycle> _surfaces =
      <FishCompanionSurfaceLifecycle>{};

  void attachSurface(FishCompanionSurfaceLifecycle surface) {
    if (_disposed) {
      throw StateError('The Fish Companion runtime host has been disposed.');
    }
    // Flutter can mount a replacement surface before disposing the previous
    // keyed widget. Track both during that short reconciliation window so a
    // lifecycle freeze still closes every browser surface safely.
    _surfaces.add(surface);
  }

  void detachSurface(FishCompanionSurfaceLifecycle surface) {
    _surfaces.remove(surface);
  }

  Future<FishCompanionServiceHandle> ready() {
    if (_disposed) {
      return Future<FishCompanionServiceHandle>.error(
        StateError('The Fish Companion runtime host has been disposed.'),
      );
    }
    final terminalCleanupFailure = _terminalCleanupFailure;
    if (terminalCleanupFailure != null) {
      return Future<FishCompanionServiceHandle>.error(terminalCleanupFailure);
    }
    if (_frozen) {
      return Future<FishCompanionServiceHandle>.error(
        StateError('The Fish Companion runtime host is frozen.'),
      );
    }
    final existing = _ready;
    if (existing != null) return existing;
    final cancellation = FishCompanionStartupCancellation();
    _startupCancellation = cancellation;
    return _ready = _start(++_generation, cancellation);
  }

  /// Starts the service opportunistically without surfacing a background
  /// failure. [ready] remains retryable when this attempt fails.
  Future<void> prewarm() async {
    try {
      await ready();
    } on Object {
      // Opening Fish Companion will retry and present its normal error state.
    }
  }

  Future<FishCompanionServiceHandle> _start(
    int generation,
    FishCompanionStartupCancellation cancellation,
  ) async {
    try {
      final handle = await _starter(cancellation);
      if (_disposed || generation != _generation) {
        if (!_disposed) _resumeAfterFreeze = true;
        await _shutdownHandleOrRetain(handle);
        throw StateError('The Fish Companion runtime host was stopped.');
      }
      _handle = handle;
      _resumeAfterFreeze = false;
      return handle;
    } on FishCompanionManagedHostCleanupFailed catch (error) {
      _terminalCleanupFailure ??= error;
      if (!_disposed && generation == _generation) {
        _ready = null;
      }
      rethrow;
    } on Object {
      if (!_disposed && generation == _generation) {
        _ready = null;
      }
      rethrow;
    } finally {
      if (identical(_startupCancellation, cancellation)) {
        _startupCancellation = null;
      }
    }
  }

  /// Checkpoints the current journal without causing an unstarted host to boot.
  Future<void> flushForLifecycle() async {
    final transition = _transition;
    if (transition != null) await transition;
    final handle = _handle;
    if (handle != null) await handle.checkpoint();
  }

  /// Stops and checkpoints the service while keeping this host restartable.
  Future<void> freezeAndFlush() =>
      _beginFreezeAndFlush(allowCleanupFailureForApplicationExit: false);

  /// Freezes browser surfaces and durable state for a full process exit.
  ///
  /// A cleanup-unproven failure remains sticky and blocks every in-process
  /// retry, update, or data move. It is tolerated only after this
  /// application-exit barrier has frozen the attached surfaces, because owner
  /// process termination is the final recovery for any surviving child.
  Future<void> freezeAndFlushForApplicationExit() =>
      _beginFreezeAndFlush(allowCleanupFailureForApplicationExit: true);

  Future<void> _beginFreezeAndFlush({
    required bool allowCleanupFailureForApplicationExit,
  }) {
    final existing = _transition;
    if (existing != null) {
      if (!allowCleanupFailureForApplicationExit &&
          _transitionAllowsCleanupFailureForApplicationExit) {
        return Future<void>.error(
          StateError(
            'Fish Companion is already preparing for full application exit.',
          ),
        );
      }
      return existing;
    }
    final operation = _freezeAndFlush(
      allowCleanupFailureForApplicationExit:
          allowCleanupFailureForApplicationExit,
    );
    _transition = operation;
    _transitionAllowsCleanupFailureForApplicationExit =
        allowCleanupFailureForApplicationExit;
    return operation.whenComplete(() {
      if (identical(_transition, operation)) {
        _transition = null;
        _transitionAllowsCleanupFailureForApplicationExit = false;
      }
    });
  }

  Future<void> _freezeAndFlush({
    required bool allowCleanupFailureForApplicationExit,
  }) async {
    _frozen = true;
    final terminalCleanupFailure = _terminalCleanupFailure;
    if (terminalCleanupFailure != null &&
        !allowCleanupFailureForApplicationExit) {
      throw terminalCleanupFailure;
    }
    final earlierStartupCleanup = _pendingStartupCleanup;
    if (earlierStartupCleanup != null) {
      try {
        await _awaitStartupCleanup(earlierStartupCleanup);
      } on FishCompanionManagedHostCleanupFailed {
        if (!allowCleanupFailureForApplicationExit) rethrow;
      }
      if (identical(_pendingStartupCleanup, earlierStartupCleanup)) {
        _pendingStartupCleanup = null;
      }
    }
    try {
      await _finishPendingHandleCleanup();
    } on FishCompanionManagedHostCleanupFailed {
      if (!allowCleanupFailureForApplicationExit) rethrow;
    }
    _generation += 1;
    final pending = _ready;
    final startupCancellation = _startupCancellation;
    final handle = _handle;
    final hadRuntimeActivity = handle != null || pending != null;
    if (pending != null && !_disposed) _resumeAfterFreeze = true;
    startupCancellation?._cancel();
    _ready = null;
    _startupCancellation = null;
    _handle = null;
    Object? surfaceError;
    StackTrace? surfaceStackTrace;
    if (hadRuntimeActivity || allowCleanupFailureForApplicationExit) {
      for (final surface in List<FishCompanionSurfaceLifecycle>.of(_surfaces)) {
        try {
          await surface.freezeForLifecycle();
        } on Object catch (error, stackTrace) {
          surfaceError ??= error;
          surfaceStackTrace ??= stackTrace;
        }
      }
    }
    if (handle != null) {
      if (!_disposed) _resumeAfterFreeze = true;
      try {
        await _shutdownHandleOrRetain(handle);
      } on FishCompanionManagedHostCleanupFailed {
        if (!allowCleanupFailureForApplicationExit) rethrow;
      }
    } else if (pending != null) {
      try {
        await pending.timeout(
          startupCancellationGracePeriod,
          onTimeout: () => throw const _FishCompanionStartupCleanupTimedOut(),
        );
      } on _FishCompanionStartupCleanupTimedOut {
        _pendingStartupCleanup = pending;
        throw TimeoutException(
          'Fish Companion startup cleanup did not finish within '
          '${startupCancellationGracePeriod.inSeconds} seconds.',
        );
      } on FishCompanionManagedHostCleanupFailed catch (error) {
        _terminalCleanupFailure ??= error;
        if (!allowCleanupFailureForApplicationExit) rethrow;
      } on Object {
        // A failed or generation-cancelled startup is already fully stopped.
      }
      try {
        await _finishPendingHandleCleanup();
      } on FishCompanionManagedHostCleanupFailed {
        if (!allowCleanupFailureForApplicationExit) rethrow;
      }
    }
    final cleanupFailure = _terminalCleanupFailure;
    if (cleanupFailure != null && !allowCleanupFailureForApplicationExit) {
      throw cleanupFailure;
    }
    if (surfaceError != null) {
      Error.throwWithStackTrace(surfaceError, surfaceStackTrace!);
    }
  }

  /// Restarts after a failed directory move/update transaction.
  Future<void> resumeAfterFailure() async {
    if (_disposed) {
      throw StateError('The Fish Companion runtime host has been disposed.');
    }
    final transition = _transition;
    if (transition != null) await transition;
    final pendingStartupCleanup = _pendingStartupCleanup;
    if (pendingStartupCleanup != null) {
      await _awaitStartupCleanup(pendingStartupCleanup);
      if (identical(_pendingStartupCleanup, pendingStartupCleanup)) {
        _pendingStartupCleanup = null;
      }
    }
    await _finishPendingHandleCleanup();
    final terminalCleanupFailure = _terminalCleanupFailure;
    if (terminalCleanupFailure != null) throw terminalCleanupFailure;
    _frozen = false;
    if (!_resumeAfterFreeze) return;
    _resumeAfterFreeze = false;
    try {
      await ready();
      for (final surface in List<FishCompanionSurfaceLifecycle>.of(_surfaces)) {
        await surface.resumeAfterLifecycleFailure();
      }
    } on Object {
      _resumeAfterFreeze = true;
      rethrow;
    }
  }

  Future<void> _awaitStartupCleanup(
    Future<FishCompanionServiceHandle> pending,
  ) async {
    try {
      await pending.timeout(
        startupCancellationGracePeriod,
        onTimeout: () => throw const _FishCompanionStartupCleanupTimedOut(),
      );
    } on _FishCompanionStartupCleanupTimedOut {
      throw TimeoutException(
        'Fish Companion startup cleanup is still in progress.',
      );
    } on FishCompanionManagedHostCleanupFailed catch (error) {
      _terminalCleanupFailure ??= error;
      rethrow;
    } on Object {
      // The canceled generation has stopped and cannot become the live handle.
    }
  }

  Future<void> _shutdownHandleOrRetain(
    FishCompanionServiceHandle handle,
  ) async {
    try {
      await handle.shutdown();
    } on FishCompanionManagedHostCleanupFailed catch (error) {
      _terminalCleanupFailure ??= error;
      _pendingHandleCleanup ??= handle;
      rethrow;
    } on Object {
      _pendingHandleCleanup ??= handle;
      rethrow;
    }
  }

  Future<void> _finishPendingHandleCleanup() async {
    final pending = _pendingHandleCleanup;
    if (pending == null) return;
    await _shutdownHandleOrRetain(pending);
    if (identical(_pendingHandleCleanup, pending)) {
      _pendingHandleCleanup = null;
    }
  }

  /// Permanently checkpoints and closes this host.
  Future<void> shutdown() {
    final existing = _shutdown;
    if (existing != null) return existing;
    _disposed = true;
    final operation = freezeAndFlush();
    late final Future<void> tracked;
    tracked = operation.then<void>(
      (_) {},
      onError: (Object error, StackTrace stackTrace) {
        if (identical(_shutdown, tracked)) _shutdown = null;
        Error.throwWithStackTrace(error, stackTrace);
      },
    );
    _shutdown = tracked;
    return tracked;
  }

  void dispose() {
    unawaited(shutdown());
  }
}

/// Starts the accepted standalone Fish Companion service.
///
/// Static UI and recognizer code stay in the immutable installed package. The
/// SQLite journal, durable Fish settings, and explicitly shared WebView2
/// profile live below [personalDataRoot]. Online-derived reference
/// acceleration uses a distinct, disposable [referenceCacheRoot] and never the
/// selected personal-data root.
class FishCompanionRuntime {
  FishCompanionRuntime({
    required this.personalDataRoot,
    required this.referenceCacheRoot,
    required this.webViewDataRoot,
    this.packagedPayloadRoot,
    this.legacyV017Journal,
    this.managedProcessHostExecutable,
    FishCompanionManagedProcessStarter? managedProcessStarter,
  }) : _managedProcessStarter =
           managedProcessStarter ?? _startFishCompanionManagedProcess;

  final Directory personalDataRoot;
  final Directory referenceCacheRoot;
  final Directory webViewDataRoot;
  final Directory? packagedPayloadRoot;
  final File? legacyV017Journal;
  final File? managedProcessHostExecutable;
  final FishCompanionManagedProcessStarter _managedProcessStarter;

  Future<FishCompanionRuntimeHandle> start({
    FishCompanionStartupCancellation? cancellation,
  }) async {
    final startup = cancellation ?? FishCompanionStartupCancellation();
    startup.throwIfCanceled();
    if (!Platform.isWindows) {
      throw UnsupportedError('Fish Companion requires Windows WebView2.');
    }

    final appRoot = await install(cancellation: startup);
    startup.throwIfCanceled();
    final cacheRoot = _resolveReferenceCacheRoot();
    final browserRoot = _resolveWebViewDataRoot();
    await cacheRoot.create(recursive: true);
    startup.throwIfCanceled();
    final database = File(
      _joinAll(<String>[
        personalDataRoot.absolute.path,
        'fishing',
        'fish-journal.sqlite3',
      ]),
    );
    final executable = File(
      _joinAll(<String>[appRoot.path, 'runtime', 'fish_companion_service.exe']),
    );
    final legacy =
        legacyV017Journal ??
        File(
          _joinAll(<String>[
            personalDataRoot.absolute.path,
            'fishing',
            'fishing-journal.json',
          ]),
        );
    final legacyExists = await legacy.exists();
    startup.throwIfCanceled();
    if (legacyExists) {
      await _migrateLegacyJournal(
        executable: executable,
        appRoot: appRoot,
        source: legacy,
        database: database,
        cancellation: startup,
      );
    }

    startup.throwIfCanceled();
    try {
      return await _startService(
        executable: executable,
        appRoot: appRoot,
        cacheRoot: cacheRoot,
        browserRoot: browserRoot,
        cancellation: startup,
      );
    } on _FishCompanionServiceExitedBeforeHealth catch (error) {
      _throwIfFishCompanionManagedHostCleanupFailed(error.exitCode);
      // The native managed host cannot exit until its complete Job Object has
      // stopped. One retry is therefore safe only for this exact failure.
      startup.throwIfCanceled();
      try {
        return await _startService(
          executable: executable,
          appRoot: appRoot,
          cacheRoot: cacheRoot,
          browserRoot: browserRoot,
          cancellation: startup,
        );
      } on _FishCompanionServiceExitedBeforeHealth catch (error) {
        _throwIfFishCompanionManagedHostCleanupFailed(error.exitCode);
        startup.throwIfCanceled();
        throw StateError(error.toString());
      }
    }
  }

  Future<FishCompanionRuntimeHandle> _startService({
    required File executable,
    required Directory appRoot,
    required Directory cacheRoot,
    required Directory browserRoot,
    required FishCompanionStartupCancellation cancellation,
  }) async {
    final port = await _availablePort(cancellation);
    cancellation.throwIfCanceled();
    final apiToken = _generateApiToken();
    final process = await _startManagedProcess(
      executable,
      <String>[
        '--root',
        appRoot.path,
        '--personal-data-root',
        personalDataRoot.absolute.path,
        '--reference-cache-root',
        cacheRoot.path,
        '--port',
        '$port',
        '--parent-pid',
        '$pid',
        '--api-token',
        apiToken,
      ],
      workingDirectory: appRoot.path,
      cancellation: cancellation,
    );
    final outputDrains = _ProcessOutputDrains(process);
    final baseUri = Uri.parse('http://127.0.0.1:$port/');
    try {
      cancellation.throwIfCanceled();
      await _waitUntilHealthy(
        baseUri.resolve('/api/health'),
        apiToken,
        process,
        cancellation,
      );
      cancellation.throwIfCanceled();
      return FishCompanionRuntimeHandle._(
        apiToken,
        process: process,
        outputDrains: outputDrains,
        root: appRoot,
        personalDataRoot: personalDataRoot.absolute,
        webViewDataRoot: browserRoot,
        uri: baseUri.replace(fragment: 'apiToken=$apiToken'),
      );
    } on _FishCompanionServiceExitedBeforeHealth catch (error, stackTrace) {
      if (isFishCompanionManagedHostCleanupFailedExitCode(error.exitCode)) {
        await _finishOutputDrainsPreservingError(
          outputDrains,
          FishCompanionManagedHostCleanupFailed(error.exitCode),
          stackTrace,
        );
      }
      await outputDrains.finish();
      throw error.withOutput(outputDrains);
    } on Object catch (error, stackTrace) {
      try {
        await _terminateProcess(process);
      } on Object catch (cleanupError, cleanupStackTrace) {
        await _finishOutputDrainsPreservingError(
          outputDrains,
          cleanupError,
          cleanupStackTrace,
        );
      }
      await outputDrains.finish();
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  /// Validates and returns the immutable packaged root without copying it.
  ///
  /// No static, reference, executable, cache, or journal file is ever placed
  /// beneath the selected personal-data root by this operation.
  Future<Directory> install({
    FishCompanionStartupCancellation? cancellation,
  }) async {
    final startup = cancellation ?? FishCompanionStartupCancellation();
    startup.throwIfCanceled();
    final packagedRoot =
        (packagedPayloadRoot ?? _locatePackagedPayload()).absolute;
    final cacheRoot = _resolveReferenceCacheRoot();
    _resolveWebViewDataRoot();
    final packagedRootExists = await packagedRoot.exists();
    startup.throwIfCanceled();
    if (!packagedRootExists) {
      throw StateError('The packaged Fish Companion payload is unavailable.');
    }
    if (_isWithin(cacheRoot.path, packagedRoot.path)) {
      throw StateError(
        'The Fish reference cache must be outside the immutable app root.',
      );
    }
    await _rejectPersonalJournalPayload(packagedRoot, startup);
    if (!fishCompanionPublicReferenceBundleIncluded &&
        !fishCompanionPublicOnlineBootstrapEnabled) {
      throw StateError(
        'Fish Map is disabled in this public build because its third-party '
        'reference bundle is not distributed.',
      );
    }
    final manifest = await _loadCriticalManifest(packagedRoot, startup);
    await _verifyPackagedCriticalFiles(packagedRoot, manifest, startup);
    startup.throwIfCanceled();
    return packagedRoot;
  }

  Directory _locatePackagedPayload() {
    final executableDirectory = File(Platform.resolvedExecutable).parent;
    final candidates = <Directory>[
      Directory(
        _joinAll(<String>[
          executableDirectory.path,
          'data',
          'flutter_assets',
          'packages',
          'bdo_fishing_core',
          'assets',
          'fish_companion',
        ]),
      ),
      Directory(
        _joinAll(<String>[
          Directory.current.path,
          'build',
          'unit_test_assets',
          'packages',
          'bdo_fishing_core',
          'assets',
          'fish_companion',
        ]),
      ),
    ];
    for (final candidate in candidates) {
      if (candidate.existsSync()) return candidate;
    }
    throw StateError('The packaged Fish Companion payload is unavailable.');
  }

  Directory _resolveReferenceCacheRoot() {
    final resolved = referenceCacheRoot.absolute;
    _requireSeparateReferenceCache(resolved);
    return resolved;
  }

  Directory _resolveWebViewDataRoot() {
    final resolved = webViewDataRoot.absolute;
    final personal = personalDataRoot.absolute.path;
    if (resolved.path == personal || !_isWithin(resolved.path, personal)) {
      throw StateError(
        'The shared WebView data directory must be beneath the selected '
        'personal-data root.',
      );
    }
    return resolved;
  }

  void _requireSeparateReferenceCache(Directory cache) {
    final personal = personalDataRoot.absolute.path;
    if (_isWithin(cache.path, personal) || _isWithin(personal, cache.path)) {
      throw StateError(
        'The Fish reference cache must be outside the personal-data root.',
      );
    }
  }

  Future<void> _migrateLegacyJournal({
    required File executable,
    required Directory appRoot,
    required File source,
    required File database,
    required FishCompanionStartupCancellation cancellation,
  }) async {
    cancellation.throwIfCanceled();
    final process = await _startManagedProcess(
      executable,
      <String>[
        '--migrate-v017-json',
        source.absolute.path,
        '--database',
        database.absolute.path,
      ],
      workingDirectory: appRoot.path,
      cancellation: cancellation,
    );
    final outputDrains = _ProcessOutputDrains(process);
    Future<void>? termination;
    Future<void> terminateOnce() => termination ??= _terminateProcess(process);
    try {
      cancellation.throwIfCanceled();
      int? exitCode;
      try {
        exitCode = await Future.any<int?>(<Future<int?>>[
          process.exitCode,
          cancellation.whenCanceled.then<int?>((_) => null),
        ]).timeout(const Duration(minutes: 2));
      } on TimeoutException {
        try {
          await terminateOnce();
        } on Object catch (cleanupError, cleanupStackTrace) {
          await _finishOutputDrainsPreservingError(
            outputDrains,
            cleanupError,
            cleanupStackTrace,
          );
        }
        await outputDrains.finish();
        cancellation.throwIfCanceled();
        throw StateError('The legacy Fishing journal migration timed out.');
      }
      if (exitCode == null) throw const FishCompanionStartupCanceled();
      if (isFishCompanionManagedHostCleanupFailedExitCode(exitCode)) {
        await _finishOutputDrainsPreservingError(
          outputDrains,
          FishCompanionManagedHostCleanupFailed(exitCode),
          StackTrace.current,
        );
      }
      await outputDrains.finish();
      cancellation.throwIfCanceled();
      if (exitCode != 0) {
        throw StateError('The legacy Fishing journal could not be migrated.');
      }
    } on FishCompanionStartupCanceled {
      try {
        await terminateOnce();
      } on Object catch (cleanupError, cleanupStackTrace) {
        await _finishOutputDrainsPreservingError(
          outputDrains,
          cleanupError,
          cleanupStackTrace,
        );
      }
      await outputDrains.finish();
      rethrow;
    }
  }

  Future<Process> _startManagedProcess(
    File childExecutable,
    List<String> childArguments, {
    required String workingDirectory,
    required FishCompanionStartupCancellation cancellation,
  }) async {
    cancellation.throwIfCanceled();
    final host =
        managedProcessHostExecutable?.absolute ??
        File(
          _joinAll(<String>[
            File(Platform.resolvedExecutable).parent.path,
            'BlackSpiritLifeFishHost.exe',
          ]),
        ).absolute;
    final hostExists = await host.exists();
    cancellation.throwIfCanceled();
    if (!hostExists) {
      throw StateError('The Fish Companion process host is unavailable.');
    }
    try {
      return await _managedProcessStarter(host.path, <String>[
        '--owner-pid',
        '$pid',
        '--',
        childExecutable.absolute.path,
        ...childArguments,
      ], workingDirectory: workingDirectory);
    } on Object {
      cancellation.throwIfCanceled();
      throw StateError('The Fish Companion managed process could not start.');
    }
  }

  static Future<void> _rejectPersonalJournalPayload(
    Directory packagedRoot,
    FishCompanionStartupCancellation cancellation,
  ) async {
    cancellation.throwIfCanceled();
    final iterator = StreamIterator<FileSystemEntity>(
      packagedRoot.list(recursive: true, followLinks: false),
    );
    try {
      while (await _moveNextOrCanceled(iterator, cancellation)) {
        final entity = iterator.current;
        if (entity is! File) continue;
        final relative = _relativePath(packagedRoot.path, entity.path);
        if (_isPersonalJournal(relative)) {
          throw StateError(
            'The packaged Fish Companion payload contains personal journal '
            'data.',
          );
        }
      }
    } finally {
      await iterator.cancel();
    }
  }

  static Future<_CriticalManifest> _loadCriticalManifest(
    Directory packagedRoot,
    FishCompanionStartupCancellation cancellation,
  ) async {
    try {
      final file = _fileAt(packagedRoot, _criticalManifestRelativePath);
      final decoded = jsonDecode(
        utf8.decode(await _readFileBytes(file, cancellation)),
      );
      if (decoded is! Map<String, dynamic> || decoded['schemaVersion'] != 1) {
        throw const FormatException('unsupported schema');
      }
      final immutable = _parseIntegrityRecords(
        decoded['immutableFiles'],
        _requiredImmutableCriticalPaths,
      );
      final snapshot = _parseIntegrityRecords(
        decoded['snapshotFiles'],
        _requiredSnapshotCriticalPaths,
      );
      return _CriticalManifest(
        immutableFiles: immutable,
        snapshotFiles: snapshot,
      );
    } on FishCompanionStartupCanceled {
      rethrow;
    } on Object {
      throw StateError(
        'The packaged Fish Companion integrity manifest is invalid.',
      );
    }
  }

  static List<_IntegrityRecord> _parseIntegrityRecords(
    Object? value,
    List<String> requiredPaths,
  ) {
    if (value is! List<Object?>) {
      throw const FormatException('records must be a list');
    }
    final records = <_IntegrityRecord>[];
    final seen = <String>{};
    final hashPattern = RegExp(r'^[0-9a-f]{64}$');
    for (final entry in value) {
      if (entry is! Map<String, dynamic>) {
        throw const FormatException('record must be an object');
      }
      final path = entry['path'];
      final byteCount = entry['byteCount'];
      final digest = entry['sha256'];
      if (path is! String ||
          !_isSafeManifestPath(path) ||
          byteCount is! int ||
          byteCount < 0 ||
          digest is! String ||
          !hashPattern.hasMatch(digest) ||
          !seen.add(path)) {
        throw const FormatException('invalid integrity record');
      }
      records.add(
        _IntegrityRecord(path: path, byteCount: byteCount, sha256: digest),
      );
    }
    records.sort((left, right) => left.path.compareTo(right.path));
    final actualPaths = records.map((record) => record.path).toList();
    final expectedPaths = List<String>.of(requiredPaths)..sort();
    if (!_sameStrings(actualPaths, expectedPaths)) {
      throw const FormatException('critical path set does not match');
    }
    return records;
  }

  static bool _isSafeManifestPath(String path) {
    if (path.isEmpty ||
        path.startsWith('/') ||
        path.contains(r'\') ||
        path.contains(':')) {
      return false;
    }
    final parts = path.split('/');
    return parts.every(
      (part) => part.isNotEmpty && part != '.' && part != '..',
    );
  }

  static bool _sameStrings(List<String> left, List<String> right) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (left[index] != right[index]) return false;
    }
    return true;
  }

  static Future<void> _verifyPackagedCriticalFiles(
    Directory packagedRoot,
    _CriticalManifest manifest,
    FishCompanionStartupCancellation cancellation,
  ) async {
    final mismatches = await _recordMismatches(packagedRoot, <_IntegrityRecord>[
      ...manifest.immutableFiles,
      ...manifest.snapshotFiles,
    ], cancellation);
    if (mismatches.isNotEmpty) {
      throw StateError('The packaged Fish Companion payload is incomplete.');
    }
  }

  static Future<List<_IntegrityRecord>> _recordMismatches(
    Directory root,
    List<_IntegrityRecord> records,
    FishCompanionStartupCancellation cancellation,
  ) async {
    final mismatches = <_IntegrityRecord>[];
    for (final record in records) {
      cancellation.throwIfCanceled();
      final file = _fileAt(root, record.path);
      try {
        final exists = await file.exists();
        cancellation.throwIfCanceled();
        if (!exists) {
          mismatches.add(record);
          continue;
        }
        final stat = await file.stat();
        cancellation.throwIfCanceled();
        if (stat.type != FileSystemEntityType.file ||
            stat.size != record.byteCount) {
          mismatches.add(record);
          continue;
        }
        final digest = await _hashFile(file, cancellation);
        if (digest.toString() != record.sha256) mismatches.add(record);
      } on FileSystemException {
        mismatches.add(record);
      }
    }
    return mismatches;
  }

  static Future<List<int>> _readFileBytes(
    File file,
    FishCompanionStartupCancellation cancellation,
  ) async {
    final bytes = BytesBuilder(copy: false);
    final iterator = StreamIterator<List<int>>(file.openRead());
    try {
      while (await _moveNextOrCanceled(iterator, cancellation)) {
        bytes.add(iterator.current);
      }
      cancellation.throwIfCanceled();
      return bytes.takeBytes();
    } finally {
      await iterator.cancel();
    }
  }

  static Future<Digest> _hashFile(
    File file,
    FishCompanionStartupCancellation cancellation,
  ) async {
    final digestSink = _SingleDigestSink();
    final inputSink = sha256.startChunkedConversion(digestSink);
    final iterator = StreamIterator<List<int>>(file.openRead());
    var inputClosed = false;
    try {
      while (await _moveNextOrCanceled(iterator, cancellation)) {
        inputSink.add(iterator.current);
      }
      cancellation.throwIfCanceled();
      inputSink.close();
      inputClosed = true;
      return digestSink.value;
    } finally {
      await iterator.cancel();
      if (!inputClosed) inputSink.close();
    }
  }

  static Future<bool> _moveNextOrCanceled<T>(
    StreamIterator<T> iterator,
    FishCompanionStartupCancellation cancellation,
  ) async {
    cancellation.throwIfCanceled();
    final canceled = Completer<void>();
    final removeCancellationListener = cancellation._addListener(() {
      if (!canceled.isCompleted) canceled.complete();
    });
    try {
      final moved = iterator.moveNext();
      final result = await Future.any<({bool canceled, bool hasNext})>(
        <Future<({bool canceled, bool hasNext})>>[
          moved.then((hasNext) => (canceled: false, hasNext: hasNext)),
          canceled.future.then((_) => (canceled: true, hasNext: false)),
        ],
      );
      if (result.canceled) throw const FishCompanionStartupCanceled();
      cancellation.throwIfCanceled();
      return result.hasNext;
    } finally {
      removeCancellationListener();
    }
  }

  static File _fileAt(Directory root, String relative) =>
      File(_joinAll(<String>[root.path, ...relative.split('/')]));

  static bool _isPersonalJournal(String relative) {
    final normalized = relative.replaceAll(r'\', '/').toLowerCase();
    return normalized
        .split('/')
        .any((component) => component.contains('fish-journal'));
  }

  static String _relativePath(String root, String path) {
    if (path.length <= root.length) return '';
    var relative = path.substring(root.length);
    while (relative.startsWith(Platform.pathSeparator)) {
      relative = relative.substring(1);
    }
    return relative;
  }

  static bool _isWithin(String candidate, String parent) {
    var child = Directory(candidate).absolute.path.toLowerCase();
    var root = Directory(parent).absolute.path.toLowerCase();
    while (child.endsWith(Platform.pathSeparator)) {
      child = child.substring(0, child.length - 1);
    }
    while (root.endsWith(Platform.pathSeparator)) {
      root = root.substring(0, root.length - 1);
    }
    return child == root || child.startsWith('$root${Platform.pathSeparator}');
  }

  static Future<int> _availablePort(
    FishCompanionStartupCancellation cancellation,
  ) async {
    for (var port = 8765; port <= 8795; port++) {
      cancellation.throwIfCanceled();
      try {
        final socket = await ServerSocket.bind(
          InternetAddress.loopbackIPv4,
          port,
          shared: false,
        );
        try {
          cancellation.throwIfCanceled();
          return port;
        } finally {
          await socket.close();
        }
      } on SocketException {
        continue;
      }
    }
    throw StateError('No localhost port is available for Fish Companion.');
  }

  static String _generateApiToken() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  static Future<void> _waitUntilHealthy(
    Uri healthUri,
    String apiToken,
    Process process,
    FishCompanionStartupCancellation cancellation,
  ) async {
    cancellation.throwIfCanceled();
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
    final canceled = Completer<void>();
    final removeCancellationListener = cancellation._addListener(() {
      client.close(force: true);
      if (!canceled.isCompleted) canceled.complete();
    });
    try {
      final result =
          await Future.any<_HealthWaitResult>(<Future<_HealthWaitResult>>[
            _pollUntilHealthy(
              client,
              healthUri,
              apiToken,
              cancellation,
            ).then((_) => const _HealthWaitResult.healthy()),
            process.exitCode.then(_HealthWaitResult.exited),
            canceled.future.then((_) => const _HealthWaitResult.canceled()),
          ]);
      if (result.canceled) throw const FishCompanionStartupCanceled();
      if (result.exitCode case final exitCode?) {
        throw _FishCompanionServiceExitedBeforeHealth(exitCode);
      }
    } finally {
      removeCancellationListener();
      client.close(force: true);
    }
  }

  static Future<void> _pollUntilHealthy(
    HttpClient client,
    Uri healthUri,
    String apiToken,
    FishCompanionStartupCancellation cancellation,
  ) async {
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    while (DateTime.now().isBefore(deadline)) {
      cancellation.throwIfCanceled();
      try {
        final request = await client
            .getUrl(healthUri)
            .timeout(const Duration(seconds: 2));
        request.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
        request.headers.set(_apiTokenHeader, apiToken);
        final response = await request.close().timeout(
          const Duration(seconds: 2),
        );
        await response.drain<void>().timeout(const Duration(seconds: 2));
        if (response.statusCode == HttpStatus.ok) return;
      } on Object catch (error) {
        cancellation.throwIfCanceled();
        if (error is! SocketException &&
            error is! HttpException &&
            error is! TimeoutException) {
          rethrow;
        }
        // The self-contained service is still unpacking or starting.
      }
      await _delayOrCanceled(const Duration(milliseconds: 150), cancellation);
    }
    throw StateError('Fish Companion could not start its local service.');
  }

  static Future<void> _delayOrCanceled(
    Duration duration,
    FishCompanionStartupCancellation cancellation,
  ) async {
    cancellation.throwIfCanceled();
    final canceled = Completer<void>();
    final removeCancellationListener = cancellation._addListener(() {
      if (!canceled.isCompleted) canceled.complete();
    });
    try {
      await Future.any<void>(<Future<void>>[
        Future<void>.delayed(duration),
        canceled.future,
      ]);
      cancellation.throwIfCanceled();
    } finally {
      removeCancellationListener();
    }
  }

  static Future<void> _terminateProcess(Process process) async {
    try {
      final exitCode = await process.exitCode.timeout(Duration.zero);
      _throwIfFishCompanionManagedHostCleanupFailed(exitCode);
      return;
    } on TimeoutException {
      // The direct process is still live, so its Windows child tree can be
      // terminated without risking a later PID-reuse lookup.
    }
    if (Platform.isWindows) {
      try {
        final systemRoot = Platform.environment['SystemRoot'];
        final taskkill = systemRoot == null || systemRoot.trim().isEmpty
            ? 'taskkill'
            : _joinAll(<String>[systemRoot, 'System32', 'taskkill.exe']);
        final killer = await Process.start(taskkill, <String>[
          '/PID',
          '${process.pid}',
          '/T',
          '/F',
        ]);
        final killerOutputDrains = _ProcessOutputDrains(killer);
        int exitCode;
        try {
          exitCode = await killer.exitCode.timeout(const Duration(seconds: 3));
        } on TimeoutException {
          killer.kill();
          try {
            await killer.exitCode.timeout(const Duration(seconds: 1));
          } on TimeoutException {
            // The direct process fallback below remains bounded.
          }
          exitCode = -1;
        }
        await killerOutputDrains.finish();
        if (exitCode != 0) process.kill();
      } on Object {
        process.kill();
      }
    } else {
      process.kill();
    }
    try {
      final exitCode = await process.exitCode.timeout(
        const Duration(seconds: 3),
      );
      _throwIfFishCompanionManagedHostCleanupFailed(exitCode);
    } on TimeoutException {
      process.kill(ProcessSignal.sigkill);
      try {
        final exitCode = await process.exitCode.timeout(
          const Duration(seconds: 3),
        );
        _throwIfFishCompanionManagedHostCleanupFailed(exitCode);
      } on TimeoutException {
        throw const FishCompanionManagedHostCleanupFailed();
      }
    }
  }

  static Future<void> _finishOutputDrainsPreservingError(
    _ProcessOutputDrains outputDrains,
    Object primaryError,
    StackTrace primaryStackTrace,
  ) async {
    try {
      await outputDrains.finish();
    } on Object {
      // A pipe-drain failure must never mask an already established process
      // cleanup failure, especially the sticky cleanup-unproven state.
    }
    Error.throwWithStackTrace(primaryError, primaryStackTrace);
  }
}

class _CriticalManifest {
  const _CriticalManifest({
    required this.immutableFiles,
    required this.snapshotFiles,
  });

  final List<_IntegrityRecord> immutableFiles;
  final List<_IntegrityRecord> snapshotFiles;
}

class _IntegrityRecord {
  const _IntegrityRecord({
    required this.path,
    required this.byteCount,
    required this.sha256,
  });

  final String path;
  final int byteCount;
  final String sha256;
}

final class _SingleDigestSink implements Sink<Digest> {
  Digest? _value;

  Digest get value {
    final result = _value;
    if (result == null) throw StateError('The file digest was not produced.');
    return result;
  }

  @override
  void add(Digest data) => _value = data;

  @override
  void close() {}
}

final class _HealthWaitResult {
  const _HealthWaitResult.healthy() : canceled = false, exitCode = null;
  const _HealthWaitResult.canceled() : canceled = true, exitCode = null;
  const _HealthWaitResult.exited(this.exitCode) : canceled = false;

  final bool canceled;
  final int? exitCode;
}

final class _FishCompanionStartupCleanupTimedOut implements Exception {
  const _FishCompanionStartupCleanupTimedOut();
}

final class _FishCompanionServiceExitedBeforeHealth implements Exception {
  const _FishCompanionServiceExitedBeforeHealth(
    this.exitCode, {
    this.stdoutCapturedByteCount = 0,
    this.stdoutByteCount = 0,
    this.stderrCapturedByteCount = 0,
    this.stderrByteCount = 0,
  });

  final int exitCode;
  final int stdoutCapturedByteCount;
  final int stdoutByteCount;
  final int stderrCapturedByteCount;
  final int stderrByteCount;

  _FishCompanionServiceExitedBeforeHealth withOutput(
    _ProcessOutputDrains output,
  ) => _FishCompanionServiceExitedBeforeHealth(
    exitCode,
    stdoutCapturedByteCount: output.stdoutCapturedByteCount,
    stdoutByteCount: output.stdoutByteCount,
    stderrCapturedByteCount: output.stderrCapturedByteCount,
    stderrByteCount: output.stderrByteCount,
  );

  @override
  String toString() =>
      'Fish Companion exited before its local service became ready '
      '(exit code $exitCode; captured stdout '
      '$stdoutCapturedByteCount/$stdoutByteCount bytes, stderr '
      '$stderrCapturedByteCount/$stderrByteCount bytes). Try Fish Map again.';
}

final class _BoundedByteCapture {
  static const int _limit = 32 * 1024;

  final BytesBuilder _captured = BytesBuilder(copy: false);
  int totalByteCount = 0;

  int get capturedByteCount => _captured.length;

  void add(List<int> bytes) {
    totalByteCount += bytes.length;
    final remaining = _limit - _captured.length;
    if (remaining <= 0) return;
    _captured.add(
      bytes.length <= remaining ? bytes : bytes.sublist(0, remaining),
    );
  }
}

final class _ProcessOutputDrains {
  factory _ProcessOutputDrains(Process process) {
    final stdoutCapture = _BoundedByteCapture();
    final stderrCapture = _BoundedByteCapture();
    final stdoutDone = Completer<void>();
    final stderrDone = Completer<void>();

    void complete(Completer<void> completer) {
      if (!completer.isCompleted) completer.complete();
    }

    // The returned owner cancels this subscription if the child does not
    // close its pipe after process termination.
    // ignore: cancel_subscriptions
    final stdoutSubscription = process.stdout.listen(
      stdoutCapture.add,
      onError: (Object _, StackTrace _) => complete(stdoutDone),
      onDone: () => complete(stdoutDone),
      cancelOnError: true,
    );
    // ignore: cancel_subscriptions
    final stderrSubscription = process.stderr.listen(
      stderrCapture.add,
      onError: (Object _, StackTrace _) => complete(stderrDone),
      onDone: () => complete(stderrDone),
      cancelOnError: true,
    );
    return _ProcessOutputDrains._(
      stdoutCapture,
      stderrCapture,
      stdoutDone.future,
      stderrDone.future,
      stdoutSubscription,
      stderrSubscription,
    );
  }

  _ProcessOutputDrains._(
    this._stdout,
    this._stderr,
    this._stdoutDone,
    this._stderrDone,
    this._stdoutSubscription,
    this._stderrSubscription,
  );

  final _BoundedByteCapture _stdout;
  final _BoundedByteCapture _stderr;
  final Future<void> _stdoutDone;
  final Future<void> _stderrDone;
  final StreamSubscription<List<int>> _stdoutSubscription;
  final StreamSubscription<List<int>> _stderrSubscription;
  Future<void>? _finished;

  int get stdoutCapturedByteCount => _stdout.capturedByteCount;
  int get stdoutByteCount => _stdout.totalByteCount;
  int get stderrCapturedByteCount => _stderr.capturedByteCount;
  int get stderrByteCount => _stderr.totalByteCount;

  Future<void> finish() => _finished ??= _finish();

  Future<void> _finish() async {
    try {
      await Future.wait<void>(<Future<void>>[
        _stdoutDone,
        _stderrDone,
      ]).timeout(const Duration(seconds: 3));
    } on TimeoutException {
      await Future.wait<void>(<Future<void>>[
        _stdoutSubscription.cancel(),
        _stderrSubscription.cancel(),
      ]);
    }
  }
}

class FishCompanionRuntimeHandle implements FishCompanionServiceHandle {
  FishCompanionRuntimeHandle._(
    this._apiToken, {
    required this.process,
    required this._outputDrains,
    required this.root,
    required this.personalDataRoot,
    required this.webViewDataRoot,
    required this.uri,
  });

  final Process process;
  @override
  final Directory root;
  @override
  final Directory personalDataRoot;
  @override
  final Directory webViewDataRoot;
  @override
  final Uri uri;
  final String _apiToken;
  final _ProcessOutputDrains _outputDrains;

  Future<void>? _shutdown;

  @override
  Future<void> checkpoint() async {
    if (_shutdown != null) {
      await _shutdown;
      return;
    }
    await _postControl(uri.resolve('/api/checkpoint'), _apiToken);
  }

  @override
  Future<void> shutdown() {
    final existing = _shutdown;
    if (existing != null) return existing;
    final operation = _shutdownGracefully();
    late final Future<void> tracked;
    tracked = operation.then<void>(
      (_) {},
      onError: (Object error, StackTrace stackTrace) {
        if (identical(_shutdown, tracked)) _shutdown = null;
        Error.throwWithStackTrace(error, stackTrace);
      },
    );
    _shutdown = tracked;
    return tracked;
  }

  Future<void> _shutdownGracefully() async {
    Object? primaryError;
    StackTrace? primaryStackTrace;
    try {
      try {
        await _postControl(uri.resolve('/api/shutdown'), _apiToken);
      } on Object {
        // A service which already exited needs no additional checkpoint.
      }
      try {
        final exitCode = await process.exitCode.timeout(
          const Duration(seconds: 6),
        );
        _throwIfFishCompanionManagedHostCleanupFailed(exitCode);
      } on TimeoutException {
        await FishCompanionRuntime._terminateProcess(process);
      }
    } on Object catch (error, stackTrace) {
      primaryError = error;
      primaryStackTrace = stackTrace;
    }
    try {
      await _outputDrains.finish();
    } on Object catch (error, stackTrace) {
      primaryError ??= error;
      primaryStackTrace ??= stackTrace;
    }
    if (primaryError != null) {
      Error.throwWithStackTrace(primaryError, primaryStackTrace!);
    }
  }

  static Future<void> _postControl(Uri target, String apiToken) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
    try {
      final request = await client.postUrl(target);
      request.headers.set(_apiTokenHeader, apiToken);
      request.contentLength = 0;
      final response = await request.close().timeout(
        const Duration(seconds: 3),
      );
      await response.drain<void>();
      if (response.statusCode != HttpStatus.ok) {
        throw StateError('Fish Companion rejected a lifecycle request.');
      }
    } finally {
      client.close(force: true);
    }
  }

  @override
  void dispose() {
    unawaited(shutdown());
  }
}

String _join(String left, String right) {
  if (left.endsWith(Platform.pathSeparator)) return '$left$right';
  return '$left${Platform.pathSeparator}$right';
}

String _joinAll(List<String> parts) {
  var result = parts.first;
  for (final part in parts.skip(1)) {
    result = _join(result, part);
  }
  return result;
}
