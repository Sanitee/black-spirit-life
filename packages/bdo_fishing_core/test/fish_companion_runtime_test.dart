import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bdo_fishing_core/bdo_fishing_core.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FishCompanionRuntimeHost', () {
    test('shares startup and gracefully shuts down once', () async {
      final started = Completer<FishCompanionServiceHandle>();
      final handle = _FakeFishCompanionServiceHandle();
      var startCount = 0;
      final host = FishCompanionRuntimeHost.withStarter((_) {
        startCount += 1;
        return started.future;
      });

      final warming = host.prewarm();
      final first = host.ready();
      final second = host.ready();
      expect(identical(first, second), isTrue);
      expect(startCount, 1);

      started.complete(handle);
      await warming;
      expect(await first, same(handle));
      expect(await second, same(handle));
      await host.shutdown();
      await host.shutdown();
      expect(handle.shutdownCount, 1);
      expect(handle.disposeCount, 0);
      await expectLater(host.ready(), throwsStateError);
    });

    test('failed prewarm remains retryable', () async {
      final handle = _FakeFishCompanionServiceHandle();
      var startCount = 0;
      final host = FishCompanionRuntimeHost(
        personalDataRoot: Directory('unused-host-fixture'),
        referenceCacheRoot: Directory('unused-reference-fixture'),
        webViewDataRoot: Directory('unused-host-fixture/webview2'),
        starter: (_) async {
          startCount += 1;
          if (startCount == 1) throw StateError('fixture startup failure');
          return handle;
        },
      );
      addTearDown(host.shutdown);

      await host.prewarm();
      expect(startCount, 1);
      expect(await host.ready(), same(handle));
      expect(startCount, 2);
    });

    test('freeze during startup closes the eventual service', () async {
      final started = Completer<FishCompanionServiceHandle>();
      final handle = _FakeFishCompanionServiceHandle();
      final host = FishCompanionRuntimeHost.withStarter((_) => started.future);

      final ready = host.ready();
      final frozen = host.freezeAndFlush();
      started.complete(handle);

      await frozen;
      await expectLater(ready, throwsStateError);
      expect(handle.shutdownCount, 1);
      await host.shutdown();
    });

    test('freeze cooperatively cancels a startup waiting forever', () async {
      final cancellationObserved = Completer<void>();
      final host = FishCompanionRuntimeHost.withStarter((cancellation) async {
        await cancellation.whenCanceled;
        cancellationObserved.complete();
        cancellation.throwIfCanceled();
        throw StateError('unreachable');
      });

      final ready = host.ready();
      final readyFailure = expectLater(
        ready,
        throwsA(isA<FishCompanionStartupCanceled>()),
      );
      await host.freezeAndFlush().timeout(const Duration(seconds: 1));

      await cancellationObserved.future;
      await readyFailure;
      await host.shutdown();
    });

    test(
      'freeze remains bounded when a custom starter ignores cancellation',
      () async {
        final never = Completer<FishCompanionServiceHandle>();
        final lateHandle = _FakeFishCompanionServiceHandle();
        final host = FishCompanionRuntimeHost.withStarter(
          (_) => never.future,
          startupCancellationGracePeriod: const Duration(milliseconds: 20),
        );

        final ready = host.ready();
        await expectLater(
          host.freezeAndFlush().timeout(const Duration(seconds: 1)),
          throwsA(isA<TimeoutException>()),
        );
        never.complete(lateHandle);
        await expectLater(ready, throwsStateError);

        expect(lateHandle.shutdownCount, 1);
        await host.shutdown();
      },
    );

    test(
      'shutdown is retryable after pending startup cleanup times out',
      () async {
        final started = Completer<FishCompanionServiceHandle>();
        final lateHandle = _FakeFishCompanionServiceHandle();
        final host = FishCompanionRuntimeHost.withStarter(
          (_) => started.future,
          startupCancellationGracePeriod: const Duration(milliseconds: 20),
        );

        final ready = host.ready();
        await expectLater(
          host.shutdown().timeout(const Duration(seconds: 1)),
          throwsA(isA<TimeoutException>()),
        );
        started.complete(lateHandle);
        await expectLater(ready, throwsStateError);

        await host.shutdown().timeout(const Duration(seconds: 1));
        expect(lateHandle.shutdownCount, 1);
      },
    );

    test('a starter TimeoutException is not a cleanup timeout', () async {
      final started = Completer<FishCompanionServiceHandle>();
      final resumed = _FakeFishCompanionServiceHandle();
      var startCount = 0;
      final host = FishCompanionRuntimeHost.withStarter((_) {
        startCount += 1;
        return startCount == 1 ? started.future : Future.value(resumed);
      });

      final readyFailure = expectLater(
        host.ready(),
        throwsA(isA<TimeoutException>()),
      );
      final frozen = host.freezeAndFlush();
      started.completeError(TimeoutException('synthetic starter timeout'));
      await frozen;
      await readyFailure;
      await host.resumeAfterFailure();

      expect(startCount, 2);
      await host.shutdown();
      expect(resumed.shutdownCount, 1);
    });

    test('a canceled startup resumes exactly one new generation', () async {
      final resumed = _FakeFishCompanionServiceHandle();
      var startCount = 0;
      final host = FishCompanionRuntimeHost.withStarter((cancellation) async {
        startCount += 1;
        if (startCount == 1) {
          await cancellation.whenCanceled;
          cancellation.throwIfCanceled();
        }
        return resumed;
      });

      final firstReadyFailure = expectLater(
        host.ready(),
        throwsA(isA<FishCompanionStartupCanceled>()),
      );
      await host.freezeAndFlush();
      await firstReadyFailure;
      await host.resumeAfterFailure();
      await host.resumeAfterFailure();

      expect(startCount, 2);
      await host.shutdown();
      expect(resumed.shutdownCount, 1);
    });

    test(
      'a pending host that becomes healthy is eligible for resume',
      () async {
        final started = Completer<FishCompanionServiceHandle>();
        final first = _FakeFishCompanionServiceHandle();
        final resumed = _FakeFishCompanionServiceHandle();
        var startCount = 0;
        final host = FishCompanionRuntimeHost.withStarter((_) {
          startCount += 1;
          return startCount == 1 ? started.future : Future.value(resumed);
        });

        final ready = host.ready();
        final frozen = host.freezeAndFlush();
        started.complete(first);
        await frozen;
        await expectLater(ready, throwsStateError);
        await host.resumeAfterFailure();

        expect(startCount, 2);
        expect(first.shutdownCount, 1);
        await host.shutdown();
        expect(resumed.shutdownCount, 1);
      },
    );

    test(
      'resume is a no-op when freeze saw no started or pending host',
      () async {
        var startCount = 0;
        final host = FishCompanionRuntimeHost.withStarter((_) async {
          startCount += 1;
          return _FakeFishCompanionServiceHandle();
        });

        await host.freezeAndFlush();
        await host.resumeAfterFailure();

        expect(startCount, 0);
        await host.shutdown();
      },
    );

    test('resume is a no-op after an earlier startup failure', () async {
      var startCount = 0;
      final host = FishCompanionRuntimeHost.withStarter((_) async {
        startCount += 1;
        throw StateError('synthetic startup failure');
      });

      await host.prewarm();
      expect(startCount, 1);
      await host.freezeAndFlush();
      await host.resumeAfterFailure();

      expect(startCount, 1);
      await host.shutdown();
    });

    test('durability lifecycle checkpoints, freezes, and resumes', () async {
      final handles = <_FakeFishCompanionServiceHandle>[];
      final host = FishCompanionRuntimeHost.withStarter((_) async {
        final handle = _FakeFishCompanionServiceHandle();
        handles.add(handle);
        return handle;
      });

      await host.ready();
      await host.flushForLifecycle();
      expect(handles.single.checkpointCount, 1);

      await host.freezeAndFlush();
      expect(handles.single.shutdownCount, 1);
      await host.resumeAfterFailure();
      expect(handles, hasLength(2));
      await host.shutdown();
      expect(handles.last.shutdownCount, 1);
    });

    test(
      'resume waits for retained handle cleanup before starting again',
      () async {
        final cleanupMayFinish = Completer<void>();
        final first = _FakeFishCompanionServiceHandle(
          shutdownFailuresRemaining: 1,
          successfulShutdownBarrier: cleanupMayFinish.future,
        );
        final resumed = _FakeFishCompanionServiceHandle();
        var startCount = 0;
        final host = FishCompanionRuntimeHost.withStarter((_) async {
          startCount += 1;
          return startCount == 1 ? first : resumed;
        });

        await host.ready();
        await expectLater(host.freezeAndFlush(), throwsStateError);
        expect(first.shutdownCount, 1);
        expect(startCount, 1);

        final resume = host.resumeAfterFailure();
        await Future<void>.delayed(Duration.zero);
        expect(first.shutdownCount, 2);
        expect(startCount, 1);

        cleanupMayFinish.complete();
        await resume;
        expect(startCount, 2);
        expect(await host.ready(), same(resumed));
        await host.shutdown();
        expect(resumed.shutdownCount, 1);
      },
    );

    test('permanent shutdown retries retained handle cleanup', () async {
      final first = _FakeFishCompanionServiceHandle(
        shutdownFailuresRemaining: 1,
      );
      var startCount = 0;
      final host = FishCompanionRuntimeHost.withStarter((_) async {
        startCount += 1;
        return first;
      });

      await host.ready();
      await expectLater(host.freezeAndFlush(), throwsStateError);
      await host.shutdown();

      expect(first.shutdownCount, 2);
      expect(startCount, 1);
      await expectLater(host.ready(), throwsStateError);
    });

    test(
      'strict freeze never coalesces into an exit-only transition',
      () async {
        final surface = _GatedFishCompanionSurfaceLifecycle();
        final host = FishCompanionRuntimeHost.withStarter(
          (_) async => _FakeFishCompanionServiceHandle(),
        );
        host.attachSurface(surface);

        final exiting = host.freezeAndFlushForApplicationExit();
        await surface.freezeStarted.future;
        await expectLater(host.freezeAndFlush(), throwsStateError);

        surface.allowFreeze.complete();
        await exiting;
        host.detachSurface(surface);
        await host.shutdown();
      },
    );

    test('freeze closes the WebView before stopping the service', () async {
      final events = <String>[];
      final handle = _FakeFishCompanionServiceHandle(
        events: events,
        shutdownEvent: 'service-shutdown',
      );
      final surface = _FakeFishCompanionSurfaceLifecycle(events);
      final host = FishCompanionRuntimeHost.withStarter((_) async => handle);
      host.attachSurface(surface);

      await host.ready();
      await host.freezeAndFlush();

      expect(events, <String>['surface-freeze', 'service-shutdown']);
      await host.resumeAfterFailure();
      expect(events.last, 'surface-resume');
      host.detachSurface(surface);
      await host.shutdown();
    });

    test(
      'failed startup does not freeze or resume an attached surface',
      () async {
        final events = <String>[];
        final surface = _FakeFishCompanionSurfaceLifecycle(events);
        final host = FishCompanionRuntimeHost.withStarter((_) async {
          throw StateError('synthetic startup failure');
        });
        host.attachSurface(surface);

        await host.prewarm();
        await host.freezeAndFlush();
        await host.resumeAfterFailure();

        expect(events, isEmpty);
        host.detachSurface(surface);
        await host.shutdown();
      },
    );
  });

  test(
    'Fish WebView reuses only the expected process-global environment',
    () async {
      expect(
        await initializeFishCompanionWebViewEnvironment(() async {}),
        FishCompanionWebViewEnvironmentOwnership.isolated,
      );
      expect(
        await initializeFishCompanionWebViewEnvironment(() async {
          throw PlatformException(code: 'environment_already_initialized');
        }),
        FishCompanionWebViewEnvironmentOwnership.shared,
      );
      await expectLater(
        initializeFishCompanionWebViewEnvironment(() async {
          throw PlatformException(code: 'environment_creation_failed');
        }),
        throwsA(isA<PlatformException>()),
      );
    },
  );

  testWidgets('widget tests do not launch an external localhost process', (
    tester,
  ) async {
    expect(Platform.environment['FLUTTER_TEST'], 'true');
    final personalRoot = Directory.systemTemp.createTempSync(
      'fish-companion-widget-test-',
    );
    addTearDown(() => personalRoot.delete(recursive: true));
    var startCount = 0;
    final runtimeHost = FishCompanionRuntimeHost(
      personalDataRoot: personalRoot,
      referenceCacheRoot: Directory('unused-reference-fixture'),
      webViewDataRoot: Directory(_path(personalRoot.path, 'webview2')),
      starter: (_) async {
        startCount += 1;
        throw StateError('widget tests must not start Fish Companion');
      },
    );
    addTearDown(runtimeHost.shutdown);

    await tester.pumpWidget(
      MaterialApp(home: FishCompanionView(runtimeHost: runtimeHost)),
    );

    expect(find.byKey(const Key('fish-companion-starting')), findsOneWidget);
    expect(
      find.byKey(const Key('fish-companion-loading-game-icon')),
      findsOneWidget,
    );
    final loadingSemantics = tester.widget<Semantics>(
      find.byKey(const Key('fish-companion-loading-semantics')),
    );
    expect(loadingSemantics.excludeSemantics, isTrue);
    expect(find.text('Preparing Fish Map'), findsOneWidget);
    expect(find.text('Loading the current fishing tables…'), findsOneWidget);
    final loadingIcon = tester.widget<Image>(
      find.byKey(const Key('fish-companion-loading-game-icon')),
    );
    expect(
      (loadingIcon.image as AssetImage).assetName,
      'assets/fish_companion/data/cache/icons-4x/00008479.webp',
    );
    expect(startCount, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'production page surface keeps the native loader over content until ready',
    (tester) async {
      const contentKey = Key('production-fish-page-fixture');

      await tester.pumpWidget(
        const MaterialApp(
          home: FishCompanionPageSurface(
            pageStatus: FishCompanionPageStatus.starting,
            content: ColoredBox(key: contentKey, color: Color(0xFF123456)),
          ),
        ),
      );
      expect(find.byKey(contentKey), findsOneWidget);
      expect(find.byKey(const Key('fish-companion-starting')), findsOneWidget);

      await tester.pumpWidget(
        const MaterialApp(
          home: FishCompanionPageSurface(
            pageStatus: FishCompanionPageStatus.ready,
            content: ColoredBox(key: contentKey, color: Color(0xFF123456)),
          ),
        ),
      );
      expect(find.byKey(contentKey), findsOneWidget);
      expect(find.byKey(const Key('fish-companion-starting')), findsNothing);
    },
  );

  test('page handoff waits for the standalone boot overlay', () async {
    var calls = 0;
    final status = await waitForFishCompanionPageTerminalStatus(
      (_) async => ++calls < 3 ? 'starting' : 'ready',
      pollInterval: Duration.zero,
      timeout: const Duration(seconds: 1),
    );
    expect(status, FishCompanionPageStatus.ready);
    expect(calls, 3);
  });

  test('page handoff surfaces standalone terminal failure', () async {
    final status = await waitForFishCompanionPageTerminalStatus(
      (_) async => 'failed',
      pollInterval: Duration.zero,
      timeout: const Duration(seconds: 1),
    );
    expect(status, FishCompanionPageStatus.failed);
  });

  test(
    'fresh preparation serves the package without writing personal or cache data',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      await fixture.writeAcceptedPayload();

      final root = await fixture.runtime().install();
      expect(root.path, fixture.packagedRoot.absolute.path);
      expect(await fixture.personalRoot.list().isEmpty, isTrue);
      expect(await fixture.referenceRoot.list().isEmpty, isTrue);
    },
  );

  test('managed cleanup sentinel recognizes both Windows representations', () {
    expect(
      isFishCompanionManagedHostCleanupFailedExitCode(
        fishCompanionManagedHostCleanupFailedExitCode,
      ),
      isTrue,
    );
    expect(
      isFishCompanionManagedHostCleanupFailedExitCode(
        fishCompanionManagedHostCleanupFailedSignedExitCode,
      ),
      isTrue,
    );
    expect(isFishCompanionManagedHostCleanupFailedExitCode(1), isFalse);
  });

  test(
    'cleanup-unproven managed host exit is sticky and never retried',
    () async {
      if (!Platform.isWindows) return;
      for (final exitCode in <int>[
        fishCompanionManagedHostCleanupFailedExitCode,
        fishCompanionManagedHostCleanupFailedSignedExitCode,
      ]) {
        final fixture = await _Fixture.create();
        addTearDown(fixture.dispose);
        await fixture.writeAcceptedPayload();
        final managedHost = await fixture.writeManagedHostStub();
        final processes = <_ImmediateExitProcess>[];
        addTearDown(() async {
          for (final process in processes) {
            await process.dispose();
          }
        });
        var launchCount = 0;
        final runtime = fixture.runtime(
          managedProcessHostExecutable: managedHost,
          managedProcessStarter:
              (_, _, {required String workingDirectory}) async {
                launchCount += 1;
                final process = _ImmediateExitProcess(exitCode);
                processes.add(process);
                return process;
              },
        );
        final host = FishCompanionRuntimeHost.withStarter(
          (cancellation) => runtime.start(cancellation: cancellation),
        );
        final surfaceEvents = <String>[];
        final surface = _FakeFishCompanionSurfaceLifecycle(surfaceEvents);
        host.attachSurface(surface);

        await expectLater(
          host.ready(),
          throwsA(
            isA<FishCompanionManagedHostCleanupFailed>().having(
              (error) => error.toString(),
              'message',
              allOf(
                contains('Fully close and restart Black Spirit Life'),
                isNot(contains('Try Fish Map again')),
              ),
            ),
          ),
        );
        expect(launchCount, 1);

        await expectLater(
          host.ready(),
          throwsA(isA<FishCompanionManagedHostCleanupFailed>()),
        );
        await expectLater(
          host.freezeAndFlush(),
          throwsA(isA<FishCompanionManagedHostCleanupFailed>()),
        );
        expect(surfaceEvents, isEmpty);
        await host.freezeAndFlushForApplicationExit();
        expect(surfaceEvents, <String>['surface-freeze']);
        await expectLater(
          host.resumeAfterFailure(),
          throwsA(isA<FishCompanionManagedHostCleanupFailed>()),
        );
        expect(launchCount, 1);

        host.detachSurface(surface);
        await expectLater(
          host.shutdown(),
          throwsA(isA<FishCompanionManagedHostCleanupFailed>()),
        );
        expect(launchCount, 1);
      }
    },
  );

  test(
    'legacy migration cleanup sentinel is sticky and never retried',
    () async {
      if (!Platform.isWindows) return;
      for (final exitCode in <int>[
        fishCompanionManagedHostCleanupFailedExitCode,
        fishCompanionManagedHostCleanupFailedSignedExitCode,
      ]) {
        final fixture = await _Fixture.create();
        addTearDown(fixture.dispose);
        await fixture.writeAcceptedPayload();
        final managedHost = await fixture.writeManagedHostStub();
        final legacy = _fileAt(
          fixture.personalRoot,
          'fishing/fishing-journal.json',
        );
        await legacy.parent.create(recursive: true);
        await legacy.writeAsString('{}');
        final processes = <_ImmediateExitProcess>[];
        addTearDown(() async {
          for (final process in processes) {
            await process.dispose();
          }
        });
        var launchCount = 0;
        final runtime = fixture.runtime(
          managedProcessHostExecutable: managedHost,
          managedProcessStarter:
              (_, _, {required String workingDirectory}) async {
                launchCount += 1;
                final process = _ImmediateExitProcess(
                  exitCode,
                  undrainableOutput:
                      exitCode == fishCompanionManagedHostCleanupFailedExitCode,
                );
                processes.add(process);
                return process;
              },
        );
        final host = FishCompanionRuntimeHost.withStarter(
          (cancellation) => runtime.start(cancellation: cancellation),
        );

        await expectLater(
          host.ready(),
          throwsA(isA<FishCompanionManagedHostCleanupFailed>()),
        );
        await expectLater(
          host.ready(),
          throwsA(isA<FishCompanionManagedHostCleanupFailed>()),
        );
        await expectLater(
          host.freezeAndFlush(),
          throwsA(isA<FishCompanionManagedHostCleanupFailed>()),
        );
        await host.freezeAndFlushForApplicationExit();
        await expectLater(
          host.resumeAfterFailure(),
          throwsA(isA<FishCompanionManagedHostCleanupFailed>()),
        );
        expect(launchCount, 1);

        await expectLater(
          host.shutdown(),
          throwsA(isA<FishCompanionManagedHostCleanupFailed>()),
        );
        expect(launchCount, 1);
      }
    },
  );

  test(
    'healthy handle cleanup sentinel blocks every same-process lifecycle',
    () async {
      if (!Platform.isWindows) return;
      for (final exitCode in <int>[
        fishCompanionManagedHostCleanupFailedExitCode,
        fishCompanionManagedHostCleanupFailedSignedExitCode,
      ]) {
        final fixture = await _Fixture.create();
        addTearDown(fixture.dispose);
        await fixture.writeAcceptedPayload();
        final managedHost = await fixture.writeManagedHostStub();
        final process = _ControllableExitProcess(
          undrainableOutput:
              exitCode == fishCompanionManagedHostCleanupFailedExitCode,
        );
        addTearDown(process.dispose);
        HttpServer? server;
        StreamSubscription<HttpRequest>? requests;
        addTearDown(() async {
          await requests?.cancel();
          await server?.close(force: true);
        });
        var launchCount = 0;
        final runtime = fixture.runtime(
          managedProcessHostExecutable: managedHost,
          managedProcessStarter:
              (_, arguments, {required String workingDirectory}) async {
                launchCount += 1;
                final portArgument = arguments.indexOf('--port');
                expect(portArgument, greaterThanOrEqualTo(0));
                final port = int.parse(arguments[portArgument + 1]);
                expect(
                  port,
                  inInclusiveRange(
                    fishCompanionFirstPort,
                    fishCompanionLastPort,
                  ),
                  reason:
                      'The actual service must use the browser-allowed range',
                );
                server = await HttpServer.bind(
                  InternetAddress.loopbackIPv4,
                  port,
                  shared: false,
                );
                requests = server!.listen((request) async {
                  request.response.statusCode = HttpStatus.ok;
                  request.response.contentLength = 0;
                  await request.response.close();
                  if (request.uri.path == '/api/shutdown') {
                    process.complete(exitCode);
                    await server?.close(force: true);
                  }
                });
                return process;
              },
        );
        final host = FishCompanionRuntimeHost.withStarter(
          (cancellation) => runtime.start(cancellation: cancellation),
        );

        await HttpOverrides.runWithHttpOverrides(() async {
          await host.ready();
          await expectLater(
            host.freezeAndFlush(),
            throwsA(isA<FishCompanionManagedHostCleanupFailed>()),
          );
          await host.freezeAndFlushForApplicationExit();
          await expectLater(
            host.ready(),
            throwsA(isA<FishCompanionManagedHostCleanupFailed>()),
          );
          await expectLater(
            host.resumeAfterFailure(),
            throwsA(isA<FishCompanionManagedHostCleanupFailed>()),
          );
          await expectLater(
            host.shutdown(),
            throwsA(isA<FishCompanionManagedHostCleanupFailed>()),
          );
        }, _RealLocalhostHttpOverrides());
        expect(launchCount, 1);
      }
    },
  );

  test(
    'managed service launch retries one drained pre-health exit exactly once',
    () async {
      if (!Platform.isWindows) return;
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      final windowsDirectory = Platform.environment['WINDIR'];
      expect(windowsDirectory, isNotNull);
      final immediateExitExecutable = File(
        _path(windowsDirectory!, 'System32${Platform.pathSeparator}where.exe'),
      );
      expect(await immediateExitExecutable.exists(), isTrue);
      await fixture.writeAcceptedPayload();
      final managedHost = await fixture.writeManagedHostStub();
      final launches =
          <
            ({
              String executable,
              List<String> arguments,
              String workingDirectory,
            })
          >[];
      Future<Process> managedStarter(
        String executable,
        List<String> arguments, {
        required String workingDirectory,
      }) {
        launches.add((
          executable: executable,
          arguments: List<String>.of(arguments),
          workingDirectory: workingDirectory,
        ));
        return Process.start(immediateExitExecutable.path, <String>[
          '__black_spirit_life_missing_service__',
        ], workingDirectory: workingDirectory);
      }

      final runtime = fixture.runtime(
        managedProcessHostExecutable: managedHost,
        managedProcessStarter: managedStarter,
      );
      Object? failure;
      try {
        await runtime.start();
      } on Object catch (error) {
        failure = error;
      }

      expect(failure, isNotNull);
      expect(failure, isA<StateError>());
      expect(launches, hasLength(2));
      final service = _fileAt(
        fixture.packagedRoot,
        'runtime/fish_companion_service.exe',
      ).absolute;
      for (final launch in launches) {
        expect(launch.executable, managedHost.absolute.path);
        expect(launch.workingDirectory, fixture.packagedRoot.absolute.path);
        expect(launch.arguments.sublist(0, 4), <String>[
          '--owner-pid',
          '$pid',
          '--',
          service.path,
        ]);
        expect(launch.arguments, contains('--personal-data-root'));
        expect(launch.arguments, contains('--reference-cache-root'));
        expect(launch.arguments, contains('--api-token'));
      }
      final message = '$failure';
      expect(message, contains('Try Fish Map again'));
      expect(message, isNot(contains(fixture.root.path)));
      expect(message, isNot(contains('--api-token')));
      expect(
        await _fileAt(
          fixture.personalRoot,
          'fishing/fish-journal.sqlite3',
        ).exists(),
        isFalse,
      );
    },
  );

  test('output drain failure cannot mask cleanup-unproven exit', () async {
    if (!Platform.isWindows) return;
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    await fixture.writeAcceptedPayload();
    final managedHost = await fixture.writeManagedHostStub();
    final process = _ImmediateExitProcess(
      fishCompanionManagedHostCleanupFailedExitCode,
      undrainableOutput: true,
    );
    addTearDown(process.dispose);
    var launchCount = 0;
    final runtime = fixture.runtime(
      managedProcessHostExecutable: managedHost,
      managedProcessStarter: (_, _, {required String workingDirectory}) async {
        launchCount += 1;
        return process;
      },
    );
    final host = FishCompanionRuntimeHost.withStarter(
      (cancellation) => runtime.start(cancellation: cancellation),
    );

    await expectLater(
      host.ready().timeout(const Duration(seconds: 6)),
      throwsA(isA<FishCompanionManagedHostCleanupFailed>()),
    );
    await expectLater(
      host.ready(),
      throwsA(isA<FishCompanionManagedHostCleanupFailed>()),
    );
    await host.freezeAndFlushForApplicationExit();
    expect(launchCount, 1);
  });

  test('close cancellation cannot mask the retry cleanup sentinel', () async {
    if (!Platform.isWindows) return;
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    await fixture.writeAcceptedPayload();
    final managedHost = await fixture.writeManagedHostStub();
    final first = _ImmediateExitProcess(1);
    final second = _ControllableExitProcess();
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    final secondStarted = Completer<void>();
    var launchCount = 0;
    final runtime = fixture.runtime(
      managedProcessHostExecutable: managedHost,
      managedProcessStarter: (_, _, {required String workingDirectory}) async {
        launchCount += 1;
        if (launchCount == 1) return first;
        secondStarted.complete();
        return second;
      },
    );
    final host = FishCompanionRuntimeHost.withStarter(
      (cancellation) => runtime.start(cancellation: cancellation),
    );
    final readyFailure = expectLater(
      host.ready(),
      throwsA(isA<FishCompanionManagedHostCleanupFailed>()),
    );
    await secondStarted.future;

    second.complete(fishCompanionManagedHostCleanupFailedExitCode);
    await expectLater(
      host.freezeAndFlush(),
      throwsA(isA<FishCompanionManagedHostCleanupFailed>()),
    );
    await readyFailure;
    await host.freezeAndFlushForApplicationExit();
    await expectLater(
      host.ready(),
      throwsA(isA<FishCompanionManagedHostCleanupFailed>()),
    );
    expect(launchCount, 2);
  });

  test(
    'legacy migration and service both use the managed host contract',
    () async {
      if (!Platform.isWindows) return;
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      final windowsDirectory = Platform.environment['WINDIR'];
      expect(windowsDirectory, isNotNull);
      final immediateExitExecutable = File(
        _path(windowsDirectory!, 'System32${Platform.pathSeparator}where.exe'),
      );
      expect(await immediateExitExecutable.exists(), isTrue);
      await fixture.writeAcceptedPayload();
      final managedHost = await fixture.writeManagedHostStub();
      final legacy = _fileAt(
        fixture.personalRoot,
        'fishing/fishing-journal.json',
      );
      await legacy.parent.create(recursive: true);
      await legacy.writeAsString('{}');
      final launches =
          <
            ({
              String executable,
              List<String> arguments,
              String workingDirectory,
            })
          >[];
      Future<Process> managedStarter(
        String executable,
        List<String> arguments, {
        required String workingDirectory,
      }) {
        launches.add((
          executable: executable,
          arguments: List<String>.of(arguments),
          workingDirectory: workingDirectory,
        ));
        final migration = arguments.contains('--migrate-v017-json');
        return Process.start(immediateExitExecutable.path, <String>[
          migration ? 'where.exe' : '__black_spirit_life_missing_service__',
        ], workingDirectory: workingDirectory);
      }

      final runtime = fixture.runtime(
        managedProcessHostExecutable: managedHost,
        managedProcessStarter: managedStarter,
      );

      await expectLater(runtime.start(), throwsA(isA<StateError>()));

      expect(launches, hasLength(3));
      final service = _fileAt(
        fixture.packagedRoot,
        'runtime/fish_companion_service.exe',
      ).absolute;
      final database = _fileAt(
        fixture.personalRoot,
        'fishing/fish-journal.sqlite3',
      ).absolute;
      expect(launches.first.arguments, <String>[
        '--owner-pid',
        '$pid',
        '--',
        service.path,
        '--migrate-v017-json',
        legacy.absolute.path,
        '--database',
        database.path,
      ]);
      expect(
        launches
            .skip(1)
            .every(
              (launch) =>
                  launch.arguments.length > 4 &&
                  launch.arguments[3] == service.path &&
                  launch.arguments[4] == '--root',
            ),
        isTrue,
      );
    },
  );

  test('lifecycle freeze waits for the managed host process to exit', () async {
    if (!Platform.isWindows) return;
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    await fixture.writeAcceptedPayload();
    final managedHost = await fixture.writeManagedHostStub();
    final process = _DelayedExitProcess();
    addTearDown(process.dispose);
    final processStarted = Completer<void>();
    final runtime = fixture.runtime(
      managedProcessHostExecutable: managedHost,
      managedProcessStarter: (_, _, {required String workingDirectory}) async {
        if (!processStarted.isCompleted) processStarted.complete();
        return process;
      },
    );
    final host = FishCompanionRuntimeHost.withStarter(
      (cancellation) => runtime.start(cancellation: cancellation),
      startupCancellationGracePeriod: const Duration(seconds: 8),
    );
    final readyFailure = expectLater(
      host.ready(),
      throwsA(isA<FishCompanionStartupCanceled>()),
    );
    await processStarted.future;

    await host.freezeAndFlush().timeout(const Duration(seconds: 8));

    expect(process.hasExited, isTrue);
    expect(process.killCount, 2);
    await readyFailure;
    await host.shutdown();
  });

  test(
    'startup cancellation cleanup sentinel fails closed across generations',
    () async {
      if (!Platform.isWindows) return;
      for (final exitCode in <int>[
        fishCompanionManagedHostCleanupFailedExitCode,
        fishCompanionManagedHostCleanupFailedSignedExitCode,
      ]) {
        final fixture = await _Fixture.create();
        addTearDown(fixture.dispose);
        await fixture.writeAcceptedPayload();
        final managedHost = await fixture.writeManagedHostStub();
        final process = _DelayedExitProcess(
          exitCodeOnKill: exitCode,
          exitOnKillCount: 1,
        );
        addTearDown(process.dispose);
        final processStarted = Completer<void>();
        var launchCount = 0;
        final runtime = fixture.runtime(
          managedProcessHostExecutable: managedHost,
          managedProcessStarter:
              (_, _, {required String workingDirectory}) async {
                launchCount += 1;
                if (!processStarted.isCompleted) processStarted.complete();
                return process;
              },
        );
        final host = FishCompanionRuntimeHost.withStarter(
          (cancellation) => runtime.start(cancellation: cancellation),
          startupCancellationGracePeriod: const Duration(seconds: 8),
        );
        final readyFailure = expectLater(
          host.ready(),
          throwsA(isA<FishCompanionManagedHostCleanupFailed>()),
        );
        await processStarted.future;

        await expectLater(
          host.freezeAndFlush().timeout(const Duration(seconds: 8)),
          throwsA(isA<FishCompanionManagedHostCleanupFailed>()),
        );
        await readyFailure;
        await host.freezeAndFlushForApplicationExit();
        await expectLater(
          host.ready(),
          throwsA(isA<FishCompanionManagedHostCleanupFailed>()),
        );
        await expectLater(
          host.resumeAfterFailure(),
          throwsA(isA<FishCompanionManagedHostCleanupFailed>()),
        );
        await expectLater(
          host.shutdown(),
          throwsA(isA<FishCompanionManagedHostCleanupFailed>()),
        );
        expect(process.hasExited, isTrue);
        expect(launchCount, 1);
      }
    },
  );

  test(
    'startup cancellation with a host that never exits stays fail closed',
    () async {
      if (!Platform.isWindows) return;
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      await fixture.writeAcceptedPayload();
      final managedHost = await fixture.writeManagedHostStub();
      final process = _NeverExitProcess();
      addTearDown(process.dispose);
      final processStarted = Completer<void>();
      var launchCount = 0;
      final runtime = fixture.runtime(
        managedProcessHostExecutable: managedHost,
        managedProcessStarter:
            (_, _, {required String workingDirectory}) async {
              launchCount += 1;
              processStarted.complete();
              return process;
            },
      );
      final host = FishCompanionRuntimeHost.withStarter(
        (cancellation) => runtime.start(cancellation: cancellation),
        startupCancellationGracePeriod: const Duration(seconds: 10),
      );
      final readyFailure = expectLater(
        host.ready(),
        throwsA(isA<FishCompanionManagedHostCleanupFailed>()),
      );
      await processStarted.future;

      await expectLater(
        host.freezeAndFlush().timeout(const Duration(seconds: 12)),
        throwsA(isA<FishCompanionManagedHostCleanupFailed>()),
      );
      await readyFailure;
      await expectLater(
        host.ready(),
        throwsA(isA<FishCompanionManagedHostCleanupFailed>()),
      );
      await host.freezeAndFlushForApplicationExit();
      await expectLater(
        host.shutdown(),
        throwsA(isA<FishCompanionManagedHostCleanupFailed>()),
      );
      expect(process.killCount, greaterThanOrEqualTo(2));
      expect(launchCount, 1);
    },
    timeout: const Timeout(Duration(seconds: 15)),
  );

  test(
    'legacy migration cancellation awaits a never-exiting managed host cleanup',
    () async {
      if (!Platform.isWindows) return;
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      await fixture.writeAcceptedPayload();
      final managedHost = await fixture.writeManagedHostStub();
      final legacy = _fileAt(
        fixture.personalRoot,
        'fishing/fishing-journal.json',
      );
      await legacy.parent.create(recursive: true);
      await legacy.writeAsString('{}');
      final process = _NeverExitProcess();
      addTearDown(process.dispose);
      final processStarted = Completer<void>();
      var launchCount = 0;
      final runtime = fixture.runtime(
        managedProcessHostExecutable: managedHost,
        managedProcessStarter:
            (executable, arguments, {required String workingDirectory}) async {
              launchCount += 1;
              expect(arguments, contains('--migrate-v017-json'));
              processStarted.complete();
              return process;
            },
      );
      final host = FishCompanionRuntimeHost.withStarter(
        (cancellation) => runtime.start(cancellation: cancellation),
        startupCancellationGracePeriod: const Duration(seconds: 10),
      );
      final readyFailure = expectLater(
        host.ready(),
        throwsA(isA<FishCompanionManagedHostCleanupFailed>()),
      );
      await processStarted.future;

      await expectLater(
        host.freezeAndFlush().timeout(const Duration(seconds: 12)),
        throwsA(isA<FishCompanionManagedHostCleanupFailed>()),
      );
      await readyFailure;
      await expectLater(
        host.ready(),
        throwsA(isA<FishCompanionManagedHostCleanupFailed>()),
      );
      await host.freezeAndFlushForApplicationExit();
      await expectLater(
        host.shutdown(),
        throwsA(isA<FishCompanionManagedHostCleanupFailed>()),
      );
      expect(process.killCount, greaterThanOrEqualTo(2));
      expect(launchCount, 1);
    },
    timeout: const Timeout(Duration(seconds: 15)),
  );

  test('poisoned payload rejects the complete journal family', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    await fixture.writeAcceptedPayload(
      personalPayloadFiles: const <String, String>{
        'data/fish-journal.sqlite3': 'publisher-journal',
        'data/fish-journal.sqlite3-wal': 'publisher-wal',
        'data/fish-journal.sqlite3-shm': 'publisher-shm',
        'data/fish-journal.sqlite3-journal': 'publisher-rollback-journal',
        'data/fish-journal.before-sale-redesign.sqlite3': 'legacy',
        'data/archive/fish-journal.sqlite3.backup': 'backup',
        'data/recovery/backup-fish-journal.sqlite3.tmp': 'recovery',
      },
    );

    await expectLater(fixture.runtime().install(), throwsStateError);
    expect(await fixture.personalRoot.list().isEmpty, isTrue);
  });

  test(
    'preparation preserves every existing destination journal file',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      await fixture.writeAcceptedPayload();
      const personalFiles = <String, String>{
        'fishing/fish-journal.sqlite3': 'user-journal',
        'fishing/fish-journal.sqlite3-wal': 'user-wal',
        'fishing/fish-journal.sqlite3-shm': 'user-shm',
        'fishing/fish-journal.sqlite3-journal': 'rollback',
        'fishing/fish-journal.before-sale-redesign.sqlite3': 'legacy',
        'fishing/archive/fish-journal.sqlite3.backup': 'backup',
        'fishing/recovery/backup-fish-journal.sqlite3.tmp': 'recovery',
      };
      for (final entry in personalFiles.entries) {
        await _write(fixture.personalRoot, entry.key.split('/'), entry.value);
      }

      await fixture.runtime().install();

      for (final entry in personalFiles.entries) {
        expect(
          await _fileAt(fixture.personalRoot, entry.key).readAsString(),
          entry.value,
        );
      }
    },
  );

  test('reference cache beneath personal data is rejected', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    await fixture.writeAcceptedPayload();
    final nested = Directory(_path(fixture.personalRoot.path, 'cache'));

    await expectLater(
      FishCompanionRuntime(
        personalDataRoot: fixture.personalRoot,
        packagedPayloadRoot: fixture.packagedRoot,
        referenceCacheRoot: nested,
        webViewDataRoot: fixture.webViewRoot,
      ).install(),
      throwsStateError,
    );
  });

  test(
    'shared WebView data must remain beneath the selected personal root',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      await fixture.writeAcceptedPayload();

      await expectLater(
        FishCompanionRuntime(
          personalDataRoot: fixture.personalRoot,
          packagedPayloadRoot: fixture.packagedRoot,
          referenceCacheRoot: fixture.referenceRoot,
          webViewDataRoot: Directory(
            _path(fixture.root.path, 'outside-webview'),
          ),
        ).install(),
        throwsStateError,
      );
      expect(await fixture.personalRoot.list().isEmpty, isTrue);
    },
  );
}

