import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/state/planner_application_controller.dart';
import '../../app/window/native_file_dialog_service.dart';
import '../../data/portable/portable_custom_icon_bridge.dart';
import '../../data/portable/portable_file_service.dart';
import '../../data/portable/portable_v4_codec.dart';
import '../../domain/formatting/planner_formatters.dart';
import '../../domain/market/market_calculations.dart';
import '../../domain/models/craft_mode.dart';
import '../../domain/planner/mastery_yields.dart';
import '../../domain/state/planner_state.dart';
import '../../domain/state/state_copy.dart';
import '../../domain/state/transactions/state_transactions.dart';
import '../../visual/visual.dart';
import 'market_bonus_icon.dart';

/// Window-owned, document-independent state for the Craft Profile workspace.
///
/// A single instance can be shared by every mode workspace so the portable
/// JSON editor, selected export scopes, and operation status survive mode and
/// retained-theme navigation without entering persisted planner data.
final class DataSessionController extends ChangeNotifier {
  static const int editorUnlockTapCount = 7;
  static const Duration editorUnlockWindow = Duration(seconds: 5);

  PortableScopes _scopes = const PortableScopes.defaults();
  final TextEditingController _json = TextEditingController();
  final TextEditingController _personalDataPath = TextEditingController();
  bool _jsonVisible = false;
  bool _afkWeightExpanded = false;
  bool _editorSettingsUnlocked = false;
  int _editorUnlockTaps = 0;
  DateTime? _editorUnlockStartedAt;
  bool _busy = false;
  bool _movingPersonalData = false;
  String? _status;
  bool _statusError = false;

  void _update(VoidCallback mutation) {
    mutation();
    notifyListeners();
  }

  /// Reveals the shared AFK Load profile when another workspace links here.
  void showAfkWeightSettings() {
    if (_afkWeightExpanded) return;
    _update(() => _afkWeightExpanded = true);
  }

  bool get editorSettingsUnlocked => _editorSettingsUnlocked;
  bool get profileIoBusy => _busy;

  /// Android-style session-only gate for advanced editor controls.
  ///
  /// Seven taps must land inside one five-second window. The reveal is kept in
  /// this window-owned controller, so mode changes preserve it but closing the
  /// app hides the controls again.
  int registerEditorUnlockTap({DateTime? at}) {
    if (_editorSettingsUnlocked) return 0;
    final now = at ?? DateTime.now();
    final windowStart = _editorUnlockStartedAt;
    final outsideWindow =
        windowStart == null || now.difference(windowStart) > editorUnlockWindow;
    if (outsideWindow) {
      _editorUnlockStartedAt = now;
      _editorUnlockTaps = 1;
    } else {
      _editorUnlockTaps += 1;
    }
    final remaining = editorUnlockTapCount - _editorUnlockTaps;
    if (remaining > 0) return remaining;
    _update(() {
      _editorSettingsUnlocked = true;
      _editorUnlockTaps = 0;
      _editorUnlockStartedAt = null;
    });
    return 0;
  }

  @override
  void dispose() {
    _json.dispose();
    _personalDataPath.dispose();
    super.dispose();
  }
}

class DataView extends StatefulWidget {
  const DataView({
    required this.controller,
    this.sessionController,
    this.codec = const PortableV4Codec(),
    this.fileDialogs = const NativeFileDialogService(),
    this.fileService = const PortableFileService(),
    this.iconBridge,
    this.iconExporter,
    this.iconImporter,
    this.showDeveloperBackup = false,
    this.onTestUpdate,
    this.personalDataPath,
    this.onMovePersonalData,
    super.key,
  });

  final PlannerApplicationController controller;
  final DataSessionController? sessionController;
  final PortableV4Codec codec;
  final NativeFileDialogService fileDialogs;
  final PortableFileService fileService;
  final PortableCustomIconBridge? iconBridge;
  final PortableIconExporter? iconExporter;
  final PortableIconImporter? iconImporter;

  /// Maintenance-only escape hatch. Normal application workspaces leave the
  /// developer backup surface absent, independently of editor-tool unlocking.
  final bool showDeveloperBackup;
  final VoidCallback? onTestUpdate;
  final String? personalDataPath;
  final Future<void> Function(String destinationPath)? onMovePersonalData;

  @override
  State<DataView> createState() => _DataViewState();
}

class _DataViewState extends State<DataView> {
  final ScrollController _scroll = ScrollController();
  late final DataSessionController _session;
  late final bool _ownsSession;
  late final Listenable _changes;

  @override
  void initState() {
    super.initState();
    _ownsSession = widget.sessionController == null;
    _session = widget.sessionController ?? DataSessionController();
    final personalDataPath = widget.personalDataPath?.trim();
    if (_session._personalDataPath.text.isEmpty &&
        personalDataPath != null &&
        personalDataPath.isNotEmpty) {
      _session._personalDataPath.text = personalDataPath;
    }
    _changes = Listenable.merge(<Listenable>[
      ...widget.controller.modes.values.map((mode) => mode.state),
      widget.controller.activeMode,
      widget.controller.deleteToolsEnabled,
      widget.controller.marketTax,
      widget.controller.afkWeightProfile,
      _session,
    ]);
  }

  @override
  void dispose() {
    _scroll.dispose();
    if (_ownsSession) _session.dispose();
    super.dispose();
  }

  void _setStatus(String message, {bool error = false}) {
    if (!mounted) return;
    _session._update(() {
      _session._status = message;
      _session._statusError = error;
    });
  }

  Future<void> _export() async {
    if (_session._busy || _session._movingPersonalData) return;
    _session._update(() => _session._busy = true);
    try {
      final compact = widget.codec.export(
        widget.controller.documentSnapshot,
        scopes: _session._scopes,
        includeMarketTax: true,
        iconExporter: widget.iconExporter ?? widget.iconBridge?.export,
      );
      final formatted = const JsonEncoder.withIndent(
        '  ',
      ).convert(jsonDecode(compact));
      _session._json.value = TextEditingValue(
        text: formatted,
        selection: TextSelection.collapsed(offset: formatted.length),
      );
      _session._update(() => _session._jsonVisible = true);
      final path = await widget.fileDialogs.pickJsonDestination();
      if (path == null) {
        _setStatus(
          'Export JSON is ready in the editor; file save was canceled.',
        );
        return;
      }
      final result = await widget.fileService.saveJson(path, formatted);
      _setStatus('Exported ${result.byteCount} bytes to ${result.targetPath}.');
    } on Object catch (error) {
      _setStatus('Export failed: $error', error: true);
    } finally {
      if (mounted) _session._update(() => _session._busy = false);
    }
  }

