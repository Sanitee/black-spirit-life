part of 'node_network_optimizer.dart';

/// A generation-tagged result returned by [BdoNodeNetworkWorker].
///
/// Callers that submit a newer request before an older request finishes must
/// compare [generation] with their latest generation before showing [result].
/// Requests execute sequentially in the worker isolate. The plan's
/// optimization mode distinguishes globally exact and scalable results.
class BdoNodeNetworkWorkerResponse {
  const BdoNodeNetworkWorkerResponse({
    required this.requestId,
    required this.generation,
    required this.result,
  });

  /// Monotonically increasing ID assigned by this worker instance.
  final int requestId;

  /// Caller-provided generation used to reject stale UI results.
  final int generation;

  final BdoNodeNetworkResult result;

  bool belongsToGeneration(int currentGeneration) =>
      generation == currentGeneration;
}

/// A deterministic worker lifecycle or remote-execution failure.
class BdoNodeNetworkWorkerException implements Exception {
  const BdoNodeNetworkWorkerException(
    this.message, {
    this.remoteStackTrace,
    this.requestId,
    this.generation,
  });

  final String message;
  final String? remoteStackTrace;
  final int? requestId;
  final int? generation;

  @override
  String toString() => 'BdoNodeNetworkWorkerException: $message';
}

/// Thrown when work is submitted after [BdoNodeNetworkWorker.dispose].
class BdoNodeNetworkWorkerDisposedException
    extends BdoNodeNetworkWorkerException {
  const BdoNodeNetworkWorkerDisposedException()
    : super('The node-network worker has been disposed.');
}

/// Long-lived native isolate for worker-node network optimization.
///
/// [start] transfers the dataset's worker resources and nodes once, without
/// copying unrelated gathering-point/map payloads, and prepares the normalized
/// graph inside the isolate. Every [optimize] call then reuses that graph.
/// Requests are processed in submission order. The UI should increase its own
/// generation for each changed request and only apply a response whose
/// [BdoNodeNetworkWorkerResponse.generation] is still current.
///
/// This class uses `dart:isolate` and is intended for native Dart/Flutter VM
/// targets such as Windows. Always call [dispose] from the owning widget or
/// service.
class BdoNodeNetworkWorker {
  BdoNodeNetworkWorker._() {
    _eventSubscription = _events.listen(_handleEvent);
  }

  /// Starts a worker and waits until its dataset graph is prepared.
  static Future<BdoNodeNetworkWorker> start(
    BdoResourceMapDataset data, {
    String debugName = 'bdo-node-network-worker',
  }) async {
    final worker = BdoNodeNetworkWorker._();
    try {
      worker._isolate = await Isolate.spawn<_NodeNetworkWorkerBootstrap>(
        _nodeNetworkWorkerMain,
        _NodeNetworkWorkerBootstrap(
          responsePort: worker._events.sendPort,
          resources: List<BdoResourceDefinition>.of(
            data.resources,
            growable: false,
          ),
          workerNodes: List<BdoWorkerNode>.of(
            data.workerNodes,
            growable: false,
          ),
        ),
        onError: worker._events.sendPort,
        onExit: worker._events.sendPort,
        errorsAreFatal: true,
        debugName: debugName,
      );
      await worker._ready.future;
      final failure = worker._terminalFailure;
      if (failure != null) {
        throw failure;
      }
      return worker;
    } catch (error, stackTrace) {
      await worker._abortStartup();
      final failure = error is BdoNodeNetworkWorkerException
          ? error
          : BdoNodeNetworkWorkerException(
              'Could not start the node-network worker: $error',
            );
      Error.throwWithStackTrace(failure, stackTrace);
    }
  }

  final ReceivePort _events = ReceivePort();
  final Completer<void> _ready = Completer<void>();
  final Completer<void> _exited = Completer<void>();
  final Map<int, _PendingNodeNetworkJob> _pending =
      <int, _PendingNodeNetworkJob>{};

  late final StreamSubscription<Object?> _eventSubscription;

  Isolate? _isolate;
  SendPort? _commandPort;
  BdoNodeNetworkWorkerException? _terminalFailure;
  Future<void>? _disposeFuture;
  Future<void>? _closePortsFuture;
  var _nextRequestId = 0;

  bool get isDisposed => _disposeFuture != null;

  bool get isRunning =>
      !isDisposed && _terminalFailure == null && _commandPort != null;