final class _FakeFishCompanionServiceHandle
    implements FishCompanionServiceHandle {
  _FakeFishCompanionServiceHandle({
    this.events,
    this.shutdownEvent,
    this.shutdownFailuresRemaining = 0,
    this.successfulShutdownBarrier,
  });

  @override
  final Directory root = Directory('unused-service-fixture');

  @override
  final Directory personalDataRoot = Directory('unused-personal-fixture');

  @override
  final Directory webViewDataRoot = Directory(
    'unused-personal-fixture/webview2',
  );

  @override
  final Uri uri = Uri.parse('http://127.0.0.1:18765/');

  int checkpointCount = 0;
  int shutdownCount = 0;
  int disposeCount = 0;
  final List<String>? events;
  final String? shutdownEvent;
  int shutdownFailuresRemaining;
  final Future<void>? successfulShutdownBarrier;

  @override
  Future<void> checkpoint() async {
    checkpointCount += 1;
  }

  @override
  Future<void> shutdown() async {
    shutdownCount += 1;
    if (shutdownFailuresRemaining > 0) {
      shutdownFailuresRemaining -= 1;
      throw StateError('synthetic handle shutdown failure');
    }
    final barrier = successfulShutdownBarrier;
    if (barrier != null) await barrier;
    if (shutdownEvent case final event?) events?.add(event);
  }

  @override
  void dispose() {
    disposeCount += 1;
  }
}

