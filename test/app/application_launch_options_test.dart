import 'dart:async';
import 'dart:io';

import 'package:bdo_craft_planner_flutter/app/application_launch_options.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Fish prewarm diagnostics are off for every ordinary launch', () {
    expect(
      const ApplicationLaunchOptions().diagnosticDeferFishPrewarm,
      isFalse,
    );
    for (final arguments in <List<String>>[
      <String>[],
      <String>['--unrelated-option'],
      <String>['--diagnostic-defer-fish-prewarm=false'],
      <String>['--diagnostic-defer-fish-prewarm=true'],
      <String>['--diagnostic-defer-fish-prewarm-extra'],
      <String>['--DIAGNOSTIC-DEFER-FISH-PREWARM'],
      <String>[' --diagnostic-defer-fish-prewarm'],
    ]) {
      expect(
        ApplicationLaunchOptions.fromArguments(
          arguments,
        ).diagnosticDeferFishPrewarm,
        isFalse,
        reason:
            'Only the exact opt-in token enables the diagnostic: $arguments',
      );
    }
  });

  test('exact Fish diagnostic token works independently of argument order', () {
    const flag = '--diagnostic-defer-fish-prewarm';
    for (final arguments in <List<String>>[
      <String>[flag],
      <String>['--unrelated-option', flag],
      <String>[flag, '--unrelated-option'],
      <String>[flag, flag],
    ]) {
      expect(
        ApplicationLaunchOptions.fromArguments(
          arguments,
        ).diagnosticDeferFishPrewarm,
        isTrue,
      );
    }
  });

  test('diagnostic parsing cannot carry state into a later normal launch', () {
    final arguments = <String>['--diagnostic-defer-fish-prewarm'];
    final diagnostic = ApplicationLaunchOptions.fromArguments(arguments);
    arguments.clear();

    expect(diagnostic.diagnosticDeferFishPrewarm, isTrue);
    expect(
      ApplicationLaunchOptions.fromArguments(
        arguments,
      ).diagnosticDeferFishPrewarm,
      isFalse,
    );
    expect(
      const ApplicationLaunchOptions().diagnosticDeferFishPrewarm,
      isFalse,
    );
  });

  test('real entry point forwards the opt-in and guards direct host prewarm', () {
    final entryPoint = File('lib/main.dart').readAsStringSync();
    final bootstrap = File('lib/app/bootstrap.dart').readAsStringSync();

    // The widget tests exercise BdoCraftPlannerApp, not runApp/bootstrap.
    // Keep the earlier direct service-start path covered without launching it.
    expect(
      entryPoint,
      contains('launchOptions: ApplicationLaunchOptions.fromArguments(args)'),
    );
    expect(
      bootstrap,
      contains(
        'ApplicationLaunchOptions launchOptions = const ApplicationLaunchOptions()',
      ),
    );
    expect(
      RegExp(
        r'if\s*\(!launchOptions\.diagnosticDeferFishPrewarm\)\s*\{\s*'
        r'unawaited\(fishCompanionRuntimeHost\.prewarm\(\)\);\s*\}',
      ).hasMatch(bootstrap),
      isTrue,
    );
    expect(
      RegExp(r'fishCompanionRuntimeHost\.prewarm\(').allMatches(bootstrap),
      hasLength(1),
      reason: 'No unguarded second bootstrap prewarm path may bypass the flag.',
    );
    expect(
      bootstrap,
      contains(
        'diagnosticDeferFishPrewarm: launchOptions.diagnosticDeferFishPrewarm',
      ),
    );
    final directoryErrorGuard = RegExp(
      r'if\s*\(launchOptions\.diagnosticDeferFishPrewarm\)\s*\{\s*'
      r'(?://[^\r\n]*\s*)*applicationDirectory\.future\.ignore\(\);\s*\}',
    ).firstMatch(bootstrap);
    expect(directoryErrorGuard, isNotNull);
    expect(
      directoryErrorGuard!.start,
      lessThan(bootstrap.indexOf('final applicationFuture =')),
      reason: 'Install the error listener before bootstrap can fail.',
    );
  });

  test(
    'deferred directory errors do not become a second uncaught failure',
    () async {
      final uncaught = <Object>[];
      final failure = StateError('catalog unavailable');
      Object? mainFailure;
      Object? relayedFailure;

      await runZonedGuarded<Future<void>>(() async {
        final applicationDirectory = Completer<Directory>();
        applicationDirectory.future.ignore();
        final application = Completer<void>();
        // This models the bootstrap relay checked above. It deliberately does
        // not invoke the real bootstrap, filesystem/profile discovery or runApp.
        unawaited(
          application.future.then<void>(
            (_) {},
            onError: (Object error, StackTrace stackTrace) {
              applicationDirectory.completeError(error, stackTrace);
            },
          ),
        );
        final reportedFailure = application.future.then<Object?>(
          (_) => null,
          onError: (Object error, StackTrace stackTrace) => error,
        );
        application.completeError(failure);
        mainFailure = await reportedFailure;
        await Future<void>.delayed(Duration.zero);

        // ignore() observes the unused relay; it does not turn its failure into
        // success or prevent a later legitimate consumer from seeing the error.
        relayedFailure = await applicationDirectory.future.then<Object?>(
          (_) => null,
          onError: (Object error, StackTrace stackTrace) => error,
        );
      }, (error, stackTrace) => uncaught.add(error));

      expect(uncaught, isEmpty);
      expect(mainFailure, same(failure));
      expect(relayedFailure, same(failure));
    },
  );
}