  /// Queues one optimization request in the worker isolate.
  ///
  /// [generation] is echoed in the response; it does not cancel older work.
  /// Compare it with the latest UI generation before applying the result.
  Future<BdoNodeNetworkWorkerResponse> optimize({
    required BdoNodeNetworkRequest request,
    required int generation,
  }) {
    if (isDisposed) {
      return Future<BdoNodeNetworkWorkerResponse>.error(
        const BdoNodeNetworkWorkerDisposedException(),
      );
    }
    final terminalFailure = _terminalFailure;
    if (terminalFailure != null) {
      return Future<BdoNodeNetworkWorkerResponse>.error(terminalFailure);
    }
    final commandPort = _commandPort;
    if (commandPort == null) {
      return Future<BdoNodeNetworkWorkerResponse>.error(
        const BdoNodeNetworkWorkerException(
          'The node-network worker is not ready.',
        ),
      );
    }

    final requestId = ++_nextRequestId;
    final completer = Completer<BdoNodeNetworkWorkerResponse>();
    _pending[requestId] = _PendingNodeNetworkJob(
      generation: generation,
      completer: completer,
    );
    try {
      commandPort.send(
        _NodeNetworkOptimizeCommand(
          requestId: requestId,
          generation: generation,
          request: request,
        ),
      );
    } catch (error, stackTrace) {
      _pending.remove(requestId);
      completer.completeError(
        BdoNodeNetworkWorkerException(
          'Could not send request $requestId to the worker: $error',
          requestId: requestId,
          generation: generation,
        ),
        stackTrace,
      );
    }
    return completer.future;
  }

  /// Immediately stops the isolate and rejects all unfinished requests.
  ///
  /// Disposal is idempotent. A currently running search is cancelled by
  /// terminating its isolate, so widget teardown never waits for a large job.
  Future<void> dispose() => _disposeFuture ??= _dispose();

  void _handleEvent(Object? event) {
    if (event == null) {
      _handleIsolateExit();
      return;
    }
    if (event is List) {
      _handleIsolateError(event);
      return;
    }
    _handleMessage(event);
  }

  void _handleMessage(Object? message) {
    switch (message) {
      case _NodeNetworkWorkerReady(:final commandPort):
        if (isDisposed || _terminalFailure != null) {
          return;
        }
        if (_commandPort != null || _ready.isCompleted) {
          _failTerminal(
            const BdoNodeNetworkWorkerException(
              'The worker sent more than one ready message.',
            ),
            StackTrace.current,
          );
          return;
        }
        _commandPort = commandPort;
        _ready.complete();
      case _NodeNetworkWorkerSuccess(
        :final requestId,
        :final generation,
        :final result,
      ):
        final pending = _pending[requestId];
        if (pending == null) {
          _handleUnknownResponse(requestId);
          return;
        }
        if (pending.generation != generation) {
          _failTerminal(
            BdoNodeNetworkWorkerException(
              'Request $requestId returned generation $generation instead of '
              '${pending.generation}.',
              requestId: requestId,
              generation: generation,
            ),
            StackTrace.current,
          );
          return;
        }
        _pending.remove(requestId);
        if (!pending.completer.isCompleted) {
          pending.completer.complete(
            BdoNodeNetworkWorkerResponse(
              requestId: requestId,
              generation: generation,
              result: result,
            ),
          );
        }
      case _NodeNetworkWorkerFailure(
        :final requestId,
        :final generation,
        :final error,
        :final stackTrace,
      ):
        final pending = _pending[requestId];
        if (pending == null) {
          _handleUnknownResponse(requestId);
          return;
        }
        if (pending.generation != generation) {
          _failTerminal(
            BdoNodeNetworkWorkerException(
              'Failed request $requestId returned generation $generation '
              'instead of ${pending.generation}.',
              requestId: requestId,
              generation: generation,
            ),
            StackTrace.current,
          );
          return;
        }
        _pending.remove(requestId);
        if (!pending.completer.isCompleted) {
          pending.completer.completeError(
            BdoNodeNetworkWorkerException(
              'Request $requestId failed in the worker: $error',
              remoteStackTrace: stackTrace,
              requestId: requestId,
              generation: generation,
            ),
            StackTrace.fromString(stackTrace),
          );
        }
      case _NodeNetworkWorkerStartupFailure(:final error, :final stackTrace):
        _failTerminal(
          BdoNodeNetworkWorkerException(
            'The worker could not prepare the dataset: $error',
            remoteStackTrace: stackTrace,
          ),
          StackTrace.fromString(stackTrace),
        );
      default:
        _failTerminal(
          BdoNodeNetworkWorkerException(
            'The worker sent an unsupported message: '
            '${message.runtimeType}.',
          ),
          StackTrace.current,
        );
    }
  }

  void _handleUnknownResponse(int requestId) {
    if (isDisposed) {
      return;
    }
    _failTerminal(
      BdoNodeNetworkWorkerException(
        'The worker returned unknown or duplicate request ID $requestId.',
        requestId: requestId,
      ),
      StackTrace.current,
    );
  }

  void _handleIsolateError(Object? message) {
    final (error, stackTrace) = switch (message) {
      [final Object? error, final Object? stackTrace, ...] => (
        '$error',
        '$stackTrace',
      ),
      _ => ('$message', ''),
    };
    _failTerminal(
      BdoNodeNetworkWorkerException(
        'The worker isolate terminated with an error: $error',
        remoteStackTrace: stackTrace,
      ),
      StackTrace.fromString(stackTrace),
    );
  }