final class _DelayedExitProcess implements Process {
  _DelayedExitProcess({this.exitCodeOnKill = -1, this.exitOnKillCount = 2});

  static const int _unusedProcessId = 2147483646;

  final Completer<int> _exit = Completer<int>();
  final StreamController<List<int>> _stdinController =
      StreamController<List<int>>.broadcast();
  late final IOSink _stdin = IOSink(_stdinController.sink);
  final int exitCodeOnKill;
  final int exitOnKillCount;
  int killCount = 0;

  bool get hasExited => _exit.isCompleted;

  @override
  Future<int> get exitCode => _exit.future;

  @override
  int get pid => _unusedProcessId;

  @override
  Stream<List<int>> get stderr => const Stream<List<int>>.empty();

  @override
  IOSink get stdin => _stdin;

  @override
  Stream<List<int>> get stdout => const Stream<List<int>>.empty();

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    killCount += 1;
    if (killCount == exitOnKillCount) {
      Timer(const Duration(milliseconds: 50), () {
        if (!_exit.isCompleted) _exit.complete(exitCodeOnKill);
      });
    }
    return true;
  }

  Future<void> dispose() async {
    if (!_exit.isCompleted) _exit.complete(-1);
    await _stdin.close();
    await _stdinController.close();
  }
}

