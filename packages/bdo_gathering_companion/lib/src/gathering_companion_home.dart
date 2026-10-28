import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'assets.dart';
import 'recipe_checklist.dart';
import 'widgets/spot_map.dart';
import 'domain/bairog_benchmarks.dart';
import 'domain/bairog_calculator.dart';
import 'domain/gathering_preparation.dart';
import 'domain/models.dart';
import 'domain/pets.dart';
import 'services/native_bridge.dart';
import 'services/session_store.dart';
import 'services/shared_market_loader.dart';
import 'services/stable_v017_migration.dart';
import 'ui/buff_picker.dart';
import 'ui/field_desk_materials.dart';
import 'ui/field_guide.dart';
import 'ui/gathering_setup_dialog.dart';
import 'ui/gathering_preparation_panel.dart';
import 'ui/loot_panel.dart';
import 'ui/stable_v017_loadout_notes_card.dart';
import 'ui/theme.dart';
import 'ui/expedition_chrome.dart';

class CompanionHome extends StatefulWidget {
  const CompanionHome({
    super.key,
    required this.catalog,
    required this.store,
    required this.glassOpacityPercent,
    required this.onGlassOpacityChanged,
    this.sharedMarketLoader,
    this.sharedMarketUpdates,
    this.marketFreshFor = const Duration(minutes: 2),
    this.sessionImportReceiptDirectory,
    this.sessionImportError,
    this.onRetrySessionImport,
    this.recipeChecklistBuilder,
    this.recipeChecklistController,
  });
  final Catalog catalog;
  final SessionStore store;
  final int glassOpacityPercent;
  final ValueChanged<int> onGlassOpacityChanged;
  final GatheringSharedMarketLoader? sharedMarketLoader;
  final Stream<GatheringMarketReceipt>? sharedMarketUpdates;
  final Duration marketFreshFor;
  final String? sessionImportReceiptDirectory;
  final String? sessionImportError;
  final VoidCallback? onRetrySessionImport;
  final GatheringRecipeChecklistBuilder? recipeChecklistBuilder;
  final GatheringRecipeChecklistController? recipeChecklistController;
  @override
  State<CompanionHome> createState() => _CompanionHomeState();
}

class _CompanionHomeState extends State<CompanionHome> {
  bool _recipeChecklistOpen = false;
  bool _returnToRecipeChecklist = false;
  GatheringRecipeLocations? _recipeLocations;
  void _restoreRecipeChecklist() => setState(() {
    _recipeChecklistOpen = true;
    _recipeLocations = null;
    _returnToRecipeChecklist = false;
  });
  void _checkRecipeRequest() {
    if (!mounted || widget.recipeChecklistController?.pending != true) return;
    widget.recipeChecklistController!.pending = false;
    setState(() => _recipeChecklistOpen = true);
  }

  Spot? _recipeSpot(String name) => catalog.spots
      .where(
        (spot) =>
            spot.mapped &&
            spot.methodIds.any(
              (method) => catalog
                  .lootForSpot(spot, method)
                  .any((item) => item.name.toLowerCase() == name.toLowerCase()),
            ),
      )
      .firstOrNull;
  int _page = 2;
  final _fieldDeskRevision = ValueNotifier<int>(0);
  String? _buffMethodId;
  String? _buffSpotId;
  bool get _hostedFieldDesk => context.glass.visualPalette != null;
  String get _recommendationMethod => _buffMethodId ?? _methodId;
  String get _recommendationLabel => switch (_recommendationMethod) {
    'hunting' => 'Matchlock',
    'sniper' => 'Sniper',
    _ => 'Gathering',
  };
  GlobalKey _lootPanelKey = GlobalKey(debugLabel: 'draft-loot');
  final _entryScroll = ScrollController();
  late String _methodId;
  String? _spotId;
  Spot? _guideSpot;
  int _guideRevision = 0;
  bool _guideVisited = true, _saving = false, _buffsEdited = true;
  bool _opacitySaving = false;
  bool _estimateSetupSaving = false;
  bool _lootInputValid = true;
  bool _inlineStatsValid = true;
  Object _inlineStatsContext = Object();
  String? _notice;
  late GatheringPreparation _preparation;
  late GatheringPreparation _persistedPreparation;
  GatheringPreparation? _returnPreparation;
  bool _statsEdited = true;
  bool _preparationPreview = false;
  bool _preparationTransition = false;
  Future<void> _preparationWrites = Future<void>.value();
  int _preparationWriteRevision = 0;
  Set<String> get _buffIds => _preparation.activeBuffIds(catalog).toSet();
  Set<String> get _petIds => _preparation.petIds;
  List<PetRecommendation> _petCatalog = const [];
  bool _petCatalogRequested = false;
  bool _petsEdited = true;
  Map<String, LootEntry> _loot = {};
  final _minutes = TextEditingController(text: '30');
  final _notes = TextEditingController();
  final _customSpot = TextEditingController();
  final _historySearch = TextEditingController();
  String _historyQuery = '';
  String? _historyMethodId;
  DateTimeRange? _historyDates;
  DateTime _date = DateTime.now();
  DateTime? _timerStart;
  int _timerAccumulated = 0;
  Timer? _tick;
  GatheringSession? _editing;
  BairogCalculatorSettings get _estimateSetup {
    if (_editing != null && !_buffsEdited && !_preparationPreview) {
      final frozen = objectMap(
        _editing!.preparationSnapshot?['effectiveSettings'],
      );
      if (!_statsEdited && frozen.isNotEmpty) {
        final settings = BairogCalculatorSettings.fromJson(frozen);
        return _petsEdited
            ? settings.copyWith(
                hedgehogTier: _preparation.baseSettings.hedgehogTier,
              )
            : settings;
      }
      // Old records have no estimate setup. Only use their recorded base and
      // buff observations, never today's global profile or revised catalog.
      return _preparation.baseSettings.copyWith(
        mastery:
            ((_statsEdited
                        ? _preparation.baseSettings.mastery
                        : _editing!.mastery) +
                    (_editing!.buffTotals['lifeMastery'] ?? 0) +
                    (_editing!.buffTotals['gatheringMastery'] ?? 0))
                .round()
                .clamp(0, 3000),
        gatheringDropRatePercent:
            _preparation.baseSettings.gatheringDropRatePercent +
            (_editing!.buffTotals['gatheringItemDropPct'] ?? 0),
      );
    }
    return _preparation.effectiveSettings(catalog);
  }

  Catalog get catalog => widget.catalog;
  Method get method => catalog.methods.firstWhere(
    (m) => m.id == _methodId,
    orElse: () => catalog.methods.first,
  );
  Spot? get spot => catalog.spots.where((s) => s.id == _spotId).firstOrNull;
  String get spotName =>
      spot?.name ?? (_spotId == 'custom' ? _customSpot.text.trim() : '');
  int get _elapsed =>
      _timerAccumulated +
      (_timerStart == null
          ? 0
          : DateTime.now().difference(_timerStart!).inSeconds);
  int get seconds {
    if (_timerStart != null) return _elapsed;
    final value =
        (double.tryParse(_minutes.text.replaceAll(',', '.')) ?? 0) * 60;
    if (!value.isFinite || value > 604800) return 604801;
    return value.round();
  }

  Map<String, double> get _totals => _editing != null && !_buffsEdited
      ? _editing!.buffTotals
      : catalog.sumBuffs(_buffIds);
  int get _baseMastery => _editing != null && !_statsEdited
      ? _editing!.mastery
      : _preparation.statsConfirmed
      ? _preparation.baseSettings.mastery
      : _editing?.mastery ?? 0;
  int get _totalItems => _loot.values.fold(0, (n, e) => n + e.total);

