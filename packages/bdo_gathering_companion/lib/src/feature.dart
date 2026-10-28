import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'domain/models.dart';
import 'gathering_companion_home.dart';
import 'recipe_checklist.dart';
import 'services/gathering_durability_controller.dart';
import 'services/native_bridge.dart';
import 'services/session_store.dart';
import 'services/session_import_inbox.dart';
import 'services/shared_market_loader.dart';
import 'services/stable_v017_migration.dart';
import 'ui/theme.dart';
import 'ui/visual_palette.dart';
import 'widgets/spot_video_player.dart';

class GatheringCompanionFeature extends StatefulWidget {
  const GatheringCompanionFeature({
    super.key,
    this.dataDirectory,
    this.prepareDataDirectory,
    this.durabilityController,
    this.sharedMarketLoader,
    this.sharedMarketUpdates,
    this.marketFreshFor = const Duration(minutes: 2),
    this.visualPalette,
    this.recipeChecklistBuilder,
    this.recipeChecklistController,
  });

  final Directory? dataDirectory;
  final Future<void> Function(Directory directory)? prepareDataDirectory;
  final GatheringDurabilityController? durabilityController;
  final GatheringSharedMarketLoader? sharedMarketLoader;
  final Stream<GatheringMarketReceipt>? sharedMarketUpdates;
  final Duration marketFreshFor;
  final CompanionVisualPalette? visualPalette;
  final GatheringRecipeChecklistBuilder? recipeChecklistBuilder;
  final GatheringRecipeChecklistController? recipeChecklistController;

  @override
  State<GatheringCompanionFeature> createState() =>
      _GatheringCompanionFeatureState();
}

class _GatheringCompanionFeatureState extends State<GatheringCompanionFeature> {
  Catalog? _catalog;
  SessionStore? _store;
  Object? _error;
  int _glassOpacityPercent = defaultGlassOpacityPercent;
  int _loadGeneration = 0;
  SessionImportInbox? _sessionImportInbox;
  final GatheringDurabilityController _ownedDurabilityController =
      GatheringDurabilityController();

  GatheringDurabilityController get _durabilityController =>
      widget.durabilityController ?? _ownedDurabilityController;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant GatheringCompanionFeature oldWidget) {
    super.didUpdateWidget(oldWidget);
    final store = _store;
    if (oldWidget.durabilityController != widget.durabilityController &&
        store != null) {
      (oldWidget.durabilityController ?? _ownedDurabilityController).detach(
        store,
      );
      _attachDurability(store);
    }
    if (oldWidget.dataDirectory?.path != widget.dataDirectory?.path) {
      _load();
    }
  }

  Future<void> _load() async {
    final generation = ++_loadGeneration;
    final previousStore = _store;
    _sessionImportInbox?.dispose();
    _sessionImportInbox = null;
    if (previousStore != null) _durabilityController.detach(previousStore);
    setState(() {
      _catalog = null;
      _store = null;
      _error = null;
    });
    try {
      final directory = widget.dataDirectory;
      if (directory != null) {
        await migrateStableV017GatheringData(directory: directory);
        await widget.prepareDataDirectory?.call(directory);
        configureSpotVideoCacheRoot(
          Directory(
            '${directory.absolute.path}${Platform.pathSeparator}video-webview',
          ),
        );
        await cleanupSpotVideoCache();
      }
      final store = SessionStore(directory: widget.dataDirectory);
      final catalog = await Catalog.load();
      await store.load();
      if (!mounted || generation != _loadGeneration) return;
      final inbox = SessionImportInbox(
        store: store,
        catalog: catalog,
        onChanged: () {
          if (mounted && generation == _loadGeneration) setState(() {});
        },
      );
      _sessionImportInbox = inbox;
      _attachDurability(store);
      setState(() {
        _catalog = catalog;
        _store = store;
        _glassOpacityPercent = normalizeGlassOpacity(
          store.preferences[glassOpacityPreferenceKey],
        );
      });
      if (!_durabilityController.isFrozen) inbox.start();
    } catch (error) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() => _error = error);
    }
  }

  void _attachDurability(SessionStore store) {
    _durabilityController.attach(
      store: store,
      releaseTransientResources: _pauseRuntime,
      resumeTransientResources: _resumeRuntime,
    );
  }

  Future<void> _pauseRuntime() async {
    await Future.wait(<Future<void>>[
      pauseSpotVideoResources(),
      NativeBridge.shutdownSessionImport(),
      if (_sessionImportInbox case final inbox?) inbox.pause(),
    ]);
  }

  Future<void> _resumeRuntime() async {
    resumeSpotVideoResources();
    if (mounted) _sessionImportInbox?.start();
  }

  void _previewGlassOpacity(int value) {
    final normalized = normalizeGlassOpacity(value);
    if (normalized != _glassOpacityPercent) {
      setState(() => _glassOpacityPercent = normalized);
    }
  }

  @override
  void dispose() {
    _loadGeneration++;
    _sessionImportInbox?.dispose();
    if (_store case final store?) _durabilityController.detach(store);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BDO Gathering Companion',
      debugShowCheckedModeBanner: false,
      theme: companionTheme(
        opacityPercent: _glassOpacityPercent,
        visualPalette: widget.visualPalette,
      ),
      builder: companionBackdropBuilder,
      scrollBehavior: const MaterialScrollBehavior().copyWith(
        scrollbars: false,
      ),
      home: Builder(
        builder: (context) {
          final catalog = _catalog;
          final store = _store;
          if (catalog != null && store != null) {
            return CompanionHome(
              recipeChecklistBuilder: widget.recipeChecklistBuilder,
              recipeChecklistController: widget.recipeChecklistController,
              catalog: catalog,
              store: store,
              glassOpacityPercent: _glassOpacityPercent,
              onGlassOpacityChanged: _previewGlassOpacity,
              sharedMarketLoader: widget.sharedMarketLoader,
              sharedMarketUpdates: widget.sharedMarketUpdates,
              marketFreshFor: widget.marketFreshFor,
              sessionImportReceiptDirectory: _sessionImportInbox?.directoryPath,
              sessionImportError: _sessionImportInbox?.lastError,
              onRetrySessionImport: () {
                final inbox = _sessionImportInbox;
                if (inbox != null) unawaited(inbox.drain());
              },
            );
          }
          return ColoredBox(
            color: Colors.transparent,
            child: Center(
              child: _error == null
                  ? const CircularProgressIndicator()
                  : ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 620),
                      child: GlassSurface(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Gathering data could not be opened',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 10),
                            const Text(
                              'Your saved sessions were left unchanged. Retry after checking that the app data folder is available.',
                            ),
                            const SizedBox(height: 10),
                            SelectableText(_error.toString()),
                            const SizedBox(height: 16),
                            FilledButton.icon(
                              onPressed: _load,
                              icon: const Icon(Icons.refresh),
                              label: const Text('Retry'),
                            ),
                          ],
                        ),
                      ),
                    ),
            ),
          );
        },
      ),
    );
  }
}