final class _ControllableExitProcess implements Process {
  _ControllableExitProcess({bool undrainableOutput = false})
    : _stdoutController = undrainableOutput
          ? StreamController<List<int>>(
              onCancel: () => Future<void>.error(
                StateError('synthetic output cancellation failure'),
              ),
            )
          : null;

  static const int _unusedProcessId = 2147483644;

  final Completer<int> _exit = Completer<int>();
  final StreamController<List<int>>? _stdoutController;
  final StreamController<List<int>> _stdinController =
      StreamController<List<int>>.broadcast();
  late final IOSink _stdin = IOSink(_stdinController.sink);

  void complete(int exitCode) {
    if (!_exit.isCompleted) _exit.complete(exitCode);
  }

  @override
  Future<int> get exitCode => _exit.future;

  @override
  int get pid => _unusedProcessId;

  @override
  Stream<List<int>> get stderr => const Stream<List<int>>.empty();

  @override
  IOSink get stdin => _stdin;

  @override
  Stream<List<int>> get stdout =>
      _stdoutController?.stream ?? const Stream<List<int>>.empty();

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    complete(-1);
    return true;
  }

  Future<void> dispose() async {
    complete(-1);
    await _stdin.close();
    await _stdinController.close();
    await _stdoutController?.close();
  }
}