  void _showPortableExeNotice() {
    _setStatus(
      'Portable EXE packaging is unavailable in this build. '
      'Use Export JSON for selective sharing.',
    );
  }

  Future<void> _import() async {
    if (_session._busy || _session._movingPersonalData) return;
    if (_session._json.text.trim().isEmpty) {
      _session._update(() => _session._jsonVisible = true);
      _setStatus(
        'Paste portable JSON into the editor, then choose Import JSON.',
      );
      return;
    }
    _session._update(() {
      _session._busy = true;
      _session._status = null;
      _session._statusError = false;
    });
    final beforeImport = widget.controller.documentSnapshot;
    try {
      final imported = widget.iconBridge == null
          ? widget.codec.import(
              beforeImport,
              _session._json.text,
              confirmLegacyFullReplacement: true,
              iconImporter: widget.iconImporter,
            )
          : await widget.iconBridge!.materializeImport(
              beforeImport,
              _session._json.text,
              confirmLegacyFullReplacement: true,
            );
      final importedState = imported.state.showDeleteTools
          ? imported.state.copyWith(showDeleteTools: false)
          : imported.state;
      try {
        await widget.controller.updateDocumentDurably((_) => importedState);
      } on Object {
        if (widget.iconBridge case final bridge?) {
          await bridge.discardUncommittedImport(beforeImport, imported.state);
        }
        rethrow;
      }
      if (mounted) {
        _session._update(() {
          _session._status = null;
          _session._statusError = false;
        });
      }
    } on Object catch (error) {
      _setStatus('Import failed; no state changed: $error', error: true);
    } finally {
      if (mounted) _session._update(() => _session._busy = false);
    }
  }

  void _commitMastery(CraftMode mode, String source) {
    final parsed = parsePlannerNumber(source);
    if (parsed == null || !parsed.isFinite) return;
    final mastery = parsed.floor().clamp(0, 3000);
    widget.controller.updateDocument((document) {
      return switch (mode) {
        CraftMode.alchemy => document.copyWith(
          alchemy: document.alchemy.copyWith(
            alchemyMastery: mastery,
            compatibility: document.alchemy.compatibility.copyWith(
              alchemyYield: alchemyExpectedOutput(mastery.toDouble(), 1, 4),
            ),
          ),
        ),
        CraftMode.cooking => document.copyWith(
          cooking: document.cooking.copyWith(cookingMastery: mastery),
        ),
        CraftMode.processing => document.copyWith(
          processing: document.processing.copyWith(processingMastery: mastery),
        ),
      };
    }, immediate: true);
  }

  void _updateAfkWeightProfile(
    AfkWeightProfile Function(AfkWeightProfile current) update,
  ) {
    widget.controller.updateDocument(
      (document) => document.copyWith(
        afkWeightProfile: update(document.afkWeightProfile),
      ),
      immediate: true,
    );
  }

  void _commitAfkWeightNumber(
    String source,
    AfkWeightProfile Function(AfkWeightProfile current, double value) update,
  ) {
    final parsed = parsePlannerNumber(source);
    if (parsed == null || !parsed.isFinite || parsed < 0) return;
    _updateAfkWeightProfile((current) => update(current, parsed));
  }

  Future<void> _browsePersonalDataPath() async {
    if (_session._movingPersonalData || _session._busy) return;
    try {
      final selected = await widget.fileDialogs.pickDirectory(
        initialPath: _session._personalDataPath.text,
      );
      if (selected == null || !mounted) return;
      _session._personalDataPath.value = TextEditingValue(
        text: selected,
        selection: TextSelection.collapsed(offset: selected.length),
      );
    } on PlatformException catch (error) {
      _setStatus(
        error.message ?? 'The Windows folder picker could not be opened.',
        error: true,
      );
    }
  }

