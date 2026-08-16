import 'package:flutter/material.dart';

import '../app_identity.dart';
import '../data/persistence/planner_state_repository.dart';
import '../domain/market/market_price_gateway.dart';
import '../features/resource_map/resource_map_workspace.dart';
import '../shared/overlays/draggable_overlay_surface.dart';
import '../visual/components/app_button.dart';
import '../visual/components/app_surface.dart';
import '../visual/components/section_header.dart';
import '../visual/foundations/app_scroll_behavior.dart';
import '../visual/foundations/theme_spec.dart';
import '../visual/sakura_night_garden/sakura_spec.dart';
import '../visual/standard/standard_spec.dart';
import 'application_bootstrap.dart';
import 'first_launch_migration_view.dart';
import 'first_run_setup.dart';
import 'first_run_setup_view.dart';
import 'update/beta_update.dart';
import 'window/app_startup_frame.dart';
import 'window/window_host_service.dart';
import 'window/world_root_startup_animation.dart';
import 'workspace/application_workspace.dart';

class BdoCraftPlannerApp extends StatelessWidget {
  const BdoCraftPlannerApp({
    required this.applicationFuture,
    this.marketGateway,
    this.resourceMapConfiguration = const ResourceMapWorkspaceConfiguration(),
    this.updateService,
    this.updateSource,
    this.enableBetaUpdates = AppIdentity.outOfProcessBetaUpdatesEnabled,
    this.repeatFullSetupEveryApplicationVersion =
        AppIdentity.repeatFullSetupEveryApplicationVersion,
    this.windowHost = const WindowHostService(),
    super.key,
  });

  final Future<ApplicationBundle> applicationFuture;
  final MarketPriceGateway? marketGateway;
  final ResourceMapWorkspaceConfiguration resourceMapConfiguration;
  final BetaUpdateService? updateService;
  final String? updateSource;
  final bool enableBetaUpdates;
  final bool repeatFullSetupEveryApplicationVersion;
  final WindowHostService windowHost;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: AppIdentity.displayName,
    debugShowCheckedModeBanner: false,
    scrollBehavior: const AppScrollBehavior(),
    theme: SakuraNightGardenSpec.theme.materialTheme(),
    home: ThemeSpecScope(
      spec: SakuraNightGardenSpec.theme,
      child: StandardVisualScope(
        settings: const StandardVisualSettings(
          backgroundId: SakuraNightGardenSpec.backgroundId,
          accentHue: 341,
        ),
        child: _BootstrapGate(
          applicationFuture: applicationFuture,
          marketGateway: marketGateway,
          resourceMapConfiguration: resourceMapConfiguration,
          updateService: updateService,
          updateSource: updateSource,
          enableBetaUpdates: enableBetaUpdates,
          repeatFullSetupEveryApplicationVersion:
              repeatFullSetupEveryApplicationVersion,
          windowHost: windowHost,
        ),
      ),
    ),
  );
}

class _BootstrapGate extends StatefulWidget {
  const _BootstrapGate({
    required this.applicationFuture,
    required this.marketGateway,
    required this.resourceMapConfiguration,
    required this.updateService,
    required this.updateSource,
    required this.enableBetaUpdates,
    required this.repeatFullSetupEveryApplicationVersion,
    required this.windowHost,
  });

  final Future<ApplicationBundle> applicationFuture;
  final MarketPriceGateway? marketGateway;
  final ResourceMapWorkspaceConfiguration resourceMapConfiguration;
  final BetaUpdateService? updateService;
  final String? updateSource;
  final bool enableBetaUpdates;
  final bool repeatFullSetupEveryApplicationVersion;
  final WindowHostService windowHost;

  @override
  State<_BootstrapGate> createState() => _BootstrapGateState();
}

class _BootstrapGateState extends State<_BootstrapGate> {
  ApplicationBundle? _resolvedBundle;
  FirstLaunchMigrationResolution? _migrationOutcome;
  bool _resolvingMigration = false;
  Object? _migrationError;
  bool _setupDismissedForSession = false;
  bool _setupBusy = false;
  bool _setupCompletionPending = false;
  Object? _setupError;