final class _NeverExitProcess implements Process {
  static const int _unusedProcessId = 2147483643;

  final Completer<int> _exit = Completer<int>();
  final StreamController<List<int>> _stdinController =
      StreamController<List<int>>.broadcast();
  late final IOSink _stdin = IOSink(_stdinController.sink);
  int killCount = 0;

  @override
  Future<int> get exitCode => _exit.future;

  @override
  int get pid => _unusedProcessId;

  @override
  Stream<List<int>> get stderr => const Stream<List<int>>.empty();

  @override
  IOSink get stdin => _stdin;

  @override
  Stream<List<int>> get stdout => const Stream<List<int>>.empty();

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    killCount += 1;
    return true;
  }

  Future<void> dispose() async {
    if (!_exit.isCompleted) _exit.complete(-1);
    await _stdin.close();
    await _stdinController.close();
  }
}

final class _ImmediateExitProcess implements Process {
  _ImmediateExitProcess(int exitCode, {bool undrainableOutput = false})
    : _exitCode = Future<int>.value(exitCode),
      _stdoutController = undrainableOutput
          ? StreamController<List<int>>(
              onCancel: () => Future<void>.error(
                StateError('synthetic output cancellation failure'),
              ),
            )
          : null;

  static const int _unusedProcessId = 2147483645;

