/// Process-only diagnostics. These options are never part of saved settings.
final class ApplicationLaunchOptions {
  const ApplicationLaunchOptions({this.diagnosticDeferFishPrewarm = false});

  factory ApplicationLaunchOptions.fromArguments(Iterable<String> arguments) =>
      ApplicationLaunchOptions(
        diagnosticDeferFishPrewarm: arguments.contains(
          '--diagnostic-defer-fish-prewarm',
        ),
      );

  final bool diagnosticDeferFishPrewarm;
}