  @override
  void didUpdateWidget(_BootstrapGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.applicationFuture, widget.applicationFuture)) {
      _resolvedBundle = null;
      _migrationOutcome = null;
      _resolvingMigration = false;
      _migrationError = null;
      _setupDismissedForSession = false;
      _setupBusy = false;
      _setupCompletionPending = false;
      _setupError = null;
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<ApplicationBundle>(
    future: widget.applicationFuture,
    builder: (context, snapshot) {
      if (snapshot.hasError) return _StartupFailure(error: snapshot.error);
      final bundle = _resolvedBundle ?? snapshot.data;
      if (bundle == null) return const _StartupLoading();
      if (_migrationOutcome case final outcome?) {
        return FirstLaunchMigrationReportView(
          outcome: outcome,
          onContinue: () => setState(() => _migrationOutcome = null),
        );
      }
      if (bundle.firstLaunchMigration case final migration?) {
        return FirstLaunchMigrationPreviewView(
          migration: migration,
          busy: _resolvingMigration,
          error: _migrationError,
          onImport: migration.preview.canImport
              ? () => _resolveMigration(bundle, import: true)
              : null,
          onStartFresh: () => _resolveMigration(bundle, import: false),
        );
      }
      final setupProgress = FirstRunSetupProgress.fromDocument(
        bundle.controller.documentSnapshot,
        repeatForApplicationVersion:
            widget.repeatFullSetupEveryApplicationVersion
            ? AppIdentity.applicationVersion
            : '',
      );
      if (!_setupDismissedForSession &&
          (setupProgress.shouldShow || _setupCompletionPending)) {
        return FirstRunSetupView(
          document: bundle.controller.documentSnapshot,
          groups: setupProgress.pendingGroups,
          busy: _setupBusy,
          error: _setupError,
          onSkip: () => _skipSetup(bundle),
          onFinish: (answers) =>
              _finishSetup(bundle, setupProgress.pendingGroups, answers),
        );
      }
      return ApplicationWorkspace(
        bundle: bundle,
        marketGateway: widget.marketGateway,
        resourceMapConfiguration: widget.resourceMapConfiguration,
        updateService: widget.updateService,
        updateSource: widget.updateSource,
        enableBetaUpdates: widget.enableBetaUpdates,
        windowHost: widget.windowHost,
      );
    },
  );

  Future<void> _resolveMigration(
    ApplicationBundle source, {
    required bool import,
  }) async {
    if (_resolvingMigration) return;
    final migration = source.firstLaunchMigration!;
    final confirmed = await _confirmMigrationChoice(
      migration.preview,
      import: import,
    );
    if (!mounted || !confirmed) return;
    setState(() {
      _resolvingMigration = true;
      _migrationError = null;
    });
    try {
      final resolved = import
          ? await migration.accept()
          : await migration.startFresh();
      if (!mounted) return;
      setState(() {
        _resolvedBundle = resolved;
        _migrationOutcome = FirstLaunchMigrationResolution(
          imported: import,
          preview: migration.preview,
          bundle: resolved,
        );
        _setupDismissedForSession = false;
        _setupError = null;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _migrationError = error);
    } finally {
      if (mounted) setState(() => _resolvingMigration = false);
    }
  }

  Future<void> _skipSetup(ApplicationBundle bundle) async {
    if (_setupBusy) return;
    setState(() {
      _setupBusy = true;
      _setupError = null;
    });
    try {
      await bundle.controller.skipFirstRunSetup();
      if (!mounted) return;
      setState(() {
        _setupDismissedForSession = true;
        _setupBusy = false;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _setupError = error;
        _setupBusy = false;
      });
    }
  }

  Future<void> _finishSetup(
    ApplicationBundle bundle,
    List<FirstRunSetupGroup> groups,
    FirstRunSetupAnswers answers,
  ) async {
    if (_setupBusy) return;
    setState(() {
      _setupBusy = true;
      _setupCompletionPending = true;
      _setupError = null;
    });
    try {
      await bundle.controller.finishFirstRunSetup(
        answers,
        groups: groups,
        completedForApplicationVersion:
            widget.repeatFullSetupEveryApplicationVersion
            ? AppIdentity.applicationVersion
            : '',
      );
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _setupError = error;
        _setupBusy = false;
        _setupCompletionPending = false;
      });
      return;
    }
    if (!mounted) return;
    final bool acknowledged;
    try {
      acknowledged = await _showSetupSettingsLocation();
    } on Object catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'Black Spirit Life first-run setup',
          context: ErrorDescription(
            'while showing the saved setup settings-location notice',
          ),
        ),
      );
      if (mounted) setState(() => _setupBusy = false);
      return;
    }
    if (!mounted || !acknowledged) {
      if (mounted) setState(() => _setupBusy = false);
      return;
    }
    setState(() {
      _setupBusy = false;
      _setupCompletionPending = false;
    });
  }

  Future<bool> _showSetupSettingsLocation() async =>
      await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => PopScope(
          canPop: false,
          child: DraggableModalRouteSurface(
            overlayId: 'first-run-setup-settings-location',
            insetPadding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: AppSurface(
                key: const ValueKey<String>('first-run-setup-location-notice'),
                role: AppSurfaceRole.modal,
                padding: const EdgeInsets.all(20),
                semanticLabel: 'Setup settings location',
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    const Text(
                      'You can change these settings later in Craft Profile.',
                    ),
                    const SizedBox(height: 18),
                    Align(
                      alignment: Alignment.centerRight,
                      child: AppButton.label(
                        'Okay',
                        key: const ValueKey<String>(
                          'first-run-setup-location-okay',
                        ),
                        autofocus: true,
                        role: AppButtonRole.primary,
                        onPressed: () => Navigator.pop(dialogContext, true),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ) ??
      false;

  Future<bool> _confirmMigrationChoice(
    PlannerStateMigrationPreview preview, {
    required bool import,
  }) async =>
      await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => DraggableModalRouteSurface(
          overlayId: import
              ? 'confirm-migration-import'
              : 'confirm-clean-profile',
          insetPadding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: AppSurface(
              role: AppSurfaceRole.modal,
              tone: AppSurfaceTone.warning,
              semanticLabel: import
                  ? 'Confirm state import'
                  : 'Start clean profile',
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  DraggableOverlayDragRegion(
                    key: const ValueKey<String>('migration-confirm-drag'),
                    child: SectionHeader(
                      title: import
                          ? 'Confirm state import'
                          : 'Start clean profile?',
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    import
                        ? 'Import the previewed ${preview.sourceByteCount} byte copy into ${AppIdentity.productName}? The Avalonia file remains untouched.'
                        : 'Create a clean Flutter profile without importing the Avalonia state? The Avalonia file remains available and untouched.',
                  ),
                  const SizedBox(height: 20),
                  Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 8,
                    runSpacing: 8,
                    children: <Widget>[
                      AppButton.label(
                        'Cancel',
                        key: const ValueKey<String>('migration-confirm-cancel'),
                        autofocus: true,
                        onPressed: () => Navigator.pop(dialogContext, false),
                      ),
                      AppButton.label(
                        import ? 'Import Copy' : 'Start Fresh',
                        key: ValueKey<String>(
                          import
                              ? 'migration-confirm-import'
                              : 'migration-confirm-fresh',
                        ),
                        role: AppButtonRole.primary,
                        onPressed: () => Navigator.pop(dialogContext, true),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ) ??
      false;
}

class _StartupLoading extends StatelessWidget {
  const _StartupLoading();

  @override
  Widget build(BuildContext context) {
    final spec = context.visualTheme;
    return _StartupFrame(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Semantics(
            liveRegion: true,
            label: 'Loading the complete BDO catalog and planner state',
            child: AppSurface(
              role: AppSurfaceRole.popup,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
              semanticLabel: 'Planner startup loading',
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    WorldRootStartupAnimation(
                      dimension: (MediaQuery.sizeOf(context).shortestSide * .26)
                          .clamp(144.0, 220.0),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Preparing your planner',
                      textAlign: TextAlign.center,
                      style: spec.typography.section,
                    ),
                    const SizedBox(height: 12),
                    _StartupLoadingIndicator(color: spec.palette.trimBright),
                    const SizedBox(height: 8),
                    Text(
                      'Loading the complete catalog and saved state…',
                      textAlign: TextAlign.center,
                      style: spec.typography.meta.copyWith(
                        color: spec.palette.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StartupLoadingIndicator extends StatefulWidget {
  const _StartupLoadingIndicator({required this.color});

  final Color color;

  @override
  State<_StartupLoadingIndicator> createState() =>
      _StartupLoadingIndicatorState();
}

class _StartupLoadingIndicatorState extends State<_StartupLoadingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _rotation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1250),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _rotation
        ..stop()
        ..value = 0;
    } else if (!_rotation.isAnimating) {
      _rotation.repeat();
    }
  }

  @override
  void dispose() {
    _rotation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox.square(
      dimension: 22,
      child: RotationTransition(
        turns: _rotation,
        child: CircularProgressIndicator(
          key: const ValueKey<String>('startup-loading-indicator'),
          value: .72,
          strokeWidth: 2.2,
          strokeCap: StrokeCap.round,
          color: widget.color,
          backgroundColor: widget.color.withAlpha(32),
        ),
      ),
    ),
  );
}

class _StartupFailure extends StatelessWidget {
  const _StartupFailure({required this.error});

  final Object? error;

  @override
  Widget build(BuildContext context) {
    final spec = context.visualTheme;
    return _StartupFrame(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: AppSurface(
              role: AppSurfaceRole.modal,
              tone: AppSurfaceTone.danger,
              padding: const EdgeInsets.all(24),
              semanticLabel: 'Planner startup failed',
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  const SectionHeader(
                    title: '${AppIdentity.displayName} could not start.',
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'No test or fallback data was substituted. Restore or reconnect the folder or packaged file named below, then reopen the application.',
                    style: spec.typography.body.copyWith(
                      color: spec.palette.textMuted,
                    ),
                  ),
                  const SizedBox(height: 14),
                  AppSurface(
                    role: AppSurfaceRole.row,
                    tone: AppSurfaceTone.danger,
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Icon(
                          Icons.error_outline,
                          color: spec.palette.danger,
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: SelectableText(
                            '$error',
                            style: spec.typography.body,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StartupFrame extends StatelessWidget {
  const _StartupFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => AppStartupFrame(child: child);
}