  final Future<int> _exitCode;
  final StreamController<List<int>>? _stdoutController;
  final StreamController<List<int>> _stdinController =
      StreamController<List<int>>.broadcast();
  late final IOSink _stdin = IOSink(_stdinController.sink);

  @override
  Future<int> get exitCode => _exitCode;

  @override
  int get pid => _unusedProcessId;

  @override
  Stream<List<int>> get stderr => const Stream<List<int>>.empty();

  @override
  IOSink get stdin => _stdin;

  @override
  Stream<List<int>> get stdout =>
      _stdoutController?.stream ?? const Stream<List<int>>.empty();

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) => false;

  Future<void> dispose() async {
    await _stdin.close();
    await _stdinController.close();
    await _stdoutController?.close();
  }
}

final class _RealLocalhostHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    client.connectionTimeout = const Duration(seconds: 2);
    return client;
  }
}

final class _FakeFishCompanionSurfaceLifecycle
    implements FishCompanionSurfaceLifecycle {
  _FakeFishCompanionSurfaceLifecycle(this.events);

  final List<String> events;

  @override
  Future<void> freezeForLifecycle() async => events.add('surface-freeze');

  @override
  Future<void> resumeAfterLifecycleFailure() async =>
      events.add('surface-resume');
}

final class _GatedFishCompanionSurfaceLifecycle
    implements FishCompanionSurfaceLifecycle {
  final Completer<void> freezeStarted = Completer<void>();
  final Completer<void> allowFreeze = Completer<void>();

  @override
  Future<void> freezeForLifecycle() async {
    freezeStarted.complete();
    await allowFreeze.future;
  }

  @override
  Future<void> resumeAfterLifecycleFailure() async {}
}