  @override
  void initState() {
    super.initState();
    widget.recipeChecklistController?.addListener(_checkRecipeRequest);
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkRecipeRequest());
    try {
      _preparation = GatheringPreparation.fromPreferences(
        widget.store.preferences,
        catalog: catalog,
      );
    } catch (_) {
      _preparation = GatheringPreparation();
    }
    _persistedPreparation = _preparation;
    _methodId = catalog.methods.first.id;
    final lastMethod = widget.store.preferences['methodId'];
    if (catalog.methods.any((m) => m.id == lastMethod)) {
      _methodId = lastMethod.toString();
    }
    final lastSpot = widget.store.preferences['spotId'];
    if (catalog.spots.any(
      (s) => s.id == lastSpot && s.methodIds.contains(_methodId),
    )) {
      _spotId = lastSpot.toString();
    }
    _buffMethodId = _methodId;
    _buffSpotId = _spotId;
    for (final c in [_minutes, _customSpot]) {
      c.addListener(_refresh);
    }
    if (widget.store.recoveredBackup) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _message(
          'Recovered your last valid backup. The damaged file has not been overwritten.',
        ),
      );
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The cached catalog can complete synchronously. Hosted applicability
    // depends on the inherited theme, which is not available during initState.
    if (!_petCatalogRequested) {
      _petCatalogRequested = true;
      unawaited(_loadPets());
    }
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(covariant CompanionHome oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.recipeChecklistController !=
        widget.recipeChecklistController) {
      oldWidget.recipeChecklistController?.removeListener(_checkRecipeRequest);
      widget.recipeChecklistController?.addListener(_checkRecipeRequest);
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _checkRecipeRequest(),
      );
    }
  }

  @override
  void dispose() {
    widget.recipeChecklistController?.removeListener(_checkRecipeRequest);
    _fieldDeskRevision.dispose();
    _tick?.cancel();
    _entryScroll.dispose();
    for (final c in [_minutes, _notes, _customSpot, _historySearch]) {
      c.dispose();
    }
    super.dispose();
  }

  void _message(String message) {
    if (!mounted) return;
    setState(() => _notice = message);
  }

  Future<void> _showEstimateSetup() async {
    if (_estimateSetupSaving ||
        _opacitySaving ||
        _saving ||
        _preparationTransition) {
      return;
    }
    if (!_inlineStatsValid) {
      _navigate(3);
      _message('Finish or reset the highlighted stats in Prepare.');
      return;
    }
    if (_timerStart != null) {
      _message('Pause gathering before changing your preparation.');
      return;
    }
    final previous = _preparation;
    final next = await showGatheringSetupDialog(
      context: context,
      catalog: catalog,
      initial: previous.baseSettings,
      preparationLabel: _hostedFieldDesk ? 'Buffs' : 'Prepare',
      onPreview: (draft) {
        if (mounted) {
          setState(() {
            _preparationPreview = true;
            _preparation = previous.withBaseSettings(draft, catalog);
          });
        }
      },
    );
    if (!mounted) return;
    setState(() {
      _preparation = previous;
      _preparationPreview = false;
    });
    if (next != null) {
      _changePreparation(
        previous.withBaseSettings(next, catalog, statsConfirmed: true),
        statsEdited: true,
      );
      await _drainPreparationWrites();
    }
  }

  void _changePreparation(
    GatheringPreparation next, {
    bool statsEdited = false,
  }) {
    if (_saving ||
        _opacitySaving ||
        _preparationTransition ||
        _timerStart != null) {
      return;
    }
    if (_preparation.hasSameValuesAs(next)) return;
    final buffsChanged =
        _preparation.buffIds.length != next.buffIds.length ||
        !_preparation.buffIds.containsAll(next.buffIds);
    final petsChanged =
        _preparation.petIds.length != next.petIds.length ||
        !_preparation.petIds.containsAll(next.petIds);
    setState(() {
      _preparation = next;
      _statsEdited = _statsEdited || statsEdited;
      _buffsEdited = _buffsEdited || buffsChanged;
      _petsEdited = _petsEdited || petsChanged;
      _notice = null;
    });
    _fieldDeskRevision.value++;
    // Editing an old run changes that run only, never the current saved kit.
    if (_editing != null) return;
    final preparedMethodId = _hostedFieldDesk
        ? _recommendationMethod
        : method.id;
    final preparedSpotId = _hostedFieldDesk
        ? _buffSpotId ?? ''
        : spot?.id ?? '';
    final revision = ++_preparationWriteRevision;
    setState(() => _estimateSetupSaving = true);
    _preparationWrites = _preparationWrites.then((_) async {
      final previousPreferences = Map<String, dynamic>.from(
        widget.store.preferences,
      );
      widget.store.preferences = {
        ...widget.store.preferences,
        'methodId': preparedMethodId,
        'spotId': preparedSpotId,
        gatheringPreparationPreferenceKey: next.toJson(),
        gatheringEstimatePreferenceKey: next
            .effectiveSettings(catalog)
            .toJson(),
      };
      try {
        await widget.store.save();
        _persistedPreparation = next;
      } catch (error) {
        widget.store.preferences = previousPreferences;
        if (mounted && revision == _preparationWriteRevision) {
          setState(() => _preparation = _persistedPreparation);
          _fieldDeskRevision.value++;
          _message('Could not save your preparation. $error');
        }
      } finally {
        if (mounted && revision == _preparationWriteRevision) {
          setState(() => _estimateSetupSaving = false);
        }
      }
    });
  }

  Future<void> _drainPreparationWrites() async {
    while (true) {
      final pending = _preparationWrites;
      await pending;
      if (identical(pending, _preparationWrites)) return;
    }
  }

  void _changeInlineStats(BairogCalculatorSettings settings, bool confirmed) {
    _changePreparation(
      _preparation.withBaseSettings(
        settings,
        catalog,
        statsConfirmed: confirmed || _preparation.statsConfirmed,
      ),
      statsEdited: true,
    );
  }

  void _setInlineStatsValidity(bool valid) {
    if (mounted && valid != _inlineStatsValid) {
      setState(() => _inlineStatsValid = valid);
    }
  }

  String get _estimateSetupTooltip =>
      'Edit base stats and gathering options.\n'
      'Estimates include selected buffs.\n$_estimateMinigameLabel';

  String get _estimateMinigameLabel => switch (_estimateSetup.minigameMode) {
    BairogMinigameMode.none => 'No minigame',
    BairogMinigameMode.normal => 'Normal 5%',
    BairogMinigameMode.event => 'Event 10%',
  };

  Widget _estimateSetupButton() {
    const artwork = GameIcon(
      'assets/icons/items/735353.webp',
      size: 26,
      grade: 3,
    );
    return Tooltip(
      message: _estimateSetupTooltip,
      child: TextButton.icon(
        key: const ValueKey('open-gathering-setup'),
        onPressed: _estimateSetupSaving ? null : _showEstimateSetup,
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
          textStyle: Theme.of(context).textTheme.labelLarge!.copyWith(
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        icon: artwork,
        label: const Text('Your stats'),
      ),
    );
  }

  Future<void> _openBairogSource() async {
    try {
      if (await NativeBridge.openExternal(bairogBenchmarkSet.calculatorUrl)) {
        return;
      }
      _message('Could not open Bairog · BDO Workshop.');
    } catch (error) {
      _message('Could not open Bairog · BDO Workshop. $error');
    }
  }

  Widget _bairogSourceButton() => Semantics(
    label: 'Open Bairog · BDO Workshop gathering calculator',
    link: true,
    child: Tooltip(
      message: 'Bairog',
      child: IconButton(
        key: const ValueKey('open-bairog-source'),
        onPressed: _openBairogSource,
        style: IconButton.styleFrom(
          minimumSize: const Size.square(46),
          padding: const EdgeInsets.all(6),
          visualDensity: VisualDensity.standard,
        ),
        icon: const GameIcon(
          'assets/icons/sources/bdoworkshop_logo.png',
          size: 34,
          backgroundColor: Colors.transparent,
        ),
      ),
    ),
  );

  void _browseContext(Spot? selected, String? methodId) {
    if (!_hostedFieldDesk) return;
    final next = methodId == null || methodId == 'all'
        ? _recommendationMethod
        : methodId;
    if (_buffMethodId == next && _buffSpotId == selected?.id) return;
    setState(() {
      _buffMethodId = next;
      _buffSpotId = selected?.id;
    });
  }

  Future<void> _openGarmothApp() async {
    try {
      if (await NativeBridge.openExternal('https://garmoth.com/app')) return;
      _message('Could not open Garmoth App.');
    } catch (_) {
      _message('Could not open Garmoth App.');
    }
  }

  Future<void> _showRecommendedBuffs() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => ValueListenableBuilder<int>(
        valueListenable: _fieldDeskRevision,
        builder: (context, revision, _) => Dialog(
          key: const ValueKey('gathering-buffs-dialog'),
          backgroundColor: Colors.transparent,
          elevation: 0,
          insetPadding: const EdgeInsets.all(18),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 480,
              maxHeight: MediaQuery.sizeOf(context).height - 36,
            ),
            child: GlassSurface(
              elevated: true,
              padding: const EdgeInsets.all(18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const GameIcon(
                        'assets/icons/buffs/791.webp',
                        size: 38,
                        recessed: true,
                      ),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Text(
                          'Recommended buffs',
                          style: TextStyle(
                            fontFamily: 'Georgia',
                            fontSize: 21,
                            fontWeight: FontWeight.w700,
                            color: context.gatheringColors.ink,
                          ),
                        ),
                      ),
                      IconButton(
                        key: const ValueKey('close-gathering-buffs'),
                        tooltip: 'Close',
                        onPressed: () => Navigator.pop(dialogContext),
                        icon: const Icon(Icons.close, size: 20),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final entry in [
                        ('butcher', 'Gathering'),
                        ('hunting', 'Matchlock'),
                        ('sniper', 'Sniper'),
                      ])
                        ChoiceChip(
                          key: ValueKey('buff-method-${entry.$1}'),
                          label: Text(entry.$2),
                          selected: entry.$2 == _recommendationLabel,
                          onSelected: (_) {
                            setState(() {
                              _buffMethodId = entry.$1;
                              _buffSpotId = null;
                            });
                            _fieldDeskRevision.value++;
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Flexible(
                    child: SingleChildScrollView(
                      key: const ValueKey('gathering-buffs-scroll'),
                      child: GatheringPreparationPanel(
                        compactRecommendations: true,
                        catalog: catalog,
                        methodId: _recommendationMethod,
                        spotId: _buffSpotId,
                        selectedBuffIds: _buffIds,
                        selectedPetIds: _petIds,
                        pets: _petCatalog,
                        baseSettings: _preparation.baseSettings,
                        effectiveSettings: _estimateSetup,
                        statsConfirmed: _preparation.statsConfirmed,
                        onToggleBuff: _toggleBuff,
                        onTogglePet: _togglePet,
                        onPreset: _preset,
                        onClearBuffs: _clearBuffs,
                        onClearPets: _clearPets,
                        onStatsChanged: _changeInlineStats,
                        onStatsValidityChanged: _setInlineStatsValidity,
                        onEditStats: () {
                          Navigator.pop(dialogContext);
                          _showEstimateSetup();
                        },
                      ),
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

  Widget _fieldDeskAction({
    required String keyName,
    required String title,
    required String detail,
    required String artwork,
    required VoidCallback? onTap,
  }) => GlassControl(
    radius: 8,
    leadingWidth: 49,
    copperInlay: true,
    child: InkWell(
      key: ValueKey(keyName),
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 60),
        child: Row(
          children: [
            SizedBox(
              width: 49,
              child: Center(child: GameIcon(artwork, size: 32, recessed: true)),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 9, 8, 11),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      detail,
                      style: TextStyle(
                        fontSize: 12,
                        color: context.gatheringColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _fieldDeskExternal({required bool garmoth}) => Semantics(
    link: true,
    child: TextButton(
      key: ValueKey(garmoth ? 'open-garmoth-app' : 'open-bairog-source'),
      onPressed: garmoth ? _openGarmothApp : _openBairogSource,
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 7),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          GameIcon(
            garmoth
                ? 'assets/icons/sources/garmoth_icon.png'
                : 'assets/icons/sources/bdoworkshop_logo.png',
            size: 28,
            backgroundColor: Colors.transparent,
          ),
          const SizedBox(width: 9),
          Flexible(child: Text(garmoth ? 'Garmoth App' : 'Bairog')),
          const SizedBox(width: 7),
          Icon(
            Icons.north_east,
            size: 14,
            color: context.gatheringColors.muted,
          ),
        ],
      ),
    ),
  );

  Widget _fieldDeskRail() => SingleChildScrollView(
    key: const ValueKey('gathering-field-rail-scroll'),
    padding: const EdgeInsets.fromLTRB(10, 12, 4, 12),
    child: GlassSurface(
      key: const ValueKey('gathering-field-rail'),
      padding: const EdgeInsets.fromLTRB(12, 18, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Gathering',
            style: TextStyle(
              fontFamily: 'Georgia',
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: context.gatheringColors.ink,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 17),
            child: Divider(height: 1, color: context.glass.strongLine),
          ),
          _fieldDeskAction(
            keyName: 'open-gathering-setup',
            title: 'Your stats',
            detail: 'Edit character',
            artwork: 'assets/icons/items/735353.webp',
            onTap: _estimateSetupSaving ? null : _showEstimateSetup,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 12, 10, 16),
            child: Column(
              children: [
                _fieldDeskStat(
                  'Mastery',
                  _preparation.statsConfirmed
                      ? countText(_preparation.baseSettings.mastery)
                      : '—',
                ),
                const SizedBox(height: 6),
                _fieldDeskStat(
                  'Drop rate',
                  _preparation.statsConfirmed
                      ? '${numberText(_preparation.baseSettings.gatheringDropRatePercent)}%'
                      : '—',
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Before buffs',
                    style: TextStyle(
                      fontSize: 12,
                      color: context.gatheringColors.muted,
                    ),
                  ),
                ),
              ],
            ),
          ),
          _fieldDeskAction(
            keyName: 'open-gathering-buffs',
            title: 'Buffs',
            detail: '$_recommendationLabel · ${_buffIds.length} selected',
            artwork: 'assets/icons/buffs/791.webp',
            onTap: _showRecommendedBuffs,
          ),
          if (widget.recipeChecklistBuilder != null) ...[
            const SizedBox(height: 10),
            TextButton.icon(
              key: const ValueKey('gathering-recipe-checklist'),
              onPressed: () =>
                  setState(() => _recipeChecklistOpen = !_recipeChecklistOpen),
              icon: const Icon(Icons.checklist_rounded),
              label: const Text('Checklist'),
            ),
          ],
          const SizedBox(height: 18),
          Text(
            'Guides & tracking',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: context.gatheringColors.muted,
            ),
          ),
          const SizedBox(height: 5),
          Align(
            alignment: Alignment.centerLeft,
            child: _fieldDeskExternal(garmoth: false),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: _fieldDeskExternal(garmoth: true),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 10, bottom: 5),
            child: Divider(height: 1, color: context.glass.line),
          ),
          Wrap(spacing: 1, runSpacing: 3, children: _workspaceUtilities()),
        ],
      ),
    ),
  );

  Widget _fieldDeskStat(String label, String value) => Row(
    children: [
      Expanded(
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            color: context.gatheringColors.muted,
          ),
        ),
      ),
      const SizedBox(width: 6),
      Text(
        value,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ],
  );

  Widget _fieldDeskToolbar() => Padding(
    padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
    child: Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _estimateSetupButton(),
        if (widget.recipeChecklistBuilder != null)
          TextButton.icon(
            key: const ValueKey('gathering-recipe-checklist'),
            onPressed: () =>
                setState(() => _recipeChecklistOpen = !_recipeChecklistOpen),
            icon: const Icon(Icons.checklist_rounded),
            label: const Text('Checklist'),
          ),
        TextButton.icon(
          key: const ValueKey('open-gathering-buffs'),
          onPressed: _showRecommendedBuffs,
          icon: const GameIcon('assets/icons/buffs/791.webp', size: 26),
          label: const Text('Buffs'),
        ),
        _fieldDeskExternal(garmoth: false),
        _fieldDeskExternal(garmoth: true),
      ],
    ),
  );

  Future<void> _persistGlassOpacity(int value) async {
    if (_opacitySaving || _estimateSetupSaving || _saving) return;
    final normalized = normalizeGlassOpacity(value);
    final previousValue = normalizeGlassOpacity(
      widget.store.preferences[glassOpacityPreferenceKey],
    );
    final previousPreferences = Map<String, dynamic>.from(
      widget.store.preferences,
    );
    widget.store.preferences = {
      ...widget.store.preferences,
      glassOpacityPreferenceKey: normalized,
    };
    setState(() => _opacitySaving = true);
    try {
      await widget.store.save();
    } catch (error) {
      widget.store.preferences = previousPreferences;
      widget.onGlassOpacityChanged(previousValue);
      _message('Could not save the glass opacity. $error');
    } finally {
      if (mounted) setState(() => _opacitySaving = false);
    }
  }

  Widget _glassOpacitySlider({bool dialog = false}) => Semantics(
    label: 'Glass opacity',
    value: '${widget.glassOpacityPercent} percent',
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!dialog)
          Text(
            'Opacity',
            style: TextStyle(
              color: context.gatheringColors.muted,
              fontSize: 12,
            ),
          ),
        if (!dialog) const SizedBox(width: 5),
        SizedBox(
          width: dialog ? 190 : 104,
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
            ),
            child: Slider(
              key: ValueKey(
                dialog ? 'glass-opacity-dialog-slider' : 'glass-opacity-slider',
              ),
              min: 0,
              max: 100,
              divisions: 100,
              value: widget.glassOpacityPercent.toDouble(),
              label: '${widget.glassOpacityPercent}%',
              onChanged: _opacitySaving || _estimateSetupSaving || _saving
                  ? null
                  : (value) => widget.onGlassOpacityChanged(value.round()),
              onChangeEnd: _opacitySaving || _estimateSetupSaving || _saving
                  ? null
                  : (value) => _persistGlassOpacity(value.round()),
            ),
          ),
        ),
        SizedBox(
          width: 38,
          child: Text(
            '${widget.glassOpacityPercent}%',
            key: ValueKey(
              dialog ? 'glass-opacity-dialog-value' : 'glass-opacity-value',
            ),
            textAlign: TextAlign.right,
            style: TextStyle(
              color: context.gatheringColors.ink,
              fontSize: 12,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    ),
  );

  Future<void> _showGlassOpacity() => showDialog<void>(
    context: context,
    builder: (dialogContext) => Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: GlassSurface(
          padding: const EdgeInsets.fromLTRB(20, 18, 14, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Glass opacity',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              _glassOpacitySlider(dialog: true),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Close'),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  void _navigate(int page) => setState(() {
    _page = page;
    if (page == 2) _guideVisited = true;
  });
  void _toggleBuff(Buff buff) {
    if (buff.referenceOnly) return;
    final ids = Set<String>.from(_buffIds);
    if (!ids.remove(buff.id)) {
      for (final b in catalog.selectedBuffs(ids)) {
        if (buff.conflictsWith(b)) {
          ids.remove(b.id);
        }
      }
      ids.add(buff.id);
    }
    _changePreparation(_preparation.withBuffIds(ids, catalog));
  }

  Future<void> _loadPets() async {
    final pets = await PetCatalog.load();
    if (!mounted) return;
    setState(() => _petCatalog = pets);
    _fieldDeskRevision.value++;
    if (_petsEdited) _reconcilePets();
  }

  void _reconcilePets() {
    // The hosted desk browses recommendations, not a session being recorded.
    // Visibility is filtered by method/spot in PetRecommendations; inspecting
    // another method must not remove a saved pet or clear its chosen tier.
    // Standalone session recording retains its original applicability checks.
    if (_hostedFieldDesk) return;
    if (_petCatalog.isEmpty ||
        (_editing != null && !_petsEdited) ||
        _timerStart != null ||
        _saving ||
        _preparationTransition) {
      return;
    }
    final ids = reconcileSelectedPetIds(
      selectedIds: _petIds,
      pets: _petCatalog,
      methodId: _methodId,
      spotId: spot?.id,
    ).toSet();
    _changePreparation(_preparation.withPetIds(ids));
  }

  Future<void> _togglePet(PetRecommendation pet) async {
    if (_saving ||
        _opacitySaving ||
        _preparationTransition ||
        _timerStart != null) {
      return;
    }
    await _drainPreparationWrites();
    if (!mounted ||
        _saving ||
        _opacitySaving ||
        _preparationTransition ||
        _timerStart != null) {
      return;
    }
    final ids = Set<String>.from(_petIds);
    final adding = !ids.remove(pet.id);
    if (adding) {
      if (gatheringExtraProcPetIds.contains(pet.id)) {
        ids.removeAll(gatheringExtraProcPetIds);
      }
      ids.add(pet.id);
    }
    var next = _preparation.withPetIds(ids);
    if (adding &&
        gatheringExtraProcPetIds.contains(pet.id) &&
        next.baseSettings.hedgehogTier == BairogHedgehogTier.none) {
      final tier = await showDialog<BairogHedgehogTier>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('${pet.name} tier'),
          content: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final tier in BairogHedgehogTier.values.where(
                (t) => t != BairogHedgehogTier.none,
              ))
                OutlinedButton(
                  onPressed: () => Navigator.pop(context, tier),
                  child: Text(
                    tier == BairogHedgehogTier.tier4
                        ? 'T4–5'
                        : 'T${tier.storageValue}',
                  ),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
          ],
        ),
      );
      if (!mounted ||
          tier == null ||
          _saving ||
          _opacitySaving ||
          _preparationTransition) {
        return;
      }
      next = next.withBaseSettings(
        next.baseSettings.copyWith(hedgehogTier: tier),
        catalog,
      );
    }
    _changePreparation(next);
  }

  void _clearPets() => _changePreparation(_preparation.withPetIds({}));

  void _clearBuffs() =>
      _changePreparation(_preparation.withBuffIds({}, catalog));

  void _preset(Map<String, dynamic> preset) {
    final ids = Set<String>.from(_buffIds);
    for (final id in strings(preset['buffIds'])) {
      final buff = catalog.buffs.where((b) => b.id == id).firstOrNull;
      if (buff == null) continue;
      ids.removeWhere(
        (selected) => buff.conflictsWith(
          catalog.buffs.firstWhere((b) => b.id == selected),
        ),
      );
      ids.add(id);
    }
    _changePreparation(_preparation.withBuffIds(ids, catalog));
  }

  void _timer() {
    if (_saving ||
        _opacitySaving ||
        _preparationTransition ||
        (_timerStart == null && _estimateSetupSaving)) {
      return;
    }
    if (_timerStart != null) {
      _timerAccumulated = _elapsed;
      _timerStart = null;
      _tick?.cancel();
      _minutes.text = (_timerAccumulated / 60).toStringAsFixed(2);
    } else {
      _timerStart = DateTime.now();
      _tick = Timer.periodic(const Duration(seconds: 1), (_) => _refresh());
    }
    _refresh();
  }

  void _resetDraft() {
    _tick?.cancel();
    _timerStart = null;
    _timerAccumulated = 0;
    _loot = {};
    _lootPanelKey = GlobalKey(debugLabel: 'draft-loot');
    _editing = null;
    if (_returnPreparation != null) {
      _preparation = _returnPreparation!;
      _returnPreparation = null;
    }
    _buffsEdited = true;
    _petsEdited = true;
    _statsEdited = true;
    _preparationPreview = false;
    _lootInputValid = true;
    _inlineStatsValid = true;
    _inlineStatsContext = Object();
    _notice = null;
    _date = DateTime.now();
    _minutes.text = '30';
    _notes.clear();
  }

  Future<bool> _confirm(String title, String message, String action) async =>
      await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: Text(action),
            ),
          ],
        ),
      ) ??
      false;
  Future<void> _newDraft() async {
    if (_saving || _opacitySaving || _preparationTransition) return;
    await _drainPreparationWrites();
    if (!mounted || _saving || _opacitySaving) return;
    if ((!_inlineStatsValid ||
            !_lootInputValid ||
            _loot.isNotEmpty ||
            _timerStart != null ||
            _timerAccumulated > 0 ||
            _editing != null ||
            _notes.text.trim().isNotEmpty) &&
        !await _confirm(
          'Start a new session?',
          'The current unsaved draft will be cleared. Saved sessions stay unchanged.',
          'New session',
        )) {
      return;
    }
    if (!mounted) return;
    setState(() {
      _resetDraft();
      _page = 0;
    });
  }

  Future<void> _save() async {
    if (_saving || _opacitySaving || _preparationTransition) return;
    _reconcilePets();
    setState(() => _preparationTransition = true);
    try {
      await _drainPreparationWrites();
    } finally {
      if (mounted) setState(() => _preparationTransition = false);
    }
    if (!mounted || _saving || _opacitySaving) return;
    if (!_lootInputValid) {
      _message('Check the highlighted quantities before saving.');
      return;
    }
    if (!_inlineStatsValid) {
      _message('Finish or reset the highlighted stats in Prepare.');
      return;
    }
    if (spotName.isEmpty) {
      _message('Choose a spot, or enter your own location.');
      return;
    }
    if (seconds <= 0 || seconds > 604800) {
      _message(
        'Enter a duration greater than zero and no longer than seven days.',
      );
      return;
    }
    if (_loot.isEmpty || _totalItems <= 0) {
      _message('Add at least one gathered item before saving.');
      return;
    }
    if (_loot.values.any((e) => e.rawTotal < 0)) {
      _message(
        'Review negative item totals before saving. Check the starting amounts and maid transfers.',
      );
      return;
    }
    setState(() => _saving = true);
    final duration = seconds;
    final frozen = _editing != null && !_buffsEdited;
    final frozenPets = _editing != null && !_petsEdited;
    final session = GatheringSession(
      id: _editing?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
      createdAt: _date,
      methodId: method.id,
      methodLabel: method.label,
      methodIcon: method.icon,
      spotId: spot?.id ?? '',
      spotName: spotName,
      durationSeconds: duration,
      mastery: _baseMastery,
      notes: _notes.text.trim(),
      sessionImport: _editing?.sessionImport,
      loot: _loot.values
          .where(
            (e) =>
                e.total > 0 ||
                e.hasInventorySnapshot ||
                e.start != 0 ||
                e.remaining != 0 ||
                e.sentAway != 0,
          )
          .map((e) => LootEntry.fromJson(e.toJson()))
          .toList(),
      buffs: frozen
          ? _editing!.buffs
          : catalog.selectedBuffs(_buffIds).map((b) => b.snapshot()).toList(),
      pets: frozenPets
          ? _editing!.pets
          : _petCatalog
                .where((pet) => _petIds.contains(pet.id))
                .map(
                  (pet) => <String, dynamic>{
                    'id': pet.id,
                    'name': pet.name,
                    'icon': pet.icon,
                    'summary': pet.summary,
                  },
                )
                .toList(),
      buffTotals: Map.from(_totals),
      catalogDate: frozen ? _editing!.catalogDate : catalog.reviewedAt,
      preparationSnapshot: frozen && frozenPets && !_statsEdited
          ? _editing!.preparationSnapshot
          : {
              ..._preparation.snapshot(catalog, methodId: method.id),
              'effectiveSettings': _estimateSetup.toJson(),
              'buffTotals': Map<String, double>.from(_totals),
              if (frozen) ...{
                'activeBuffIds': _editing!.buffs
                    .map((buff) => textOf(buff, 'id'))
                    .toList(),
                'catalogDate': _editing!.catalogDate,
              },
            },
    );
    final previousPreferences = Map<String, dynamic>.from(
      widget.store.preferences,
    );
    if (_editing == null) {
      widget.store.preferences = {
        ...widget.store.preferences,
        'methodId': method.id,
        'spotId': spot?.id ?? '',
      };
    }
    try {
      await widget.store.upsert(session);
      if (!mounted) return;
      setState(() {
        _resetDraft();
        _page = 1;
      });
    } catch (error) {
      widget.store.preferences = previousPreferences;
      _message('Could not save. Your draft is still here. $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _edit(GatheringSession s) async {
    if (_saving || _opacitySaving || _preparationTransition) return;
    if (s.sessionImport != null &&
        !catalog.methods.any((method) => method.id == s.methodId)) {
      _message('Update this session in Session Import, then send it again.');
      return;
    }
    await _drainPreparationWrites();
    if (!mounted || _saving || _opacitySaving) return;
    if ((!_inlineStatsValid ||
            !_lootInputValid ||
            _loot.isNotEmpty ||
            _timerStart != null ||
            _timerAccumulated > 0 ||
            _notes.text.trim().isNotEmpty) &&
        !await _confirm(
          'Replace the current draft?',
          'Opening this saved session will replace the unsaved draft.',
          'Open session',
        )) {
      return;
    }
    if (!mounted) return;
    setState(() {
      _resetDraft();
      _returnPreparation = _preparation;
      _editing = s;
      _date = s.createdAt.toLocal();
      _methodId = catalog.methods.any((m) => m.id == s.methodId)
          ? s.methodId
          : catalog.methods.first.id;
      _spotId = catalog.spots.any((p) => p.id == s.spotId)
          ? s.spotId
          : 'custom';
      _customSpot.text = s.spotName;
      _minutes.text = (s.durationSeconds / 60).toStringAsFixed(2);
      _notes.text = s.notes;
      final frozenProfile = objectMap(s.preparationSnapshot?['profile']);
      _preparation = frozenProfile.isNotEmpty
          ? GatheringPreparation.fromJson(frozenProfile)
          : GatheringPreparation(
              baseSettings: BairogCalculatorSettings(
                mastery: s.mastery,
                gatheringDropRatePercent: 0,
                minigameMode: BairogMinigameMode.none,
                enabledExpenseItemIds: const {},
              ),
              buffIds: s.buffs.map((b) => textOf(b, 'id')),
              petIds: s.pets.map((pet) => textOf(pet, 'id')),
            );
      _buffsEdited = false;
      _petsEdited = false;
      _statsEdited = false;
      _loot = {
        for (final entry in s.loot)
          entry.id: LootEntry.fromJson(entry.toJson()),
      };
      _page = 0;
    });
  }

  Future<void> _useSpot(Spot s, {String? methodId}) async {
    if (_saving || _opacitySaving || _preparationTransition) return;
    await _drainPreparationWrites();
    if (!mounted || _saving || _opacitySaving) return;
    final requestedMethod = methodId ?? _methodId;
    final nextMethod = s.methodIds.contains(requestedMethod)
        ? requestedMethod
        : s.methodIds.first;
    if (_spotId == s.id && _methodId == nextMethod) {
      await _goToStage(3);
      return;
    }
    final hasDraft =
        !_inlineStatsValid ||
        !_lootInputValid ||
        _loot.isNotEmpty ||
        _timerStart != null ||
        _timerAccumulated > 0 ||
        _notes.text.trim().isNotEmpty ||
        _editing != null;
    if (hasDraft &&
        !await _confirm(
          'Change spot?',
          'This starts a new run and clears the current draft.',
          'Change spot',
        )) {
      return;
    }
    if (!mounted) return;
    setState(() {
      if (hasDraft) _resetDraft();
      _methodId = nextMethod;
      _spotId = s.id;
      _petsEdited = true;
      _page = 3;
    });
    _reconcilePets();
  }

  void _openGuide([Spot? s]) => setState(() {
    _guideSpot = s;
    _guideRevision++;
    _guideVisited = true;
    _page = 2;
  });
  Future<void> _reference() async {
    try {
      if (!await NativeBridge.openReferenceWindow(
        glassOpacityPercent: widget.glassOpacityPercent,
        visualPalette: context.glass.visualPalette,
      )) {
        _message('Could not open Minigame Helper.');
      }
    } catch (error) {
      _message('Could not open Minigame Helper. $error');
    }
  }

  Widget _headerActionArtwork(String path) => Image.asset(
    path,
    package: gatheringAssetPackage,
    width: 32,
    height: 32,
    fit: BoxFit.contain,
    filterQuality: FilterQuality.medium,
    excludeFromSemantics: true,
  );

  Future<void> _pickDate() async {
    final chosen = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2014),
      lastDate: DateTime.now(),
    );
    if (chosen != null && mounted) {
      setState(
        () => _date = DateTime(
          chosen.year,
          chosen.month,
          chosen.day,
          _date.hour,
          _date.minute,
        ),
      );
    }
  }

  String _dateText(DateTime d) {
    final local = d.toLocal();
    return '${local.day.toString().padLeft(2, '0')}.${local.month.toString().padLeft(2, '0')}.${local.year}';
  }

  List<Widget> _navigationButtons({bool rail = false}) => [
    for (final p in [
      (2, 'Spots'),
      (3, 'Prepare'),
      (0, 'Gather'),
      (1, 'Journal'),
    ])
      Padding(
        padding: EdgeInsets.only(bottom: rail ? 6 : 0),
        child: FieldDeskSelection(
          selected: _page == p.$1,
          child: GlassControl(
            selected: _page == p.$1,
            radius: 7,
            child: _navigationButton(p.$1, p.$2, rail: rail),
          ),
        ),
      ),
  ];

  Widget _navigationButton(int page, String label, {bool rail = false}) =>
      TextButton(
        key: ValueKey(switch (page) {
          2 => 'workflow-spots',
          3 => 'workflow-prepare',
          0 => 'workflow-gather',
          _ => 'workflow-history',
        }),
        style: TextButton.styleFrom(
          foregroundColor: _page == page
              ? context.gatheringColors.ink
              : context.gatheringColors.muted,
          alignment: Alignment.centerLeft,
          padding: EdgeInsets.symmetric(
            horizontal: 12,
            vertical: rail ? 15 : 11,
          ),
          textStyle: Theme.of(context).textTheme.labelLarge!.copyWith(
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
        onPressed:
            ((page == 3 || page == 0) && spot == null && _spotId != 'custom') ||
                (page == 0 && !_inlineStatsValid)
            ? null
            : () => _goToStage(page),
        child: Row(
          mainAxisSize: rail ? MainAxisSize.max : MainAxisSize.min,
          children: [
            Icon(
              switch (page) {
                2 => Icons.explore_outlined,
                3 => Icons.backpack_outlined,
                0 => Icons.timelapse_rounded,
                _ => Icons.history_rounded,
              },
              size: 20,
              color: _page == page
                  ? context.gatheringColors.accent
                  : context.gatheringColors.muted,
            ),
            const SizedBox(width: 11),
            Flexible(child: Text(label)),
          ],
        ),
      );

  Widget _workflowBar() => Padding(
    key: const ValueKey('workflow-toolbar'),
    padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
    child: Align(
      alignment: Alignment.centerLeft,
      child: Wrap(
        key: const ValueKey('workflow-tabs'),
        spacing: 6,
        runSpacing: 6,
        children: _navigationButtons(),
      ),
    ),
  );

  Widget _workflowRail() => Align(
    alignment: Alignment.topCenter,
    child: Container(
      key: const ValueKey('gathering-field-rail'),
      decoration: BoxDecoration(
        gradient: _page == 2 && context.glass.visualPalette == null
            ? LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  for (final color in context.glass.headerGradient.colors)
                    color.withValues(
                      alpha: (color.a * color.a * color.a).clamp(.02, 1.0),
                    ),
                ],
              )
            : context.glass.headerGradient,
        border: Border(
          right: BorderSide(color: context.glass.line),
          bottom: BorderSide(color: context.glass.line),
        ),
        borderRadius: const BorderRadius.only(bottomRight: Radius.circular(10)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 22, 12, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.only(left: 5, bottom: 14),
            child: Text(
              'Gathering',
              style: TextStyle(
                fontFamily: 'Georgia',
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: context.gatheringColors.ink,
              ),
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: Container(
              margin: const EdgeInsets.only(left: 5, bottom: 24),
              width: 34,
              height: 2,
              color: context.gatheringColors.gold,
            ),
          ),
          ..._navigationButtons(rail: true),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Divider(height: 1, color: context.glass.line),
          ),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [_bairogSourceButton(), ..._workspaceUtilities()],
          ),
        ],
      ),
    ),
  );

  List<Widget> _workspaceUtilities() => [
    if (_page == 2)
      IconButton(
        key: const ValueKey('open-glass-opacity'),
        onPressed: _showGlassOpacity,
        tooltip: 'Glass opacity',
        icon: const Icon(Icons.opacity, size: 20),
      ),
    IconButton(
      key: const ValueKey('open-minigame-helper'),
      onPressed: _reference,
      tooltip: 'Minigame Helper',
      icon: _headerActionArtwork('assets/icons/sources/minigame_helper.png'),
    ),
    IconButton(
      onPressed: _help,
      tooltip: 'Help',
      icon: Icon(
        Icons.help_outline,
        size: 20,
        color: context.gatheringColors.muted,
      ),
    ),
  ];

  Widget _workspaceHeader({required bool rail}) => Padding(
    key: const ValueKey('gathering-workspace-heading'),
    padding: const EdgeInsets.fromLTRB(18, 12, 12, 10),
    child: Row(
      children: [
        if (!rail && !_hostedFieldDesk) ...[
          _bairogSourceButton(),
          const SizedBox(width: 10),
        ],
        Expanded(
          child: GatheringStageReveal(
            key: const ValueKey('workflow-stage-reveal'),
            stage: _page,
            child: Text(
              switch (_page) {
                2 => 'Find a spot',
                3 => 'Preparation',
                0 => 'Gathering session',
                _ => 'Journal',
              },
              style: TextStyle(
                fontFamily: 'Georgia',
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: context.gatheringColors.ink,
              ),
            ),
          ),
        ),
        if (rail && _page == 2 && !_hostedFieldDesk) ...[
          const SizedBox(width: 12),
          Flexible(flex: 2, child: _spotSetupSummary()),
          const SizedBox(width: 8),
        ],
        if (!rail) ..._workspaceUtilities(),
      ],
    ),
  );

  Widget _stageBody() => Theme(
    key: const ValueKey('gathering-retained-stages'),
    data: companionTheme(
      opacityPercent: _page == 2 ? widget.glassOpacityPercent : 90,
      visualPalette: context.glass.visualPalette,
    ),
    // Only the stage heading animates. The retained map/editor is never faded
    // into an offscreen layer or translated during navigation.
    child: _hostedFieldDesk
        ? _spotGuide()
        : IndexedStack(
            index: _page,
            children: [
              _entryPage(),
              _historyPage(),
              _guideVisited ? _spotGuide() : const SizedBox.shrink(),
              _preparePage(),
            ],
          ),
  );

  Widget _spotGuide() => Stack(
    children: [
      Positioned.fill(child: _spotGuideMap()),
      if (_recipeLocations case final locations?) ...[
        Positioned.fill(
          child: SpotMap(
            key: ValueKey('recipe-locations-${locations.item}'),
            spots: const [],
            selected: null,
            methods: catalog.methods,
            nodes: catalog.mapNodes,
            overview: true,
            locationPoints: locations.points,
            viewInsets: const EdgeInsets.only(top: 68),
          ),
        ),
        Positioned(
          top: 8,
          left: 12,
          right: 60,
          child: GlassSurface(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Back to checklist',
                  onPressed: _restoreRecipeChecklist,
                  icon: const Icon(Icons.arrow_back),
                ),
                Expanded(child: Text(locations.item)),
                Tooltip(
                  message: locations.sourceNote,
                  child: const Padding(
                    padding: EdgeInsets.all(8),
                    child: Icon(Icons.history, size: 20),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
      if (_recipeChecklistOpen && widget.recipeChecklistBuilder != null)
        Positioned(
          top: 8,
          bottom: 12,
          left: 12,
          child: SizedBox(
            width: (MediaQuery.sizeOf(context).width - 40)
                .clamp(0, 430)
                .toDouble(),
            child: GlassSurface(
              padding: const EdgeInsets.all(12),
              child: widget.recipeChecklistBuilder!(
                context,
                (name) => _recipeSpot(name) != null,
                (name) {
                  final selected = _recipeSpot(name);
                  if (selected == null) return;
                  setState(() {
                    _guideSpot = selected;
                    _guideRevision++;
                    _recipeChecklistOpen = false;
                    _returnToRecipeChecklist = true;
                    _recipeLocations = null;
                  });
                },
                () => setState(() => _recipeChecklistOpen = false),
                (locations) => setState(() {
                  _recipeLocations = locations;
                  _recipeChecklistOpen = false;
                }),
              ),
            ),
          ),
        ),
    ],
  );

  Widget _spotGuideMap() => TickerMode(
    enabled: _page == 2,
    child: FieldGuide(
      key: const ValueKey('gathering-spot-guide'),
      catalog: catalog,
      sharedMarketLoader: widget.sharedMarketLoader,
      sharedMarketUpdates: widget.sharedMarketUpdates,
      marketFreshFor: widget.marketFreshFor,
      sessions: widget.store.sessions,
      bairogCalculatorData: catalog.bairogCalculatorData,
      bairogSettings: _estimateSetup,
      initialSpot: _guideSpot,
      navigationRequest: _guideRevision,
      onReturnToChecklist: _returnToRecipeChecklist
          ? _restoreRecipeChecklist
          : null,
      initialFiltersExpanded: false,
      useLabel: _hostedFieldDesk ? 'Buffs' : 'Prepare here',
      onBrowseContextChanged: _hostedFieldDesk ? _browseContext : null,
      onUse: (chosen) {
        if (_hostedFieldDesk) {
          _browseContext(chosen, chosen.methodIds.first);
          _showRecommendedBuffs();
        } else {
          _useSpot(chosen);
        }
      },
      onUseWithMethod: (chosen, methodId) {
        if (_hostedFieldDesk) {
          _browseContext(chosen, methodId);
          _showRecommendedBuffs();
        } else {
          _useSpot(chosen, methodId: methodId);
        }
      },
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final textScale = MediaQuery.textScalerOf(context).scale(1);
          final rail =
              constraints.maxWidth >= 1100 * textScale &&
              constraints.maxHeight >= 540 * textScale;
          // The row and retained stage slot never move when a window crosses
          // the rail breakpoint. Resizing must not recreate the map or draft.
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: rail ? (_hostedFieldDesk ? 212 : 160) * textScale : 0,
                child: rail
                    ? (_hostedFieldDesk ? _fieldDeskRail() : _workflowRail())
                    : const SizedBox.shrink(),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _workspaceHeader(rail: rail),
                    if (!rail)
                      _hostedFieldDesk ? _fieldDeskToolbar() : _workflowBar(),
                    if (_page == 2 && !rail && !_hostedFieldDesk)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
                        child: _spotSetupSummary(),
                      ),
                    if (_notice case final notice?)
                      Container(
                        key: const ValueKey('app-notice'),
                        color: context.glass.row,
                        padding: const EdgeInsets.fromLTRB(18, 4, 8, 4),
                        child: Row(
                          children: [
                            Icon(
                              Icons.info_outline,
                              color: context.gatheringColors.gold,
                              size: 20,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                notice,
                                style: const TextStyle(fontSize: 14),
                              ),
                            ),
                            IconButton(
                              onPressed: () => setState(() => _notice = null),
                              tooltip: 'Dismiss',
                              icon: const Icon(Icons.close, size: 18),
                            ),
                          ],
                        ),
                      ),
                    Expanded(
                      key: const ValueKey('gathering-retained-workspace'),
                      child: _stageBody(),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    ),
  );

  Widget _panel(
    Widget child, {
    EdgeInsets padding = const EdgeInsets.all(14),
  }) => FieldDeskPanel(padding: padding, child: child);

  Widget _entryPage() {
    if (spot == null && _spotId != 'custom') return _emptyStage();
    return Center(
      child: ConstrainedBox(
        key: const ValueKey('session-workspace'),
        constraints: const BoxConstraints(maxWidth: 1100),
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                key: const ValueKey('session-scroll'),
                controller: _entryScroll,
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _chosenSpotHeader(stage: 0),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 16,
                      runSpacing: 12,
                      crossAxisAlignment: WrapCrossAlignment.start,
                      children: [
                        SizedBox(width: 340, child: _timeChoices()),
                        TextButton.icon(
                          key: const ValueKey('edit-preparation'),
                          onPressed: () => _goToStage(3),
                          icon: const Icon(Icons.tune, size: 20),
                          label: const Text('Edit preparation'),
                        ),
                        if (_buffIds.isNotEmpty)
                          Tooltip(
                            message: catalog
                                .selectedBuffs(_buffIds)
                                .map((b) => b.name)
                                .join('\n'),
                            child: Wrap(
                              spacing: 4,
                              runSpacing: 4,
                              children: [
                                for (final buff in catalog.selectedBuffs(
                                  _buffIds,
                                ))
                                  BuffHoverDetails(
                                    catalog: catalog,
                                    buff: buff,
                                    child: GameIcon(
                                      buff.icon,
                                      size: 32,
                                      grade: buff.grade,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Padding(
                      padding: const EdgeInsets.all(14),
                      child: LootPanel(
                        key: _lootPanelKey,
                        catalog: catalog,
                        scrollable: false,
                        entries: _loot,
                        onChanged: _refresh,
                        suggestedItems: catalog.lootForSpot(spot, _methodId),
                        onValidityChanged: (valid) {
                          if (mounted && _lootInputValid != valid) {
                            setState(() => _lootInputValid = valid);
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyStage() => Center(
    child: FilledButton.icon(
      onPressed: () => _openGuide(),
      icon: const Icon(Icons.map_outlined),
      label: const Text('Choose a spot'),
    ),
  );

  Widget _chosenSpotHeader({required int stage}) => GatheringSpotBanner(
    spot: spot,
    customName: spotName,
    method: method,
    methods: catalog.methods,
    active: _page == stage,
    onChange: () => _openGuide(),
    onMap: () => _openGuide(spot),
  );

  Widget _preparePage() {
    if (spot == null && _spotId != 'custom') return _emptyStage();
    return Center(
      child: ConstrainedBox(
        key: const ValueKey('preparation-workspace'),
        constraints: const BoxConstraints(maxWidth: 1040),
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                key: const ValueKey('preparation-scroll'),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _chosenSpotHeader(stage: 3),
                    const SizedBox(height: 16),
                    if (widget
                            .store
                            .preferences[stableV017GatheringLoadoutNotesPreferenceKey]
                        case final String notes when notes.isNotEmpty) ...[
                      StableV017GatheringLoadoutNotesCard(notes: notes),
                      const SizedBox(height: 16),
                    ],
                    GatheringPreparationPanel(
                      catalog: catalog,
                      methodId: _methodId,
                      spotId: spot?.id,
                      selectedBuffIds: _buffIds,
                      selectedPetIds: _petIds,
                      pets: _petCatalog,
                      baseSettings: _preparation.baseSettings,
                      effectiveSettings: _estimateSetup,
                      statsConfirmed: _preparation.statsConfirmed,
                      onToggleBuff: _toggleBuff,
                      onTogglePet: _togglePet,
                      onPreset: _preset,
                      onClearBuffs: _clearBuffs,
                      onClearPets: _clearPets,
                      onStatsChanged: _changeInlineStats,
                      onStatsValidityChanged: _setInlineStatsValidity,
                      statsContextId: _inlineStatsContext,
                      statsEnabled:
                          !_saving &&
                          !_opacitySaving &&
                          !_preparationTransition &&
                          _timerStart == null,
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
              child: Wrap(
                alignment: WrapAlignment.end,
                spacing: 12,
                runSpacing: 8,
                children: [
                  TextButton(
                    key: const ValueKey('record-results'),
                    onPressed:
                        _saving || _estimateSetupSaving || !_inlineStatsValid
                        ? null
                        : () => _goToStage(0),
                    child: const Text('Record results'),
                  ),
                  FilledButton.icon(
                    key: const ValueKey('start-gathering'),
                    onPressed:
                        _saving || _estimateSetupSaving || !_inlineStatsValid
                        ? null
                        : _startGathering,
                    icon: const Icon(Icons.play_arrow),
                    label: Text(
                      _timerAccumulated > 0
                          ? 'Resume gathering'
                          : 'Start gathering',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _startGathering() async {
    if (_saving ||
        _opacitySaving ||
        _preparationTransition ||
        !_inlineStatsValid) {
      return;
    }
    _reconcilePets();
    setState(() => _preparationTransition = true);
    try {
      await _drainPreparationWrites();
    } finally {
      if (mounted) setState(() => _preparationTransition = false);
    }
    if (!mounted ||
        _saving ||
        _opacitySaving ||
        (spot == null && _spotId != 'custom')) {
      return;
    }
    setState(() => _page = 0);
    if (_timerStart == null) _timer();
  }

  Future<void> _goToStage(int page) async {
    if ((page == 0 || page == 3) && spot == null && _spotId != 'custom') return;
    if (page == 0 && !_inlineStatsValid) return;
    FocusManager.instance.primaryFocus?.unfocus();
    if (page == 3 && _timerStart != null) {
      if (!await _confirm(
        'Pause gathering?',
        'Pause the timer to edit preparation.',
        'Pause',
      )) {
        return;
      }
      if (!mounted) return;
      _timer();
    }
    if (page == 2) {
      _openGuide();
    } else {
      _navigate(page);
    }
  }

  Widget _spotSetupSummary() => GlassSurface(
    key: const ValueKey('preparation-summary'),
    elevated: false,
    padding: const EdgeInsets.fromLTRB(4, 2, 14, 2),
    child: Wrap(
      spacing: 14,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _estimateSetupButton(),
        if (!_preparation.statsConfirmed)
          Tooltip(
            message: 'Enter your stats for personal estimates.',
            child: Text(
              'Example stats',
              style: TextStyle(
                color: context.gatheringColors.gold,
                fontSize: 13,
              ),
            ),
          ),
        Text('${countText(_estimateSetup.mastery)} mastery'),
        Text(
          '${numberText(_estimateSetup.gatheringDropRatePercent)}% drop rate',
        ),
      ],
    ),
  );

  Widget _methods({VoidCallback? onChanged}) => _panel(
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Tools',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 10,
          children: [
            for (final m in catalog.methods)
              Semantics(
                label: m.label,
                button: true,
                selected: m.id == _methodId,
                child: Tooltip(
                  message: m.label,
                  child: GlassControl(
                    selected: m.id == _methodId,
                    radius: 12,
                    child: InkWell(
                      key: ValueKey('method-${m.id}'),
                      borderRadius: BorderRadius.circular(12),
                      onTap: () {
                        setState(() {
                          _methodId = m.id;
                          if (spot != null && !spot!.methodIds.contains(m.id)) {
                            _spotId = null;
                          }
                          _petsEdited = true;
                        });
                        _reconcilePets();
                        onChanged?.call();
                      },
                      child: SizedBox(
                        width: MediaQuery.textScalerOf(
                          context,
                        ).scale(84).clamp(84.0, 144.0),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(5, 7, 5, 6),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              GlassArtworkWell(
                                key: ValueKey('method-artwork-${m.id}'),
                                tool: true,
                                radius: 9,
                                child: SizedBox.square(
                                  dimension: 56,
                                  child: Center(
                                    child: GameIcon(
                                      m.icon,
                                      size: 52,
                                      backgroundColor: Colors.transparent,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 7),
                              Text(
                                switch (m.id) {
                                  'butcher' => 'Butcher',
                                  'fluid' => 'Fluid',
                                  'hoe' => 'Hoe',
                                  'hunting' => 'Matchlock',
                                  'sniper' => 'Sniper',
                                  _ => m.label,
                                },
                                key: ValueKey('method-label-${m.id}'),
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: context.gatheringColors.ink,
                                ),
                              ),
                              const SizedBox(height: 5),
                              Container(
                                width: 18,
                                height: 3,
                                decoration: BoxDecoration(
                                  color: m.id == _methodId
                                      ? context.gatheringColors.accent
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    ),
  );

  void _setMinutes(int minutes) => setState(() {
    _tick?.cancel();
    _timerStart = null;
    _timerAccumulated = 0;
    _minutes.text = '$minutes';
  });

  Widget _timeChoices() => FieldDeskPanel(
    key: const ValueKey('session-inline-panel'),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          key: const ValueKey('session-inline-heading'),
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _editing == null ? 'New session' : 'Edit session',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              const SizedBox(width: 12),
              Icon(
                Icons.edit_note_outlined,
                size: 21,
                color: context.gatheringColors.muted,
              ),
            ],
          ),
        ),
        Container(
          key: const ValueKey('session-inline-body'),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: context.glass.inset,
            border: Border(top: BorderSide(color: context.glass.line)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: double.infinity,
                child: Wrap(
                  key: const ValueKey('session-duration-header'),
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_timerStart != null) ...[
                          Icon(
                            Icons.circle,
                            size: 7,
                            color: context.gatheringColors.accent,
                          ),
                          const SizedBox(width: 8),
                        ],
                        Text(
                          _timerStart != null ? 'Gathering' : 'Duration',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    TextButton.icon(
                      key: const ValueKey('session-edit-details'),
                      onPressed: _saving ? null : _options,
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      label: const Text('Edit details'),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 2,
                          vertical: 6,
                        ),
                        minimumSize: const Size(0, 34),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        textStyle: Theme.of(context).textTheme.labelLarge!
                            .copyWith(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Semantics(
                label: durationText(seconds),
                child: ExcludeSemantics(
                  child: Text(
                    _sessionClock,
                    key: const ValueKey('session-duration-value'),
                    style: TextStyle(
                      fontSize: 28,
                      height: 1.2,
                      fontFeatures: [FontFeature.tabularFigures()],
                      fontWeight: FontWeight.w600,
                      color: context.gatheringColors.ink,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                key: const ValueKey('session-timer-controls'),
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 6,
                runSpacing: 8,
                children: [
                  for (final minutes in [30, 60])
                    GlassControl(
                      selected: _timerStart == null && seconds == minutes * 60,
                      radius: 8,
                      child: OutlinedButton(
                        key: ValueKey('time-$minutes'),
                        onPressed: _timerStart == null
                            ? () => _setMinutes(minutes)
                            : null,
                        style: OutlinedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          side: BorderSide.none,
                          minimumSize: const Size(0, 38),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 10,
                          ),
                          textStyle: Theme.of(context).textTheme.labelLarge!
                              .copyWith(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                        child: Text('$minutes min'),
                      ),
                    ),
                  Tooltip(
                    message: _timerStart != null
                        ? 'Pause timer'
                        : _timerAccumulated > 0
                        ? 'Resume timer'
                        : 'Start timer',
                    child: OutlinedButton.icon(
                      key: const ValueKey('session-timer-action'),
                      onPressed: _timer,
                      icon: Icon(
                        _timerStart != null
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        size: 18,
                      ),
                      label: Text(
                        _timerStart != null
                            ? 'Pause timer'
                            : _timerAccumulated > 0
                            ? 'Resume timer'
                            : 'Start timer',
                      ),
                      style: OutlinedButton.styleFrom(
                        backgroundColor: context.glass.group,
                        foregroundColor: context.gatheringColors.ink,
                        side: BorderSide(color: context.glass.strongLine),
                        minimumSize: const Size(0, 38),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 10,
                        ),
                        textStyle: Theme.of(context).textTheme.labelLarge!
                            .copyWith(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Divider(height: 1, color: context.glass.line),
              const SizedBox(height: 10),
              _sessionSummaryRow('Date', _dateText(_date)),
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: _notes,
                builder: (context, value, _) => value.text.trim().isEmpty
                    ? const SizedBox.shrink()
                    : Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: _sessionSummaryRow('Notes', value.text.trim()),
                      ),
              ),
            ],
          ),
        ),
        Container(
          key: const ValueKey('session-inline-actions'),
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            color: context.glass.group,
            border: Border(top: BorderSide(color: context.glass.line)),
          ),
          child: _saveBar(),
        ),
      ],
    ),
  );

  String get _sessionClock {
    final value = seconds < 0 ? 0 : seconds;
    final hours = value ~/ 3600;
    final minutes = (value % 3600 ~/ 60).toString().padLeft(2, '0');
    final remaining = (value % 60).toString().padLeft(2, '0');
    return hours == 0 ? '$minutes:$remaining' : '$hours:$minutes:$remaining';
  }

  Widget _sessionSummaryRow(String label, String value) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: TextStyle(fontSize: 13, color: context.gatheringColors.muted),
      ),
      const SizedBox(width: 14),
      Expanded(
        child: Text(
          value,
          key: ValueKey('session-summary-${label.toLowerCase()}'),
          textAlign: TextAlign.right,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 13, color: context.gatheringColors.ink),
        ),
      ),
    ],
  );

  Widget _saveBar() => Wrap(
    key: const ValueKey('session-save-actions'),
    alignment: WrapAlignment.end,
    crossAxisAlignment: WrapCrossAlignment.center,
    spacing: 6,
    runSpacing: 8,
    children: [
      FilledButton(
        onPressed:
            _saving ||
                _opacitySaving ||
                _estimateSetupSaving ||
                !_lootInputValid ||
                !_inlineStatsValid
            ? null
            : _save,
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        ),
        child: Text(
          _saving
              ? 'Saving…'
              : _editing == null
              ? 'Save session'
              : 'Save changes',
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
      IconButton(
        onPressed: _saving || _opacitySaving || _estimateSetupSaving
            ? null
            : _newDraft,
        tooltip: 'New session',
        icon: Icon(
          Icons.restart_alt,
          size: 22,
          color: context.gatheringColors.muted,
        ),
      ),
    ],
  );

  void _options() => showDialog<void>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, refreshDialog) => AlertDialog(
        key: const ValueKey('session-details-dialog'),
        title: const Text('Session details'),
        content: SizedBox(
          width: 430,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    key: const ValueKey('session-details-date'),
                    onPressed: () async {
                      await _pickDate();
                      if (c.mounted) refreshDialog(() {});
                    },
                    icon: const Icon(Icons.calendar_today_outlined, size: 20),
                    label: Text(_dateText(_date)),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  key: const ValueKey('session-details-duration'),
                  controller: _minutes,
                  enabled: _timerStart == null,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Duration',
                    suffixText: 'min',
                  ),
                ),
                const SizedBox(height: 18),
                CheckboxListTile(
                  key: const ValueKey('session-details-custom-location'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Custom location'),
                  value: _spotId == 'custom',
                  onChanged: (v) {
                    setState(() => _spotId = v == true ? 'custom' : null);
                    refreshDialog(() {});
                  },
                ),
                if (_spotId == 'custom') ...[
                  _methods(onChanged: () => refreshDialog(() {})),
                  const SizedBox(height: 14),
                  TextField(
                    key: const ValueKey('session-details-location-name'),
                    controller: _customSpot,
                    maxLength: 100,
                    decoration: const InputDecoration(
                      labelText: 'Location name',
                      counterText: '',
                    ),
                  ),
                  const SizedBox(height: 14),
                ],
                const SizedBox(height: 8),
                TextField(
                  key: const ValueKey('session-details-notes'),
                  controller: _notes,
                  maxLines: 3,
                  maxLength: 2000,
                  decoration: const InputDecoration(
                    labelText: 'Notes',
                    counterText: '',
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            key: const ValueKey('session-details-done'),
            onPressed: () => Navigator.pop(c),
            child: const Text('Done'),
          ),
        ],
      ),
    ),
  );

  bool get _historyFiltered =>
      _historyQuery.trim().isNotEmpty ||
      _historyMethodId != null ||
      _historyDates != null;

  void _clearHistoryFilters() => setState(() {
    _historySearch.clear();
    _historyQuery = '';
    _historyMethodId = null;
    _historyDates = null;
  });

  Future<void> _pickHistoryDates() async {
    final chosen = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2014),
      lastDate: DateTime.now(),
      initialDateRange: _historyDates,
      helpText: 'Filter history by date',
    );
    if (chosen != null && mounted) {
      setState(() => _historyDates = chosen);
    }
  }

  Widget _historyPage() {
    final includesGrinding = widget.store.sessions.any(
      (session) => session.sessionImport?.activity == 'grinding',
    );
    final query = _historyQuery.trim().toLowerCase();
    final locations = {for (final spot in catalog.spots) spot.id: spot};
    final sessions = widget.store.sessions.where((s) {
      final location = locations[s.spotId];
      if (_historyMethodId != null && s.methodId != _historyMethodId) {
        return false;
      }
      final dates = _historyDates;
      if (dates != null) {
        final local = s.createdAt.toLocal();
        final day = DateTime(local.year, local.month, local.day);
        if (day.isBefore(dates.start) || day.isAfter(dates.end)) return false;
      }
      return '${s.spotName} ${location?.displayName ?? ''} ${location?.nodeName ?? ''} ${s.methodLabel} ${s.notes}'
          .toLowerCase()
          .contains(query);
    }).toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final totalSeconds = sessions.fold(0, (n, s) => n + s.durationSeconds);
    final hasStableV017Sessions = sessions.any(
      (session) => session.stableV017Location != null,
    );
    final modernSessions = sessions.where(
      (session) => session.stableV017Location == null,
    );
    final totalItems = modernSessions.fold(0, (n, s) => n + s.totalItems);
    final approximate = modernSessions.any(
      (session) => session.loot.any((entry) => entry.isApproximate),
    );
    final itemSummary = hasStableV017Sessions
        ? modernSessions.isEmpty
              ? 'Not recorded'
              : '${approximate ? '≈ ' : ''}${countText(totalItems)} + not recorded'
        : '${approximate ? '≈ ' : ''}${countText(totalItems)}';
    final distinctSpots = sessions
        .map(
          (s) => s.spotId.isEmpty || s.spotId == 'custom'
              ? 'custom:${s.spotName.trim().toLowerCase()}'
              : s.spotId,
        )
        .toSet()
        .length;
    final methods = <String, String>{
      for (final method in catalog.methods) method.id: method.label,
      for (final s in widget.store.sessions)
        if (!catalog.methods.any((m) => m.id == s.methodId))
          s.methodId: s.methodLabel,
    };
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1080),
        child: ListView(
          key: const ValueKey('gathering-history'),
          padding: const EdgeInsets.all(20),
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        includesGrinding
                            ? 'Session history'
                            : 'Gathering history',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${widget.store.sessions.length} saved ${widget.store.sessions.length == 1 ? 'session' : 'sessions'}',
                        style: TextStyle(
                          color: context.gatheringColors.muted,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: _newDraft,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('New session'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (widget.sessionImportError case final error?)
              Padding(
                key: const ValueKey('session-import-history-error'),
                padding: const EdgeInsets.only(bottom: 16),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        error,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    if (widget.onRetrySessionImport != null)
                      TextButton(
                        onPressed: widget.onRetrySessionImport,
                        child: const Text('Retry'),
                      ),
                  ],
                ),
              ),
            FieldDeskPanel(
              key: const ValueKey('history-filters'),
              padding: const EdgeInsets.all(12),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final search = TextField(
                    key: const ValueKey('history-search'),
                    controller: _historySearch,
                    onChanged: (v) => setState(() => _historyQuery = v),
                    decoration: InputDecoration(
                      hintText: includesGrinding
                          ? 'Spot, session type, or note'
                          : 'Spot, gathering type, or note',
                      prefixIcon: const Icon(Icons.search, size: 20),
                    ),
                  );
                  final methodFilter = InputDecorator(
                    decoration: const InputDecoration(
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        key: const ValueKey('history-method'),
                        value: _historyMethodId ?? '',
                        isExpanded: true,
                        items: [
                          DropdownMenuItem(
                            value: '',
                            child: Text(
                              includesGrinding
                                  ? 'All session types'
                                  : 'All gathering types',
                            ),
                          ),
                          ...methods.entries.map(
                            (entry) => DropdownMenuItem(
                              value: entry.key,
                              child: Text(
                                entry.value,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        ],
                        onChanged: (value) => setState(
                          () => _historyMethodId = value == '' ? null : value,
                        ),
                      ),
                    ),
                  );
                  final dates = OutlinedButton.icon(
                    key: const ValueKey('history-dates'),
                    onPressed: _pickHistoryDates,
                    icon: const Icon(Icons.date_range_outlined, size: 18),
                    label: Text(
                      _historyDates == null
                          ? 'All dates'
                          : '${_dateText(_historyDates!.start)} – ${_dateText(_historyDates!.end)}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                  final reset = TextButton(
                    key: const ValueKey('history-clear-filters'),
                    onPressed: _historyFiltered ? _clearHistoryFilters : null,
                    child: const Text('Reset'),
                  );
                  if (constraints.maxWidth >= 920) {
                    return Row(
                      children: [
                        Expanded(flex: 3, child: search),
                        const SizedBox(width: 10),
                        Expanded(flex: 2, child: methodFilter),
                        const SizedBox(width: 10),
                        Flexible(flex: 3, child: dates),
                        const SizedBox(width: 4),
                        reset,
                      ],
                    );
                  }
                  return Column(
                    children: [
                      Row(
                        children: [
                          Expanded(flex: 3, child: search),
                          const SizedBox(width: 10),
                          Expanded(flex: 2, child: methodFilter),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(child: dates),
                          const SizedBox(width: 8),
                          reset,
                        ],
                      ),
                    ],
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final scale = MediaQuery.textScalerOf(context).scale(1);
                final columns = constraints.maxWidth >= 620 * scale ? 4 : 2;
                final width =
                    ((constraints.maxWidth - (columns - 1) * 10) / columns)
                        .clamp(0.0, 200 * scale);
                return Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _historyStat(
                      'sessions',
                      'Sessions',
                      countText(sessions.length),
                      width,
                    ),
                    _historyStat(
                      'time',
                      'Gathering time',
                      durationText(totalSeconds),
                      width,
                    ),
                    _historyStat('items', 'Items gathered', itemSummary, width),
                    _historyStat(
                      'spots',
                      'Spots visited',
                      countText(distinctSpots),
                      width,
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 14),
            if (_historyFiltered)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  '${sessions.length} matching sessions',
                  key: const ValueKey('history-match-count'),
                  style: TextStyle(
                    color: context.gatheringColors.muted,
                    fontSize: 13,
                  ),
                ),
              ),
            if (sessions.isEmpty)
              FieldDeskPanel(
                padding: const EdgeInsets.all(24),
                leadingWidth: 78,
                child: Row(
                  children: [
                    GlassArtworkWell(
                      tool: true,
                      child: GameIcon(
                        catalog.methods.first.icon,
                        size: 44,
                        backgroundColor: Colors.transparent,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        widget.store.sessions.isEmpty
                            ? 'No sessions yet.'
                            : 'No sessions match these filters.',
                        style: const TextStyle(fontSize: 16),
                      ),
                    ),
                    if (_historyFiltered)
                      TextButton(
                        onPressed: _clearHistoryFilters,
                        child: const Text('Show all'),
                      ),
                  ],
                ),
              ),
            for (final session in sessions)
              _historyEntry(session, locations[session.spotId]),
          ],
        ),
      ),
    );
  }

  Widget _historyStat(String id, String label, String value, double width) =>
      SizedBox(
        width: width,
        child: FieldDeskPanel(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: context.gatheringColors.muted,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 7),
              Tooltip(
                message: value,
                child: Text(
                  value,
                  key: ValueKey('history-summary-$id'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Georgia',
                    fontSize: 25,
                    fontWeight: FontWeight.w700,
                    color: id == 'items'
                        ? context.gatheringColors.accent
                        : context.gatheringColors.ink,
                  ),
                ),
              ),
            ],
          ),
        ),
      );

  Widget _historyEntry(GatheringSession session, Spot? location) {
    final stableV017Location = session.stableV017Location;
    final target = stableV017Location == null
        ? location?.displayName ?? session.spotName
        : stableV017Location.isEmpty
        ? 'Unspecified location'
        : stableV017Location;
    final node = location?.nodeName ?? '';
    final local = session.createdAt.toLocal();
    final date =
        '${_dateText(local)} · ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
    final methodIcon = session.methodIcon.isNotEmpty
        ? session.methodIcon
        : catalog.methods
                  .where((m) => m.id == session.methodId)
                  .firstOrNull
                  ?.icon ??
              '';
    final setup = <String>[
      session.methodLabel,
      durationText(session.durationSeconds),
      if (session.mastery > 0) '${countText(session.mastery)} mastery',
      if (session.buffs.isNotEmpty)
        '${session.buffs.length} ${session.buffs.length == 1 ? 'buff' : 'buffs'}',
      if (session.pets.isNotEmpty)
        '${session.pets.length} ${session.pets.length == 1 ? 'pet' : 'pets'}',
    ];
    final info = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GlassArtworkWell(
          tool: location?.icon.isNotEmpty != true,
          child: GameIcon(
            location?.icon.isNotEmpty == true ? location!.icon : methodIcon,
            size: 44,
            backgroundColor: Colors.transparent,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                target,
                key: ValueKey('history-target-${session.id}'),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: 'Georgia',
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (node.isNotEmpty)
                Text(
                  node,
                  key: ValueKey('history-node-${session.id}'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: context.gatheringColors.muted,
                    fontSize: 14,
                  ),
                ),
              const SizedBox(height: 3),
              Text(
                date,
                style: TextStyle(
                  color: context.gatheringColors.muted,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 8),
              if (stableV017Location != null) ...[
                Container(
                  key: ValueKey('stable-v017-read-only-${session.id}'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.1),
                    border: Border.all(color: accent.withValues(alpha: 0.45)),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'Imported v0.1.7 · read-only',
                    style: TextStyle(color: accent, fontSize: 13),
                  ),
                ),
                const SizedBox(height: 6),
              ],
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: setup
                    .map(
                      (value) => Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          gradient: context.glass.controlGradient,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          value,
                          style: TextStyle(
                            color: context.gatheringColors.muted,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ],
          ),
        ),
      ],
    );
    final actions = Wrap(
      spacing: 4,
      runSpacing: 4,
      alignment: WrapAlignment.end,
      children: [
        if (location != null)
          TextButton.icon(
            key: ValueKey('history-location-${session.id}'),
            onPressed: () => _openGuide(location),
            icon: const Icon(Icons.map_outlined, size: 18),
            label: const Text('Location'),
          ),
        if (stableV017Location == null)
          Tooltip(
            message: 'Edit session',
            child: TextButton.icon(
              key: ValueKey('edit-session-${session.id}'),
              onPressed: () => _edit(session),
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: const Text('Edit'),
            ),
          ),
        IconButton(
          key: ValueKey('delete-session-${session.id}'),
          onPressed: () => _delete(session),
          tooltip: 'Delete session',
          icon: Icon(
            Icons.delete_outline,
            size: 20,
            color: context.gatheringColors.muted,
          ),
        ),
      ],
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        key: ValueKey('history-session-${session.id}'),
        color: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: LayoutBuilder(
          builder: (context, bounds) => FieldDeskPanel(
            radius: 14,
            interactive: true,
            leadingWidth: 64,
            // Match the content's existing wide branch after its border/padding.
            // Stacked loot totals need the ordinary reading face below the art.
            leadingHeight: bounds.maxWidth - 30 >= 920 ? null : 72,
            child: InkWell(
              onTap: () => _showSession(session),
              borderRadius: BorderRadius.circular(14),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    if (constraints.maxWidth >= 920) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(flex: 4, child: info),
                          const SizedBox(width: 18),
                          Expanded(
                            flex: 5,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                border: Border(
                                  left: BorderSide(color: context.glass.line),
                                ),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.only(left: 16),
                                child: _historyLoot(session),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          SizedBox(width: 145, child: actions),
                        ],
                      );
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        info,
                        const SizedBox(height: 12),
                        _historyLoot(session),
                        const SizedBox(height: 6),
                        actions,
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _historyLoot(GatheringSession session) {
    final stableV017 = session.stableV017Location != null;
    final loot = session.loot.where((entry) => entry.total > 0).toList()
      ..sort((a, b) => b.total.compareTo(a.total));
    final approximate = session.loot.any((entry) => entry.isApproximate);
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 78 * textScale,
          child: Column(
            children: [
              Tooltip(
                message: stableV017
                    ? 'Item totals were not recorded in v0.1.7.'
                    : countText(session.totalItems),
                child: Text(
                  stableV017
                      ? '—'
                      : '${approximate ? '≈ ' : ''}${countText(session.totalItems)}',
                  key: ValueKey('history-entry-total-${session.id}'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: context.gatheringColors.accent,
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                stableV017 ? 'not recorded' : 'items',
                style: TextStyle(
                  color: context.gatheringColors.muted,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final item in loot.take(4))
                Tooltip(
                  message:
                      '${item.name} · ${item.isApproximate ? '≈ ' : ''}${countText(item.total)}',
                  child: SizedBox(
                    width: 66 * textScale,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        GameIcon(item.icon, size: 48),
                        const SizedBox(height: 3),
                        Text(
                          '${item.isApproximate ? '≈ ' : ''}${countText(item.total)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              if (loot.length > 4)
                Text(
                  '+${loot.length - 4}',
                  style: TextStyle(
                    color: context.gatheringColors.muted,
                    fontSize: 14,
                  ),
                ),
              if (loot.isEmpty)
                Text(
                  stableV017
                      ? 'v0.1.7 did not store gathered item totals'
                      : 'No gathered items recorded',
                  style: TextStyle(
                    color: context.gatheringColors.muted,
                    fontSize: 13,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  String _recordedBuffTooltip(Map<String, dynamic> buff) => [
    textOf(buff, 'name'),
    ...objectMap(buff['effects']).entries
        .where((e) => e.value is num)
        .map(
          (e) =>
              '${catalog.statLabel(e.key)} ${effectText(catalog, e.key, e.value as num)}',
        ),
    if (buff['durationMinutes'] is num)
      formatDurationMinutes(buff['durationMinutes'] as num),
    'Recorded session values',
  ].join('\n');

  Future<void> _delete(GatheringSession s) async {
    if (!await _confirm(
      'Delete this session?',
      '${s.spotName} · ${_dateText(s.createdAt)} will be removed from your history.',
      'Delete session',
    )) {
      return;
    }
    try {
      await widget.store.remove(s.id);
      _refresh();
    } catch (error) {
      _message('Could not remove the session. $error');
    }
  }

  void _showSession(GatheringSession s) {
    final location = catalog.spots.where((p) => p.id == s.spotId).firstOrNull;
    final stableV017Location = s.stableV017Location;
    final target = stableV017Location == null
        ? location?.displayName ?? s.spotName
        : stableV017Location.isEmpty
        ? 'Unspecified location'
        : stableV017Location;
    final node = location?.nodeName ?? '';
    final activity =
        s.sessionImport?.activity ??
        catalog.methods
            .where((m) => m.id == s.methodId)
            .firstOrNull
            ?.activity ??
        'gathering';
    showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: Row(
          children: [
            GameIcon(
              location?.icon.isNotEmpty == true ? location!.icon : s.methodIcon,
              size: 48,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    target,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (node.isNotEmpty)
                    Text(
                      node,
                      style: TextStyle(
                        color: context.gatheringColors.muted,
                        fontSize: 14,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 620,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 14,
                  runSpacing: 5,
                  children: [
                    Text(
                      s.methodLabel,
                      style: TextStyle(
                        color: context.gatheringColors.muted,
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      _dateText(s.createdAt),
                      style: TextStyle(
                        color: context.gatheringColors.muted,
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      durationText(s.durationSeconds),
                      style: TextStyle(
                        color: context.gatheringColors.accent,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
                if (stableV017Location != null) ...[
                  const SizedBox(height: 10),
                  const Text(
                    'Imported v0.1.7 · read-only',
                    style: TextStyle(
                      color: accent,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                const SizedBox(height: 19),
                Text(
                  activity == 'grinding' ? 'Loot' : 'Gathered items',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                if (stableV017Location != null)
                  const Text(
                    'Item totals were not recorded in v0.1.7.',
                    style: TextStyle(color: muted, fontSize: 14),
                  ),
                ...s.loot.map(
                  (e) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        GameIcon(e.icon, size: 40),
                        const SizedBox(width: 10),
                        Expanded(child: Text(e.name)),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              (e.isApproximate ? '≈ ' : '') +
                                  countText(e.total),
                              style: TextStyle(
                                color: context.gatheringColors.accent,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              '${e.isApproximate ? '≈ ' : ''}${s.durationSeconds > 0 ? countText(e.total * 3600 / s.durationSeconds) : '—'} / hour',
                              style: TextStyle(
                                color: context.gatheringColors.muted,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                if (s.loot.any((e) => e.isApproximate))
                  Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(
                      '≈ includes shortened K/M amounts. Correct them with exact totals if available.',
                      style: TextStyle(
                        color: context.gatheringColors.gold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                if (s.buffs.isNotEmpty || s.pets.isNotEmpty)
                  const Divider(height: 30),
                if (s.buffs.isNotEmpty) ...[
                  const Text(
                    'Buffs used',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: s.buffs
                        .map(
                          (b) => Tooltip(
                            message: _recordedBuffTooltip(b),
                            child: GameIcon(
                              textOf(b, 'icon'),
                              size: 40,
                              grade: itemGrade(b['grade']),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                  const SizedBox(height: 16),
                  BuffSummary(
                    catalog: catalog,
                    totals: s.buffTotals,
                    activity: activity,
                    baseMastery: s.mastery,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Effects frozen from the ${s.catalogDate} catalog.',
                    style: TextStyle(
                      color: context.gatheringColors.muted,
                      fontSize: 14,
                    ),
                  ),
                ],
                if (s.pets.isNotEmpty) ...[
                  if (s.buffs.isNotEmpty) const SizedBox(height: 18),
                  const Text(
                    'Pets used',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: s.pets
                        .map(
                          (pet) => Tooltip(
                            message: [
                              textOf(pet, 'name'),
                              textOf(pet, 'summary'),
                            ].where((line) => line.isNotEmpty).join('\n'),
                            child: GameIcon(textOf(pet, 'icon'), size: 40),
                          ),
                        )
                        .toList(),
                  ),
                ],
                if (s.notes.isNotEmpty) ...[
                  const Divider(height: 26),
                  const Text(
                    'Notes',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  Text(s.notes),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Close'),
          ),
          if (stableV017Location == null &&
              (s.sessionImport == null ||
                  catalog.methods.any((method) => method.id == s.methodId)))
            FilledButton(
              onPressed: () {
                Navigator.pop(c);
                _edit(s);
              },
              child: const Text('Edit session'),
            ),
        ],
      ),
    );
  }

  void _help() => showDialog<void>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('A simple gathering companion'),
      content: SizedBox(
        width: 640,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _hostedFieldDesk
                    ? 'Compare spots on the map. Enter your base stats in Your stats and choose Buffs for Gathering, Matchlock or Sniper. Garmoth App opens external session tracking.'
                    : '1 Spot: compare locations and choose Prepare here.\n\n2 Prepare: enter your stats and select the kit you will use.\n\n3 Gather: start the timer, or record a completed run. Add your loot and save it to Sessions.',
              ),
              if (!_hostedFieldDesk) ...[
                const SizedBox(height: 15),
                const Text(
                  'For items sent away by maid, add that batch separately. Only add a batch if it will not also appear in the final inventory. If you already know the overall amount, set the total directly.',
                ),
              ],
              const SizedBox(height: 15),
              const Text(
                'Minigame Helper opens in its own movable window. Paste with Ctrl+V, resize or zoom, and replace the image for the next minigame. It does not capture the game or press keys for you.',
              ),
              const SizedBox(height: 20),
              const Text(
                'Your storage stays tidy',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 17),
              ),
              const SizedBox(height: 8),
              const Text(
                'This app never saves imported screenshot bytes or cropped images. Images exist temporarily in memory and are released when replaced or closed. Choosing an existing image does not delete your original file. Windows screenshot tools and clipboard history may separately retain their own copies.',
              ),
              const SizedBox(height: 12),
              const Text(
                'Session history uses one small structured file and one backup. Map tiles are fetched online with a bounded memory cache, not saved to disk. Recognition stays local.',
              ),
              const SizedBox(height: 8),
              SelectableText(
                widget.store.directory.path,
                style: TextStyle(
                  color: context.gatheringColors.accent,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Buff and map guidance',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 17),
              ),
              const SizedBox(height: 8),
              Text(
                catalog.ordering.isEmpty
                    ? 'Common starter choices are curated for convenience, not ranked by live prices.'
                    : catalog.ordering,
              ),
              ...catalog.stackingNotes.map(
                (s) => Padding(
                  padding: const EdgeInsets.only(top: 9),
                  child: Text(
                    '• $s',
                    style: TextStyle(
                      color: context.gatheringColors.muted,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
              ...catalog.limitations.map(
                (s) => Padding(
                  padding: const EdgeInsets.only(top: 9),
                  child: Text(
                    '• $s',
                    style: TextStyle(
                      color: context.gatheringColors.muted,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Map markers identify researched areas, not your live position or an exact route. Open each location’s guide for detailed navigation and rotations. Game artwork belongs to Pearl Abyss; this is an unofficial private companion.',
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(c),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}