  void _handleIsolateExit() {
    if (!_exited.isCompleted) {
      _exited.complete();
    }
    if (isDisposed) {
      unawaited(_closePorts());
      return;
    }
    if (_terminalFailure == null) {
      _failTerminal(
        const BdoNodeNetworkWorkerException(
          'The worker isolate exited unexpectedly.',
        ),
        StackTrace.current,
      );
    }
    unawaited(_closePorts());
  }

  void _failTerminal(
    BdoNodeNetworkWorkerException failure,
    StackTrace stackTrace,
  ) {
    _terminalFailure ??= failure;
    _commandPort = null;
    _isolate?.kill(priority: Isolate.immediate);
    if (!_ready.isCompleted) {
      _ready.completeError(failure, stackTrace);
    }
    for (final pending in _pending.values) {
      if (!pending.completer.isCompleted) {
        pending.completer.completeError(failure, stackTrace);
      }
    }
    _pending.clear();
  }

  Future<void> _abortStartup() async {
    _isolate?.kill(priority: Isolate.immediate);
    await _closePorts();
  }

  Future<void> _dispose() async {
    _commandPort = null;
    const failure = BdoNodeNetworkWorkerDisposedException();
    for (final pending in _pending.values) {
      if (!pending.completer.isCompleted) {
        pending.completer.completeError(failure);
      }
    }
    _pending.clear();

    final isolate = _isolate;
    if (isolate != null && !_exited.isCompleted) {
      isolate.kill(priority: Isolate.immediate);
    }
    await _closePorts();
  }

  Future<void> _closePorts() => _closePortsFuture ??= _closePortsOnce();

  Future<void> _closePortsOnce() async {
    _events.close();
    await _eventSubscription.cancel();
  }
}

class _PendingNodeNetworkJob {
  const _PendingNodeNetworkJob({
    required this.generation,
    required this.completer,
  });

  final int generation;
  final Completer<BdoNodeNetworkWorkerResponse> completer;
}

class _NodeNetworkWorkerBootstrap {
  const _NodeNetworkWorkerBootstrap({
    required this.responsePort,
    required this.resources,
    required this.workerNodes,
  });

  final SendPort responsePort;
  final List<BdoResourceDefinition> resources;
  final List<BdoWorkerNode> workerNodes;
}

class _NodeNetworkWorkerReady {
  const _NodeNetworkWorkerReady(this.commandPort);

  final SendPort commandPort;
}

class _NodeNetworkOptimizeCommand {
  const _NodeNetworkOptimizeCommand({
    required this.requestId,
    required this.generation,
    required this.request,
  });

  final int requestId;
  final int generation;
  final BdoNodeNetworkRequest request;
}

class _NodeNetworkWorkerSuccess {
  const _NodeNetworkWorkerSuccess({
    required this.requestId,
    required this.generation,
    required this.result,
  });

  final int requestId;
  final int generation;
  final BdoNodeNetworkResult result;
}

class _NodeNetworkWorkerFailure {
  const _NodeNetworkWorkerFailure({
    required this.requestId,
    required this.generation,
    required this.error,
    required this.stackTrace,
  });

  final int requestId;
  final int generation;
  final String error;
  final String stackTrace;
}

class _NodeNetworkWorkerStartupFailure {
  const _NodeNetworkWorkerStartupFailure({
    required this.error,
    required this.stackTrace,
  });

  final String error;
  final String stackTrace;
}

@pragma('vm:entry-point')
void _nodeNetworkWorkerMain(_NodeNetworkWorkerBootstrap bootstrap) {
  final commands = ReceivePort();
  late final _PreparedNodeNetworkOptimizer optimizer;
  try {
    optimizer = _PreparedNodeNetworkOptimizer.fromNetworkData(
      resources: bootstrap.resources,
      workerNodes: bootstrap.workerNodes,
    );
    commands.listen((message) {
      if (message case _NodeNetworkOptimizeCommand(
        :final requestId,
        :final generation,
        :final request,
      )) {
        try {
          final result = optimizer.optimize(request);
          bootstrap.responsePort.send(
            _NodeNetworkWorkerSuccess(
              requestId: requestId,
              generation: generation,
              result: result,
            ),
          );
        } catch (error, stackTrace) {
          bootstrap.responsePort.send(
            _NodeNetworkWorkerFailure(
              requestId: requestId,
              generation: generation,
              error: '$error',
              stackTrace: '$stackTrace',
            ),
          );
        }
      }
    });
    bootstrap.responsePort.send(_NodeNetworkWorkerReady(commands.sendPort));
  } catch (error, stackTrace) {
    commands.listen((_) {});
    bootstrap.responsePort.send(
      _NodeNetworkWorkerStartupFailure(
        error: '$error',
        stackTrace: '$stackTrace',
      ),
    );
  }
}