class _Fixture {
  const _Fixture({
    required this.root,
    required this.packagedRoot,
    required this.personalRoot,
    required this.referenceRoot,
    required this.webViewRoot,
  });

  final Directory root;
  final Directory packagedRoot;
  final Directory personalRoot;
  final Directory referenceRoot;
  final Directory webViewRoot;

  static Future<_Fixture> create() async {
    final root = await Directory.systemTemp.createTemp(
      'fish-companion-runtime-test-',
    );
    final packagedRoot = Directory(_path(root.path, 'packaged'));
    final personalRoot = Directory(_path(root.path, 'personal'));
    final referenceRoot = Directory(_path(root.path, 'reference-cache'));
    final webViewRoot = Directory(_path(personalRoot.path, 'webview2'));
    await packagedRoot.create(recursive: true);
    await personalRoot.create(recursive: true);
    await referenceRoot.create(recursive: true);
    return _Fixture(
      root: root,
      packagedRoot: packagedRoot,
      personalRoot: personalRoot,
      referenceRoot: referenceRoot,
      webViewRoot: webViewRoot,
    );
  }

  FishCompanionRuntime runtime({
    File? managedProcessHostExecutable,
    FishCompanionManagedProcessStarter? managedProcessStarter,
  }) => FishCompanionRuntime(
    personalDataRoot: personalRoot,
    packagedPayloadRoot: packagedRoot,
    referenceCacheRoot: referenceRoot,
    webViewDataRoot: webViewRoot,
    managedProcessHostExecutable: managedProcessHostExecutable,
    managedProcessStarter: managedProcessStarter,
  );