  Future<void> _movePersonalData() async {
    final move = widget.onMovePersonalData;
    final destination = _session._personalDataPath.text.trim();
    if (move == null ||
        _session._movingPersonalData ||
        _session._busy ||
        destination.isEmpty) {
      return;
    }
    final confirmed =
        await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) => Dialog(
            backgroundColor: Colors.transparent,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: AppSurface(
                role: AppSurfaceRole.modal,
                semanticLabel: 'Move personal data and restart',
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    const SectionHeader(title: 'Move personal data?'),
                    const SizedBox(height: 12),
                    const Text(
                      'Black Spirit Life will verify the complete profile in the new folder before switching. The old copy is removed only after verification, then the app restarts.',
                    ),
                    const SizedBox(height: 10),
                    SelectableText(destination),
                    const SizedBox(height: 18),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: <Widget>[
                        AppButton.label(
                          'Keep current folder',
                          onPressed: () => Navigator.pop(dialogContext, false),
                        ),
                        const SizedBox(width: 8),
                        AppButton.label(
                          'Move and restart',
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
    if (!confirmed || !mounted) return;
    _session._update(() {
      _session._movingPersonalData = true;
      _session._status = 'Verifying and moving personal data...';
      _session._statusError = false;
    });
    try {
      await move(destination);
      if (mounted) {
        _setStatus('Personal data moved. Restarting Black Spirit Life...');
      }
    } on Object catch (error) {
      _setStatus('$error', error: true);
    } finally {
      if (mounted) {
        _session._update(() => _session._movingPersonalData = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _changes,
    builder: (context, _) => AppSurface(
      padding: const EdgeInsets.all(14),
      semanticLabel: 'Craft profile',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Expanded(
            child: ScrollConfiguration(
              behavior: ScrollConfiguration.of(
                context,
              ).copyWith(scrollbars: false),
              child: ListView(
                key: const ValueKey<String>('data-scroll'),
                controller: _scroll,
                padding: EdgeInsets.zero,
                children: <Widget>[
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final craftOutput = _craftOutput();
                      final afkLoad = Align(
                        alignment: Alignment.topLeft,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 540),
                          child: _afkLoad(),
                        ),
                      );
                      final marketSale = _marketSaleSettings(context);
                      final personalData = _personalDataSettings(context);
                      final editorSettings = _session._editorSettingsUnlocked
                          ? _editorSettings(context)
                          : null;
                      final developerBackup = widget.showDeveloperBackup
                          ? _portableSharing()
                          : null;
                      if (constraints.maxWidth < 1080) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            craftOutput,
                            const SizedBox(height: 14),
                            afkLoad,
                            const SizedBox(height: 14),
                            marketSale,
                            const SizedBox(height: 14),
                            personalData,
                            if (editorSettings != null) ...<Widget>[
                              const SizedBox(height: 14),
                              editorSettings,
                            ],
                            if (developerBackup != null) ...<Widget>[
                              const SizedBox(height: 14),
                              developerBackup,
                            ],
                          ],
                        );
                      }
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: <Widget>[
                                craftOutput,
                                const SizedBox(height: 14),
                                afkLoad,
                                if (editorSettings != null) ...<Widget>[
                                  const SizedBox(height: 14),
                                  editorSettings,
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(width: 18),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: <Widget>[
                                marketSale,
                                const SizedBox(height: 14),
                                personalData,
                                if (developerBackup != null) ...<Widget>[
                                  const SizedBox(height: 14),
                                  developerBackup,
                                ],
                              ],
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                  if (widget.showDeveloperBackup &&
                      _session._jsonVisible) ...<Widget>[
                    const SizedBox(height: 18),
                    _backupCard(),
                  ],
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
          if (_session._status != null) ...<Widget>[
            const SizedBox(height: 6),
            _statusCard(),
          ],
          Align(
            alignment: Alignment.bottomCenter,
            child: _buildVersionUnlock(),
          ),
        ],
      ),
    ),
  );

  Widget _craftOutput() {
    final document = widget.controller.documentSnapshot;
    final processing = document.processing;
    final massBatch = massProcessingBatchSize(processing.processingMastery);
    return _DataEditorCard(
      key: const ValueKey<String>('data-craft-output-card'),
      title: 'Mastery & Output',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          LayoutBuilder(
            builder: (context, constraints) {
              const gap = 10.0;
              final columns = constraints.maxWidth >= 520
                  ? 3
                  : constraints.maxWidth >= 350
                  ? 2
                  : 1;
              final fieldWidth =
                  (constraints.maxWidth - gap * (columns - 1)) / columns;
              return Wrap(
                spacing: gap,
                runSpacing: 10,
                children: <Widget>[
                  SizedBox(
                    width: fieldWidth,
                    child: _CommitNumberField(
                      key: const ValueKey<String>('D01'),
                      label: 'Alchemy mastery',
                      value: formatQuantity(
                        document.alchemy.alchemyMastery.toDouble(),
                      ),
                      onCommit: (value) =>
                          _commitMastery(CraftMode.alchemy, value),
                    ),
                  ),
                  SizedBox(
                    width: fieldWidth,
                    child: _CommitNumberField(
                      key: const ValueKey<String>('D02'),
                      label: 'Cooking mastery',
                      value: formatQuantity(
                        document.cooking.cookingMastery.toDouble(),
                      ),
                      onCommit: (value) =>
                          _commitMastery(CraftMode.cooking, value),
                    ),
                  ),
                  SizedBox(
                    width: fieldWidth,
                    child: _CommitNumberField(
                      key: const ValueKey<String>('D03'),
                      label: 'Processing mastery',
                      value: formatQuantity(
                        processing.processingMastery.toDouble(),
                      ),
                      onCommit: (value) =>
                          _commitMastery(CraftMode.processing, value),
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: IntrinsicWidth(
              child: _DataOptionPill(
                key: const ValueKey<String>('D05'),
                label: 'Mass processing stone',
                value: processing.useMassProcessing,
                onChanged: (value) =>
                    widget.controller.modes[CraftMode.processing]!.updateState(
                      (state) => state.copyWith(useMassProcessing: value),
                      immediate: true,
                    ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              const gap = 10.0;
              final cardWidth = constraints.maxWidth >= 360
                  ? (constraints.maxWidth - gap) / 2
                  : constraints.maxWidth;
              return Wrap(
                spacing: gap,
                runSpacing: 10,
                children: <Widget>[
                  SizedBox(
                    width: cardWidth,
                    child: _DataStatCard(
                      label: 'Alchemy result',
                      value: formatQuantity(
                        document.alchemy.compatibility.alchemyYield,
                      ),
                      detail: '${document.alchemy.alchemyMastery} mastery',
                    ),
                  ),
                  SizedBox(
                    width: cardWidth,
                    child: _DataStatCard(
                      label: 'Mass batch',
                      value: processing.useMassProcessing
                          ? '$massBatch recipes'
                          : 'Off',
                      detail: '${processing.processingMastery} mastery',
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _afkLoad() {
    final afkWeight = widget.controller.documentSnapshot.afkWeightProfile;
    return _DataEditorCard(
      key: const ValueKey<String>('data-afk-load-card'),
      title: 'AFK Load',
      child: _AfkWeightProfileEditor(
        profile: afkWeight,
        expanded: _session._afkWeightExpanded,
        onToggle: () => _session._update(
          () => _session._afkWeightExpanded = !_session._afkWeightExpanded,
        ),
        onMaximumWeightCommitted: (source) => _commitAfkWeightNumber(
          source,
          (current, value) => current.copyWith(maximumWeightLt: value),
        ),
        onCurrentWeightCommitted: (source) => _commitAfkWeightNumber(
          source,
          (current, value) => current.copyWith(currentCarriedWeightLt: value),
        ),
        onSafetyBufferCommitted: (source) => _commitAfkWeightNumber(
          source,
          (current, value) => current.copyWith(safetyBufferLt: value),
        ),
        onFeatheryStepsChanged: (level) => _updateAfkWeightProfile(
          (current) => current.copyWith(featheryStepsLevel: level),
        ),
      ),
    );
  }

  void _updateMarketTax(MarketTax Function(MarketTax current) update) {
    widget.controller.updateDocument(
      (document) => document.copyWith(
        marketTax: update(document.marketTax).copyWith(enabled: true),
      ),
      immediate: true,
    );
  }

  Widget _marketSaleSettings(BuildContext context) {
    final tax = widget.controller.documentSnapshot.marketTax.copyWith(
      enabled: true,
    );
    final familyFameOptions = <double>[
      ..._familyFameTiers,
      if (!_familyFameTiers.any(
        (value) => (value - tax.familyFameBonus).abs() < .0000001,
      ))
        tax.familyFameBonus,
    ]..sort();
    return _DataEditorCard(
      key: const ValueKey<String>('data-market-sale-card'),
      title: 'Market Sales',
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 500;
          final options = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Tooltip(
                message: 'Adds the Value Pack collection bonus.',
                child: AppToggle(
                  key: const ValueKey<String>('D16'),
                  leading: const MarketBonusIcon(
                    artwork: MarketBonusArtwork.valuePack,
                  ),
                  switchAtEnd: true,
                  label: 'Value Pack',
                  description: '+30% collection bonus',
                  value: tax.valuePack,
                  onChanged: (value) => _updateMarketTax(
                    (current) => current.copyWith(valuePack: value),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Tooltip(
                message: 'Adds the Rich Merchant’s Ring collection bonus.',
                child: AppToggle(
                  key: const ValueKey<String>('D18'),
                  leading: const MarketBonusIcon(
                    artwork: MarketBonusArtwork.richMerchantsRing,
                  ),
                  switchAtEnd: true,
                  label: 'Rich Merchant’s Ring',
                  description: '+5% collection bonus',
                  value: tax.merchantRing,
                  onChanged: (value) => _updateMarketTax(
                    (current) => current.copyWith(merchantRing: value),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Tooltip(
                message:
                    'Family Fame tiers: 1,000–3,999 grants +0.5%, '
                    '4,000–6,999 grants +1.0%, and 7,000+ grants +1.5%.',
                child: _DataField(
                  label: 'Family Fame bonus',
                  stretchChild: true,
                  child: SizedBox(
                    key: const ValueKey<String>('D17'),
                    height: 42,
                    child: AppSelect<double>(
                      value: tax.familyFameBonus,
                      items: familyFameOptions,
                      labelFor: _familyFameLabel,
                      semanticLabel: 'D17 Family Fame bonus tier',
                      onChanged: (value) {
                        if (value == null) return;
                        _updateMarketTax(
                          (current) => current.copyWith(familyFameBonus: value),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ],
          );
          final result = _MarketReturnSummary(tax: tax);
          if (!wide) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[options, const SizedBox(height: 12), result],
            );
          }
          return IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Expanded(flex: 3, child: options),
                const SizedBox(width: 14),
                Expanded(flex: 2, child: result),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _personalDataSettings(BuildContext context) => _DataEditorCard(
    key: const ValueKey<String>('data-personal-data-card'),
    title: 'Personal data',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          'Favorites, checklist items, custom recipes, icons, and planner settings are stored only on this PC. They are not included in the installer.',
          style: context.visualTheme.typography.body,
        ),
        const SizedBox(height: 12),
        _DataField(
          label: 'Personal data folder',
          stretchChild: true,
          child: Row(
            children: <Widget>[
              Expanded(
                child: SizedBox(
                  height: 42,
                  child: AppTextField(
                    key: const ValueKey<String>('data-personal-data-path'),
                    controller: _session._personalDataPath,
                    semanticLabel: 'Personal data folder path',
                    maxLines: 1,
                    enabled:
                        widget.onMovePersonalData != null &&
                        !_session._movingPersonalData &&
                        !_session._busy,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              AppButton(
                key: const ValueKey<String>('data-personal-data-browse'),
                role: AppButtonRole.secondary,
                semanticLabel: 'Browse for personal data folder',
                tooltip: 'Browse for folder',
                minimumSize: const Size(42, 42),
                padding: const EdgeInsets.all(8),
                onPressed:
                    widget.onMovePersonalData == null ||
                        _session._movingPersonalData ||
                        _session._busy
                    ? null
                    : _browsePersonalDataPath,
                child: const Icon(Icons.folder_open_outlined, size: 20),
              ),
            ],
          ),
        ),
        if (widget.onMovePersonalData != null) ...<Widget>[
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: AppButton.label(
              _session._movingPersonalData ? 'Moving...' : 'Move and restart',
              key: const ValueKey<String>('data-personal-data-move'),
              role: AppButtonRole.primary,
              onPressed: _session._movingPersonalData || _session._busy
                  ? null
                  : _movePersonalData,
            ),
          ),
        ],
      ],
    ),
  );

  Widget _portableSharing() => _DataEditorCard(
    key: const ValueKey<String>('data-portable-sharing-card'),
    title: 'Developer Backup',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _DataField(
          label: 'Export scope',
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final entry in _scopeEntries(_session._scopes).entries)
                _DataOptionPill(
                  key: ValueKey<String>('D06:${entry.key}'),
                  label: entry.key == 'recipes' ? 'Recipes/icons' : entry.key,
                  value: entry.value,
                  onChanged: (value) => _session._update(
                    () => _session._scopes = _withScope(
                      _session._scopes,
                      entry.key,
                      value,
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: <Widget>[
            AppButton.label(
              'Export JSON',
              key: const ValueKey<String>('D07'),
              role: AppButtonRole.primary,
              onPressed: null,
              onPressedAsync: _session._busy || _session._movingPersonalData
                  ? null
                  : _export,
            ),
            AppButton.label(
              'Import JSON',
              key: const ValueKey<String>('D10'),
              onPressed: null,
              onPressedAsync: _session._busy || _session._movingPersonalData
                  ? null
                  : _import,
            ),
            AppButton.label(
              'Portable EXE',
              key: const ValueKey<String>('D12'),
              onPressed: _session._busy || _session._movingPersonalData
                  ? null
                  : _showPortableExeNotice,
            ),
            AppButton.label(
              _session._jsonVisible ? 'Hide JSON' : 'Show JSON',
              key: ValueKey<String>(_session._jsonVisible ? 'D11' : 'D08'),
              onPressed: () => _session._update(
                () => _session._jsonVisible = !_session._jsonVisible,
              ),
            ),
          ],
        ),
      ],
    ),
  );

  Widget _buildVersionUnlock() {
    final version = widget.controller.documentSnapshot.applicationVersion
        .trim();
    final label = version.isEmpty ? 'App build' : 'App build $version';
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        key: const ValueKey<String>('data-editor-unlock-build'),
        behavior: HitTestBehavior.opaque,
        onTap: () {
          final wasLocked = !_session.editorSettingsUnlocked;
          _session.registerEditorUnlockTap();
          if (wasLocked && _session.editorSettingsUnlocked) {
            _setStatus('Editor settings unlocked for this session.');
          }
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: context.visualTheme.typography.meta.copyWith(
              color: context.visualTheme.palette.textMuted.withAlpha(190),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _restoreHiddenItems() async {
    try {
      await widget.controller.updateDocumentDurably(
        (document) => const PlannerStateTransactions()
            .restoreHiddenItems(
              state: document,
              mode: widget.controller.active.mode,
            )
            .state,
      );
      _session._update(() {
        _session._status = 'Hidden items restored.';
        _session._statusError = false;
      });
    } on Object catch (error) {
      _session._update(() {
        _session._status = 'Hidden items could not be restored. $error';
        _session._statusError = true;
      });
    }
  }

  Widget _editorSettings(BuildContext context) {
    final activeState = widget.controller.active.state.value;
    final hiddenCount = <String>{
      ...activeState.hiddenItems.map((name) => name.trim().toLowerCase()),
      for (final entry in activeState.recipeEdits.entries)
        if (entry.value == null) entry.key.trim().toLowerCase(),
    }.where((name) => name.isNotEmpty).length;
    return _DataEditorCard(
      key: const ValueKey<String>('data-editor-settings-card'),
      title: 'Editor Settings',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Align(
            alignment: Alignment.centerLeft,
            child: IntrinsicWidth(
              child: _DataOptionPill(
                key: const ValueKey<String>('D13'),
                label: 'Show Inventory & Recipe Editor',
                value: widget.controller.documentSnapshot.showDeleteTools,
                onChanged: (value) => widget.controller.updateDocument(
                  (document) => document.copyWith(showDeleteTools: value),
                  immediate: true,
                ),
              ),
            ),
          ),
          if (widget.onTestUpdate != null) ...<Widget>[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: AppButton.label(
                'Test update',
                key: const ValueKey<String>('data-test-update'),
                role: AppButtonRole.secondary,
                onPressed: widget.onTestUpdate,
              ),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  '$hiddenCount hidden · ${widget.controller.active.mode.label}',
                  key: const ValueKey<String>('data-hidden-summary'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.visualTheme.typography.meta.copyWith(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              AppButton(
                key: const ValueKey<String>('D14'),
                role: AppButtonRole.secondary,
                minimumSize: const Size(0, 38),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                semanticLabel: 'D14 Restore hidden items',
                onPressed: null,
                onPressedAsync: hiddenCount == 0 ? null : _restoreHiddenItems,
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    AppVectorGlyph('reset', size: 16),
                    SizedBox(width: 7),
                    Text('Restore'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _backupCard() => _DataEditorCard(
    key: const ValueKey<String>('data-backup-json-card'),
    title: 'Backup JSON',
    child: SizedBox(
      height: 220,
      child: AppTextField(
        key: const ValueKey<String>('D09'),
        controller: _session._json,
        semanticLabel: 'D09 Portable JSON editor',
        hintText:
            'Exported backup JSON appears here. Paste JSON here to import.',
        maxLines: null,
        minLines: 8,
      ),
    ),
  );

  Widget _statusCard() => AppSurface(
    key: const ValueKey<String>('data-operation-status'),
    role: AppSurfaceRole.row,
    tone: _session._statusError
        ? AppSurfaceTone.danger
        : AppSurfaceTone.success,
    semanticLabel: _session._statusError
        ? 'Operation error'
        : 'Operation success',
    child: SelectableText(_session._status!),
  );
}

class _AfkWeightProfileEditor extends StatelessWidget {
  const _AfkWeightProfileEditor({
    required this.profile,
    required this.expanded,
    required this.onToggle,
    required this.onMaximumWeightCommitted,
    required this.onCurrentWeightCommitted,
    required this.onSafetyBufferCommitted,
    required this.onFeatheryStepsChanged,
  });

  final AfkWeightProfile profile;
  final bool expanded;
  final VoidCallback onToggle;
  final ValueChanged<String> onMaximumWeightCommitted;
  final ValueChanged<String> onCurrentWeightCommitted;
  final ValueChanged<String> onSafetyBufferCommitted;
  final ValueChanged<int> onFeatheryStepsChanged;

  static const _featheryLevels = <int>[0, 1, 2, 3, 4, 5];

  String _featheryLabel(int level) => switch (level) {
    1 => 'I · 105%',
    2 => 'II · 110%',
    3 => 'III · 115%',
    4 => 'IV · 120%',
    5 => 'V · 125%',
    _ => 'None · 100%',
  };

  @override
  Widget build(BuildContext context) {
    final spec = context.visualTheme;
    final summary = profile.isConfigured
        ? '${formatQuantity(profile.safeLimitLt)} LT available'
        : 'Set your character weight once';
    final safeStop = (profile.penaltyThresholdLt - profile.safetyBufferLt)
        .clamp(0, double.infinity)
        .toDouble();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: spec.palette.primary.withAlpha(28),
                borderRadius: BorderRadius.circular(spec.geometry.fieldRadius),
                border: Border.all(color: spec.palette.trim.withAlpha(150)),
              ),
              alignment: Alignment.center,
              child: Icon(
                Icons.scale_outlined,
                size: 21,
                color: spec.palette.primaryBright,
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'Character weight',
                    maxLines: 1,
                    style: spec.typography.body.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    summary,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: spec.typography.meta.copyWith(
                      color: profile.isConfigured
                          ? spec.palette.success
                          : spec.palette.textMuted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            AppButton.label(
              expanded
                  ? 'Done'
                  : profile.isConfigured
                  ? 'Edit'
                  : 'Set up',
              key: const ValueKey<String>('data-afk-load-toggle'),
              onPressed: onToggle,
              role: expanded ? AppButtonRole.primary : AppButtonRole.secondary,
              minimumSize: const Size(74, 38),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              semanticLabel:
                  'AFK Load character weight settings, '
                  '${expanded ? 'expanded' : 'collapsed'}',
            ),
          ],
        ),
        AnimatedSize(
          duration: spec.motion.interactionDuration,
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: expanded
              ? Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final fieldWidth = constraints.maxWidth >= 420
                          ? (constraints.maxWidth - 10) / 2
                          : constraints.maxWidth;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: <Widget>[
                              SizedBox(
                                width: fieldWidth,
                                child: _CommitNumberField(
                                  key: const ValueKey<String>(
                                    'data-afk-maximum-weight',
                                  ),
                                  label: 'Character Max LT',
                                  value: formatQuantity(
                                    profile.maximumWeightLt,
                                  ),
                                  onCommit: onMaximumWeightCommitted,
                                  suffixText: 'LT',
                                ),
                              ),
                              SizedBox(
                                width: fieldWidth,
                                child: _CommitNumberField(
                                  key: const ValueKey<String>(
                                    'data-afk-current-weight',
                                  ),
                                  label: 'Weight already carried',
                                  value: formatQuantity(
                                    profile.currentCarriedWeightLt,
                                  ),
                                  onCommit: onCurrentWeightCommitted,
                                  suffixText: 'LT',
                                ),
                              ),
                              SizedBox(
                                width: fieldWidth,
                                child: _CommitNumberField(
                                  key: const ValueKey<String>(
                                    'data-afk-safety-buffer',
                                  ),
                                  label: 'LT to keep free',
                                  value: formatQuantity(profile.safetyBufferLt),
                                  onCommit: onSafetyBufferCommitted,
                                  suffixText: 'LT',
                                ),
                              ),
                              SizedBox(
                                width: fieldWidth,
                                child: _DataField(
                                  label: 'Fairy · Feathery Steps',
                                  stretchChild: true,
                                  child: SizedBox(
                                    height: 42,
                                    child: AppSelect<int>(
                                      key: const ValueKey<String>(
                                        'data-afk-feathery-steps',
                                      ),
                                      value: profile.featheryStepsLevel,
                                      items: _featheryLevels,
                                      labelFor: _featheryLabel,
                                      semanticLabel:
                                          'Feathery Steps weight threshold',
                                      onChanged: (value) {
                                        if (value != null) {
                                          onFeatheryStepsChanged(value);
                                        }
                                      },
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.only(top: 11),
                            decoration: BoxDecoration(
                              border: Border(
                                top: BorderSide(
                                  color: spec.palette.trim.withAlpha(105),
                                ),
                              ),
                            ),
                            child: Wrap(
                              spacing: 18,
                              runSpacing: 6,
                              alignment: WrapAlignment.spaceBetween,
                              children: <Widget>[
                                _AfkWeightMetric(
                                  label: 'AVAILABLE FOR MATERIALS',
                                  value: profile.isConfigured
                                      ? '${formatQuantity(profile.safeLimitLt)} LT'
                                      : 'Enter Max LT',
                                  emphasized: profile.isConfigured,
                                ),
                                _AfkWeightMetric(
                                  label: 'SAFE STOP',
                                  value: profile.isConfigured
                                      ? '${formatQuantity(safeStop)} LT'
                                      : 'Not calculated',
                                ),
                              ],
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}

class _AfkWeightMetric extends StatelessWidget {
  const _AfkWeightMetric({
    required this.label,
    required this.value,
    this.emphasized = false,
  });

  final String label;
  final String value;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final spec = context.visualTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          label,
          style: spec.typography.label.copyWith(
            color: _dataFieldLabelColor(spec),
            fontSize: 10,
            fontWeight: FontWeight.w800,
            height: 1.15,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          style: spec.typography.body.copyWith(
            color: emphasized ? spec.palette.success : spec.palette.text,
            fontSize: emphasized ? 18 : 15,
            fontWeight: FontWeight.w800,
            height: 1.15,
          ),
        ),
      ],
    );
  }
}

/// The local semantic card used by the original profile workspace. Its role is
/// deliberately expressed through [AppSurface] so retained themes can restyle
/// the material without changing the profile screen's composition or behavior.
class _DataEditorCard extends StatelessWidget {
  const _DataEditorCard({required this.title, required this.child, super.key});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final spec = context.visualTheme;
    final denseLayout = spec.usesDenseSplitLayout;
    return AppSurface(
      role: AppSurfaceRole.row,
      padding: EdgeInsets.all(denseLayout ? 12 : 14),
      semanticLabel: title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            title,
            style: spec.typography.body.copyWith(
              color: _dataTitleColor(spec),
              fontSize: 17,
              fontWeight: FontWeight.w700,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _DataField extends StatelessWidget {
  const _DataField({
    required this.label,
    required this.child,
    this.stretchChild = false,
  });

  final String label;
  final Widget child;
  final bool stretchChild;

  @override
  Widget build(BuildContext context) {
    final spec = context.visualTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          label.toUpperCase(),
          style: spec.typography.label.copyWith(
            color: _dataFieldLabelColor(spec),
            fontSize: 12,
            fontWeight: FontWeight.w700,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 4),
        if (stretchChild)
          child
        else
          Align(alignment: Alignment.centerLeft, child: child),
      ],
    );
  }
}

class _DataOptionPill extends StatelessWidget {
  const _DataOptionPill({
    required this.label,
    required this.value,
    required this.onChanged,
    super.key,
  });

  final String label;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final spec = context.visualTheme;
    final ledger = spec.isIlluminatedLedger;
    final sakura = spec.isSakuraNightGarden;
    final denseLayout = spec.usesDenseSplitLayout;
    final standard = spec.isStandard ? context.standardVisual : null;
    return AppButton(
      role: AppButtonRole.optionPill,
      selected: value,
      minimumSize: denseLayout ? const Size(0, 38) : Size.zero,
      padding: denseLayout
          ? const EdgeInsets.fromLTRB(4, 2, 13, 2)
          : const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      semanticLabel: '$label: ${value ? 'on' : 'off'}',
      onPressed: onChanged == null ? null : () => onChanged!(!value),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          AnimatedContainer(
            duration: spec.motion.interactionDuration,
            width: denseLayout ? 34 : 30,
            height: denseLayout ? 34 : 24,
            decoration: BoxDecoration(
              gradient: ledger
                  ? (value
                        ? spec.materials.primary
                        : spec.materials.surfaceRaised)
                  : sakura
                  ? (value
                        ? spec.materials.secondary
                        : spec.materials.surfaceRaised)
                  : StandardSpec.accentGlass(
                      standard!.accentHue,
                      topAlpha: value ? 126 : 42,
                      bottomAlpha: value ? 46 : 12,
                      neon: standard.neon,
                    ),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: ledger
                    ? spec.palette.trim.withAlpha(value ? 220 : 88)
                    : sakura
                    ? (value
                          ? spec.palette.secondary
                          : spec.palette.trim.withAlpha(150))
                    : StandardSpec.accentBrush(
                        standard!.accentHue,
                        alpha: value ? .72 : .24,
                        neon: standard.neon,
                      ),
              ),
            ),
            alignment: Alignment.center,
            child: value
                ? AppVectorGlyph('check', size: denseLayout ? 14 : 12)
                : null,
          ),
          const SizedBox(width: 8),
          Text(
            label.toUpperCase(),
            style: TextStyle(
              inherit: true,
              fontFamily: spec.typography.label.fontFamily,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              // Avalonia's profile option labels use the platform font's native
              // glyph advance. Inheriting the retained theme's display
              // tracking makes the scope pills too wide and changes their
              // WrapPanel row breaks at both protected window sizes.
              letterSpacing: 0,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

class _DataStatCard extends StatelessWidget {
  const _DataStatCard({
    required this.label,
    required this.value,
    required this.detail,
  });

  final String label;
  final String value;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final spec = context.visualTheme;
    return AppSurface(
      role: AppSurfaceRole.panel,
      padding: const EdgeInsets.all(11),
      semanticLabel: '$label, $value, $detail',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            label.toUpperCase(),
            style: spec.typography.label.copyWith(
              color: _dataStatLabelColor(spec),
              fontSize: 11,
              fontWeight: FontWeight.w700,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            style: spec.typography.body.copyWith(
              color: spec.palette.text,
              fontSize: 18,
              fontWeight: FontWeight.w700,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            detail,
            style: spec.typography.meta.copyWith(
              color: _dataStatDetailColor(spec),
              fontSize: 11,
              fontWeight: FontWeight.w600,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

class _MarketReturnSummary extends StatelessWidget {
  const _MarketReturnSummary({required this.tax});

  final MarketTax tax;

  @override
  Widget build(BuildContext context) {
    final spec = context.visualTheme;
    final netRate = marketNetRate(tax);
    final netLabel = _formatMarketPercent(netRate);
    final detail = '${_formatMarketPercent(1 - netRate)} deducted';
    return AppSurface(
      key: const ValueKey<String>('data-market-net-summary'),
      role: AppSurfaceRole.panel,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      semanticLabel: 'Net sale return $netLabel; $detail',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                Icons.account_balance_wallet_outlined,
                size: 17,
                color: spec.palette.primaryBright,
              ),
              const SizedBox(width: 7),
              Text(
                'YOU RECEIVE',
                style: spec.typography.label.copyWith(
                  color: _dataStatLabelColor(spec),
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  height: 1.1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          Text(
            netLabel,
            key: const ValueKey<String>('data-market-net-value'),
            style: spec.typography.body.copyWith(
              color: spec.palette.text,
              fontSize: 25,
              fontWeight: FontWeight.w800,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'of the listed price',
            style: spec.typography.meta.copyWith(
              color: _dataStatDetailColor(spec),
              fontSize: 11,
              fontWeight: FontWeight.w600,
              height: 1.15,
            ),
          ),
          const SizedBox(height: 9),
          Container(
            padding: const EdgeInsets.only(top: 8),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: spec.palette.trim.withAlpha(105)),
              ),
            ),
            child: Text(
              detail,
              key: const ValueKey<String>('data-market-net-detail'),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: spec.typography.meta.copyWith(
                color: _dataStatDetailColor(spec),
                fontSize: 11,
                fontWeight: FontWeight.w700,
                height: 1.2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CommitNumberField extends StatefulWidget {
  const _CommitNumberField({
    required this.label,
    required this.value,
    required this.onCommit,
    this.suffixText,
    super.key,
  });

  final String label;
  final String value;
  final ValueChanged<String> onCommit;
  final String? suffixText;

  @override
  State<_CommitNumberField> createState() => _CommitNumberFieldState();
}

class _CommitNumberFieldState extends State<_CommitNumberField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.value,
  );
  late final FocusNode _focus = FocusNode()..addListener(_focusChanged);

  void _focusChanged() {
    if (!_focus.hasFocus) widget.onCommit(_controller.text);
  }

  @override
  void didUpdateWidget(_CommitNumberField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_focus.hasFocus && oldWidget.value != widget.value) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _focus.removeListener(_focusChanged);
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _DataField(
    label: widget.label,
    stretchChild: true,
    child: _DataNumberTextField(
      controller: _controller,
      focusNode: _focus,
      onSubmitted: widget.onCommit,
      suffixText: widget.suffixText,
    ),
  );
}

/// A consistently sized numeric field for the Craft Profile cards.
class _DataNumberTextField extends StatelessWidget {
  const _DataNumberTextField({
    required this.controller,
    required this.focusNode,
    required this.onSubmitted,
    this.suffixText,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onSubmitted;
  final String? suffixText;

  @override
  Widget build(BuildContext context) {
    final spec = context.visualTheme;
    final ledger = spec.isIlluminatedLedger;
    final sakura = spec.isSakuraNightGarden;
    final denseLayout = spec.usesDenseSplitLayout;
    final standard = spec.isStandard ? context.standardVisual : null;
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(spec.geometry.fieldRadius),
      borderSide: BorderSide(
        color: ledger
            ? spec.palette.trim.withAlpha(138)
            : sakura
            ? spec.palette.trim.withAlpha(176)
            : StandardSpec.accentBrush(
                standard!.accentHue,
                alpha: .32,
                neon: standard.neon,
              ),
      ),
    );
    Widget field = TextField(
      controller: controller,
      focusNode: focusNode,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: <TextInputFormatter>[
        FilteringTextInputFormatter.allow(RegExp(r'[-0-9.,]')),
      ],
      onSubmitted: onSubmitted,
      textAlign: TextAlign.right,
      textAlignVertical: TextAlignVertical.center,
      cursorColor: spec.palette.primaryBright,
      style: spec.typography.body.copyWith(
        fontWeight: FontWeight.w700,
        height: denseLayout ? 1.15 : spec.typography.body.height,
        leadingDistribution: denseLayout
            ? TextLeadingDistribution.even
            : spec.typography.body.leadingDistribution,
      ),
      decoration: InputDecoration(
        // The Ledger control is clamped to its authored desktop height below;
        // using the non-dense single-line template keeps Georgia's baseline
        // centered instead of pinning it to the top edge.
        isDense: !denseLayout,
        filled: ledger || sakura,
        fillColor: ledger
            ? spec.palette.surfaceRaised.withAlpha(212)
            : sakura
            ? spec.palette.surfaceInset.withAlpha(232)
            : null,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
        suffixText: suffixText,
        suffixStyle: spec.typography.meta.copyWith(
          color: spec.palette.textMuted,
          fontWeight: FontWeight.w700,
        ),
        border: border,
        enabledBorder: border,
        focusedBorder: border.copyWith(
          borderSide: BorderSide(
            color: ledger
                ? spec.palette.primaryBright
                : sakura
                ? spec.palette.primaryBright
                : StandardSpec.accentBrush(
                    standard!.accentHue,
                    neon: standard.neon,
                  ),
            width: denseLayout ? 1.7 : 1.4,
          ),
        ),
      ),
    );
    if (spec.isStandard) {
      field = DecoratedBox(
        decoration: BoxDecoration(
          gradient: StandardSpec.accentGlass(
            standard!.accentHue,
            topAlpha: 54,
            bottomAlpha: 18,
            neon: standard.neon,
          ),
          borderRadius: BorderRadius.circular(6),
        ),
        child: field,
      );
    }
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final lineHeight =
        (spec.typography.body.fontSize ?? 14) *
        (denseLayout ? 1.15 : (spec.typography.body.height ?? 1)) *
        textScale;
    return SizedBox(
      height: (lineHeight + 16).clamp(42.0, 46.0).toDouble(),
      child: field,
    );
  }
}

Map<String, bool> _scopeEntries(PortableScopes scopes) => <String, bool>{
  'recipes': scopes.recipes,
  'inventory': scopes.inventory,
  'plans': scopes.plans,
  'choices': scopes.choices,
  'market': scopes.market,
  'settings': scopes.settings,
  'completed': scopes.completed,
  'layout': scopes.layout,
};

PortableScopes _withScope(PortableScopes source, String key, bool value) =>
    PortableScopes(
      recipes: key == 'recipes' ? value : source.recipes,
      inventory: key == 'inventory' ? value : source.inventory,
      plans: key == 'plans' ? value : source.plans,
      choices: key == 'choices' ? value : source.choices,
      market: key == 'market' ? value : source.market,
      settings: key == 'settings' ? value : source.settings,
      completed: key == 'completed' ? value : source.completed,
      layout: key == 'layout' ? value : source.layout,
    );

const List<double> _familyFameTiers = <double>[0, .005, .01, .015];

String _familyFameLabel(double value) {
  if ((value - 0).abs() < .0000001) return 'Below 1,000 · +0%';
  if ((value - .005).abs() < .0000001) {
    return '1,000–3,999 · +0.5%';
  }
  if ((value - .01).abs() < .0000001) {
    return '4,000–6,999 · +1.0%';
  }
  if ((value - .015).abs() < .0000001) {
    return '7,000+ · +1.5%';
  }
  final sign = value >= 0 ? '+' : '';
  return 'Imported · $sign${_formatMarketPercent(value)}';
}

String _formatMarketPercent(double fraction) {
  final percent = fraction * 100;
  final tenths = percent * 10;
  final hundredths = percent * 100;
  final thousandths = percent * 1000;
  final digits = (percent - percent.roundToDouble()).abs() < .0000001
      ? 0
      : (tenths - tenths.roundToDouble()).abs() < .0000001
      ? 1
      : (hundredths - hundredths.roundToDouble()).abs() < .0000001
      ? 2
      : (thousandths - thousandths.roundToDouble()).abs() < .0000001
      ? 3
      : 3;
  return '${formatQuantity(percent, fractionDigits: digits)}%';
}

Color _dataTitleColor(ThemeSpec spec) =>
    spec.isStandard ? const Color(0xFFFFF1BB) : spec.palette.text;

Color _dataFieldLabelColor(ThemeSpec spec) =>
    spec.isStandard ? const Color(0xFFD7C783) : spec.palette.trimBright;

Color _dataStatLabelColor(ThemeSpec spec) =>
    spec.isStandard ? const Color(0xFFC9B978) : spec.palette.trimBright;

Color _dataStatDetailColor(ThemeSpec spec) =>
    spec.isStandard ? const Color(0xFFAFC0BA) : spec.palette.textMuted;
