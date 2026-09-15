import 'dart:async';

abstract interface class FishingWorkspaceLifecycle {
  Future<void> flush();

  Future<void> reload();

  Future<void> freezeAndFlush();

  void resumeMutations();
}

/// A small lifecycle bridge for the application shell. The Fish workspace
/// owns its local repository; the shell can still flush before shutdown and
/// reload on demand without reaching into widget state.
class FishingWorkspaceController {
  FishingWorkspaceLifecycle? _lifecycle;

  Future<void> flush() => _lifecycle?.flush() ?? Future<void>.value();

  Future<void> reload() => _lifecycle?.reload() ?? Future<void>.value();

  /// Blocks new mutations before waiting for every write already issued by
  /// the workspace. Keep the workspace frozen when the folder switch succeeds
  /// because the application restarts against the new root.
  Future<void> freezeAndFlush() =>
      _lifecycle?.freezeAndFlush() ?? Future<void>.value();

  /// Re-enables edits when a personal-data folder switch fails before restart.
  void resumeAfterFailedSwitch() => _lifecycle?.resumeMutations();

  void attach(FishingWorkspaceLifecycle lifecycle) {
    _lifecycle = lifecycle;
  }

  void detach(FishingWorkspaceLifecycle lifecycle) {
    if (identical(_lifecycle, lifecycle)) _lifecycle = null;
  }
}