  Future<File> writeManagedHostStub() async {
    final file = File(_path(root.path, 'BlackSpiritLifeFishHost.exe'));
    await file.writeAsString('managed-host-test-stub');
    return file;
  }

  Future<void> writeAcceptedPayload({
    Map<String, String> personalPayloadFiles = const <String, String>{},
    File? serviceExecutable,
  }) async {
    const files = <String, String>{
      'static/index.html': 'accepted-index',
      'static/app.js': 'accepted-app-script',
      'static/app.css': 'accepted-app-style',
      'data/cache/derived-index.v1.json': 'derived-index',
      'data/cache/fish.json': 'fish',
      'data/cache/meta.json': 'meta',
      'data/cache/zone_mask.v8.bin': 'zone-mask',
      'data/cache/zones.json': 'zones',
    };
    for (final entry in <String, String>{
      ...files,
      ...personalPayloadFiles,
    }.entries) {
      await _write(packagedRoot, entry.key.split('/'), entry.value);
    }
    final service = _fileAt(packagedRoot, 'runtime/fish_companion_service.exe');
    await service.parent.create(recursive: true);
    if (serviceExecutable case final executable?) {
      await executable.copy(service.path);
    } else {
      await service.writeAsString('service');
    }
    final immutable = await _integrityRecords(packagedRoot, const <String>[
      'static/index.html',
      'static/app.js',
      'static/app.css',
      'runtime/fish_companion_service.exe',
    ]);
    final snapshot = await _integrityRecords(packagedRoot, const <String>[
      'data/cache/derived-index.v1.json',
      'data/cache/fish.json',
      'data/cache/meta.json',
      'data/cache/zone_mask.v8.bin',
      'data/cache/zones.json',
    ]);
    await _write(
      packagedRoot,
      <String>['data', 'install-critical-manifest.v1.json'],
      jsonEncode(<String, Object>{
        'schemaVersion': 1,
        'immutableFiles': immutable,
        'snapshotFiles': snapshot,
      }),
    );
  }

  Future<void> dispose() => root.delete(recursive: true);
}

Future<List<Map<String, Object>>> _integrityRecords(
  Directory root,
  List<String> paths,
) async {
  final records = <Map<String, Object>>[];
  for (final relative in List<String>.of(paths)..sort()) {
    final file = _fileAt(root, relative);
    final bytes = await file.readAsBytes();
    records.add(<String, Object>{
      'path': relative,
      'byteCount': bytes.length,
      'sha256': sha256.convert(bytes).toString(),
    });
  }
  return records;
}

File _fileAt(Directory root, String relative) => File(
  <String>[root.path, ...relative.split('/')].join(Platform.pathSeparator),
);

Future<void> _write(
  Directory root,
  List<String> relative,
  String contents,
) async {
  final file = File(
    <String>[root.path, ...relative].join(Platform.pathSeparator),
  );
  await file.parent.create(recursive: true);
  await file.writeAsString(contents);
}

String _path(String first, [String? second]) =>
    <String?>[first, second].whereType<String>().join(Platform.pathSeparator);
