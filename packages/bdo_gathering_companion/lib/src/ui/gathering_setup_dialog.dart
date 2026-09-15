import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../domain/bairog_calculator.dart';
import '../domain/models.dart';
import 'buff_picker.dart';
import 'theme.dart';

const gatheringEstimatePreferenceKey = 'gatheringEstimateSetup';

/// The same stats/options editor as the quick dialog, with immediate changes.
/// Unconfirmed example values are hints, never implicitly entered user stats.
class GatheringInlineStats extends StatelessWidget {
  const GatheringInlineStats({
    super.key,
    required this.catalog,
    required this.baseSettings,
    required this.effectiveSettings,
    required this.statsConfirmed,
    required this.onStatsChanged,
    required this.onStatsValidityChanged,
    this.enabled = true,
    this.contextId,
    this.advancedRequest = 0,
    this.onAdvancedExpandedChanged,
  });

  final Catalog catalog;
  final BairogCalculatorSettings baseSettings, effectiveSettings;
  final bool statsConfirmed, enabled;
  final void Function(BairogCalculatorSettings, bool) onStatsChanged;
  final ValueChanged<bool> onStatsValidityChanged;
  final Object? contextId;
  final int advancedRequest;
  final ValueChanged<bool>? onAdvancedExpandedChanged;

  @override
  Widget build(BuildContext context) => _GatheringSetupDialog(
    catalog: catalog,
    initial: baseSettings,
    inline: true,
    effectiveSettings: effectiveSettings,
    statsConfirmed: statsConfirmed,
    onStatsChanged: onStatsChanged,
    onStatsValidityChanged: onStatsValidityChanged,
    enabled: enabled,
    contextId: contextId,
    advancedRequest: advancedRequest,
    onAdvancedExpandedChanged: onAdvancedExpandedChanged,
  );
}

Future<BairogCalculatorSettings?> showGatheringSetupDialog({
  required BuildContext context,
  required Catalog catalog,
  required BairogCalculatorSettings initial,
  ValueChanged<BairogCalculatorSettings>? onPreview,
}) => showDialog<BairogCalculatorSettings>(
  context: context,
  barrierDismissible: false,
  builder: (context) => _GatheringSetupDialog(
    catalog: catalog,
    initial: initial,
    onPreview: onPreview,
  ),
);

class _GatheringSetupDialog extends StatefulWidget {
  const _GatheringSetupDialog({
    required this.catalog,
    required this.initial,
    this.onPreview,
    this.inline = false,
    this.effectiveSettings,
    this.statsConfirmed = true,
    this.onStatsChanged,
    this.onStatsValidityChanged,
    this.enabled = true,
    this.contextId,
    this.advancedRequest = 0,
    this.onAdvancedExpandedChanged,
  });

  final Catalog catalog;
  final BairogCalculatorSettings initial;
  final ValueChanged<BairogCalculatorSettings>? onPreview;
  final bool inline, statsConfirmed, enabled;
  final BairogCalculatorSettings? effectiveSettings;
  final void Function(BairogCalculatorSettings, bool)? onStatsChanged;
  final ValueChanged<bool>? onStatsValidityChanged;
  final Object? contextId;
  final int advancedRequest;
  final ValueChanged<bool>? onAdvancedExpandedChanged;

  @override
  State<_GatheringSetupDialog> createState() => _GatheringSetupDialogState();
}

class _GatheringSetupDialogState extends State<_GatheringSetupDialog> {
  late final TextEditingController _mastery;
  late final TextEditingController _dropRate;
  late final TextEditingController _energy;
  late final TextEditingController _energyRecovery;
  late BairogMinigameMode _minigame;
  late BairogHedgehogTier _hedgehog;
  late bool _agris;
  late bool _afuaru;
  late bool _chest;
  late bool _chestX10;
  late bool _fever;
  late bool _evergreenShard;
  late bool _afterTax;
  late Set<int> _expenses;
  String? _validationMessage;
  final _advanced = ExpansibleController();
  final _advancedKey = GlobalKey();
  bool _masteryEntered = false, _dropRateEntered = false;
  bool _lastValidity = true;
  BairogCalculatorSettings? _lastEmitted;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _mastery = TextEditingController(
      text: widget.inline && !widget.statsConfirmed
          ? ''
          : initial.mastery.toString(),
    );
    _dropRate = TextEditingController(
      text: widget.inline && !widget.statsConfirmed
          ? ''
          : _plainNumber(initial.gatheringDropRatePercent),
    );
    _energy = TextEditingController(text: _plainNumber(initial.yourEnergy));
    _energyRecovery = TextEditingController(
      text: _plainNumber(initial.naturalEnergyRecoveryPerThreeMinutes),
    );
    _syncOptions(initial);
  }

  void _syncOptions(BairogCalculatorSettings initial) {
    _minigame = initial.minigameMode;
    _hedgehog = initial.hedgehogTier;
    _agris = initial.agrisEnabled;
    _afuaru = initial.includeAfuaru;
    _chest = initial.includeChest;
    _chestX10 = initial.includeChestX10;
    _fever = initial.includeFeverTime;
    _evergreenShard = initial.includeEvergreenShard;
    _afterTax = initial.showTaxed;
    _expenses = Set<int>.from(initial.enabledExpenseItemIds);
  }

  @override
  void didUpdateWidget(_GatheringSetupDialog oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.inline) return;
    if (oldWidget.contextId != widget.contextId ||
        (oldWidget.statsConfirmed && !widget.statsConfirmed)) {
      _resetFields();
      _reportValidityAfterBuild();
    } else {
      final before = oldWidget.initial;
      final next = widget.initial;
      final confirmedExternally =
          !oldWidget.statsConfirmed &&
          widget.statsConfirmed &&
          !(_masteryEntered && _dropRateEntered);
      void sync(
        TextEditingController controller,
        num oldValue,
        num newValue,
        num? echoedValue, {
        bool force = false,
      }) {
        if (!widget.statsConfirmed &&
            ((controller == _mastery && !_masteryEntered) ||
                (controller == _dropRate && !_dropRateEntered))) {
          return;
        }
        if (force || (oldValue != newValue && newValue != echoedValue)) {
          controller.text = _plainNumber(newValue);
        }
      }

      sync(
        _mastery,
        before.mastery,
        next.mastery,
        _lastEmitted?.mastery,
        force: confirmedExternally,
      );
      sync(
        _dropRate,
        before.gatheringDropRatePercent,
        next.gatheringDropRatePercent,
        _lastEmitted?.gatheringDropRatePercent,
        force: confirmedExternally,
      );
      sync(
        _energy,
        before.yourEnergy,
        next.yourEnergy,
        _lastEmitted?.yourEnergy,
      );
      sync(
        _energyRecovery,
        before.naturalEnergyRecoveryPerThreeMinutes,
        next.naturalEnergyRecoveryPerThreeMinutes,
        _lastEmitted?.naturalEnergyRecoveryPerThreeMinutes,
      );
      if (!before.hasSameValuesAs(next)) {
        _syncOptions(next);
        _lastEmitted = null;
      }
      _reportValidityAfterBuild();
    }
    if (oldWidget.advancedRequest != widget.advancedRequest) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _advanced.expand();
        final target = _advancedKey.currentContext;
        if (target != null) {
          Scrollable.ensureVisible(
            target,
            duration: const Duration(milliseconds: 200),
          );
        }
      });
    }
  }

  void _resetFields() {
    final initial = widget.initial;
    _mastery.text = widget.statsConfirmed ? initial.mastery.toString() : '';
    _dropRate.text = widget.statsConfirmed
        ? _plainNumber(initial.gatheringDropRatePercent)
        : '';
    _energy.text = _plainNumber(initial.yourEnergy);
    _energyRecovery.text = _plainNumber(
      initial.naturalEnergyRecoveryPerThreeMinutes,
    );
    _masteryEntered = _dropRateEntered = false;
    _lastEmitted = null;
    _syncOptions(initial);
  }

  bool get _untouchedOptional =>
      widget.inline &&
      !widget.statsConfirmed &&
      !_masteryEntered &&
      !_dropRateEntered &&
      _mastery.text.isEmpty &&
      _dropRate.text.isEmpty;

  void _reportValidityAfterBuild() {
    final valid = _validDraft != null;
    if (_lastValidity == valid) return;
    _lastValidity = valid;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _lastValidity == valid) {
        widget.onStatsValidityChanged?.call(valid);
      }
    });
  }

  @override
  void dispose() {
    _mastery.dispose();
    _dropRate.dispose();
    _energy.dispose();
    _energyRecovery.dispose();
    _advanced.dispose();
    super.dispose();
  }

  void _numberChanged(TextEditingController controller) {
    if (!mounted) return;
    setState(() {
      _validationMessage = null;
      if (controller == _mastery) _masteryEntered = true;
      if (controller == _dropRate) _dropRateEntered = true;
    });
    _previewDraft();
  }

  void _updateDraft(VoidCallback update) {
    setState(() {
      update();
      _validationMessage = null;
    });
    _previewDraft();
  }

  void _previewDraft() {
    final draft = _validDraft;
    if (!widget.inline) {
      if (draft != null) widget.onPreview?.call(draft);
      return;
    }
    final valid = draft != null;
    _lastValidity = valid;
    widget.onStatsValidityChanged?.call(valid);
    if (draft != null) {
      _lastEmitted = draft;
      widget.onStatsChanged?.call(
        draft,
        widget.statsConfirmed || (_masteryEntered && _dropRateEntered),
      );
    }
  }

  BairogCalculatorSettings? get _validDraft {
    final mastery = _untouchedOptional
        ? widget.initial.mastery
        : int.tryParse(_mastery.text.trim());
    final dropRate = _untouchedOptional
        ? widget.initial.gatheringDropRatePercent
        : _double(_dropRate.text);
    final energy = _double(_energy.text);
    final recovery = _double(_energyRecovery.text);
    if (mastery == null ||
        mastery < 0 ||
        mastery > 3000 ||
        dropRate == null ||
        dropRate < 0 ||
        energy == null ||
        energy < 0 ||
        recovery == null ||
        recovery < 0) {
      return null;
    }
    return widget.initial.copyWith(
      mastery: mastery,
      gatheringDropRatePercent: dropRate,
      minigameMode: _minigame,
      hedgehogTier: _hedgehog,
      agrisEnabled: _agris,
      enabledExpenseItemIds: Set<int>.unmodifiable(_expenses),
      yourEnergy: energy,
      naturalEnergyRecoveryPerThreeMinutes: recovery,
      includeAfuaru: _afuaru,
      includeChest: _chest,
      includeChestX10: _chestX10,
      includeFeverTime: _fever,
      includeEvergreenShard: _evergreenShard,
      showTaxed: _afterTax,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.inline) return _inlineEditor();
    final viewport = MediaQuery.sizeOf(context);
    final maxHeight = (viewport.height - 32).clamp(0.0, 900.0);
    return Dialog(
      key: const ValueKey('gathering-setup-dialog'),
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        key: const ValueKey('gathering-setup-frame'),
        constraints: BoxConstraints(maxWidth: 720, maxHeight: maxHeight),
        child: GlassSurface(
          elevated: true,
          reading: true,
          radius: 18,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _dialogHeader(),
              Divider(height: 1, color: context.glass.strongLine),
              Flexible(
                child: SingleChildScrollView(
                  key: const ValueKey('gathering-setup-scroll'),
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
                  child: Column(
                    key: const ValueKey('gathering-setup-single-column'),
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _setupSection(),
                      const SizedBox(height: 18),
                      _advancedOptions(),
                    ],
                  ),
                ),
              ),
              Divider(height: 1, color: context.glass.strongLine),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_validationMessage case final message?)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 7),
                        child: Text(
                          message,
                          style: const TextStyle(
                            color: Color(0xFFFFB4A3),
                            fontSize: 13,
                          ),
                        ),
                      ),
                    Wrap(
                      alignment: WrapAlignment.end,
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Cancel'),
                        ),
                        FilledButton(
                          key: const ValueKey('apply-gathering-setup'),
                          onPressed: _apply,
                          child: const Text('Save stats'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _inlineEditor() => Column(
    key: const ValueKey('inline-stats-editor'),
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          Flexible(
            child: Text(
              'Your stats',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontSize: 21),
            ),
          ),
          IconButton(
            key: const ValueKey('inline-stats-info'),
            tooltip: 'About base stats',
            onPressed: () => showDialog<void>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Base stats'),
                scrollable: true,
                content: const Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Include your gear, artifacts and crystals.'),
                    SizedBox(height: 10),
                    Text(
                      'Leave out the buffs selected in Prepare. They are added automatically.',
                    ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Close'),
                  ),
                ],
              ),
            ),
            icon: const Icon(Icons.info_outline, size: 17, color: muted),
          ),
          if (_validDraft == null)
            IconButton(
              key: const ValueKey('inline-stats-reset'),
              tooltip: 'Discard unfinished stat changes',
              onPressed: widget.enabled
                  ? () {
                      setState(_resetFields);
                      _lastValidity = true;
                      widget.onStatsValidityChanged?.call(true);
                    }
                  : null,
              icon: const Icon(Icons.undo, size: 18),
            ),
        ],
      ),
      const SizedBox(height: 4),
      _setupSection(),
      if (widget.statsConfirmed && _validDraft != null) ...[
        const SizedBox(height: 10),
        Wrap(
          spacing: 16,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const Text(
              'With selected buffs',
              style: TextStyle(fontSize: 13, color: muted),
            ),
            ValueChangePulse(
              value: widget.effectiveSettings!.mastery,
              child: Text(
                '${countText(widget.effectiveSettings!.mastery)} Mastery',
                key: const ValueKey('preparation-effective-mastery'),
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontSize: 16, color: accent),
              ),
            ),
            ValueChangePulse(
              value: widget.effectiveSettings!.gatheringDropRatePercent,
              child: Text(
                '${numberText(widget.effectiveSettings!.gatheringDropRatePercent)}% Drop rate',
                key: const ValueKey('preparation-effective-drop-rate'),
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontSize: 16, color: accent),
              ),
            ),
          ],
        ),
      ],
      const SizedBox(height: 6),
      _advancedOptions(),
    ],
  );

  Widget _dialogHeader() => Padding(
    padding: const EdgeInsets.fromLTRB(24, 20, 16, 18),
    child: Row(
      children: [
        const GameIcon('assets/icons/items/735353.webp', size: 42, grade: 3),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            'Your stats',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
        ),
        IconButton(
          onPressed: () => Navigator.pop(context),
          tooltip: 'Close',
          icon: const Icon(Icons.close, size: 21),
        ),
      ],
    ),
  );

  Widget _setupSection() => Column(
    key: const ValueKey('gathering-setup-inputs'),
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (!widget.inline)
        const Text(
          'Include your gear, artifacts and crystals.\nLeave out the buffs selected in Prepare.',
          key: ValueKey('gathering-base-stats-note'),
          style: TextStyle(fontSize: 14, color: muted, height: 1.45),
        ),
      if (!widget.inline) const SizedBox(height: 20),
      _compactFields(
        children: [
          _numberField(
            key: widget.inline
                ? 'inline-stats-mastery'
                : 'gathering-setup-mastery',
            controller: _mastery,
            label: 'Base mastery',
            hint: widget.inline && !widget.statsConfirmed
                ? 'Example: ${widget.initial.mastery}'
                : '0–3000',
            integer: true,
          ),
          _numberField(
            key: widget.inline
                ? 'inline-stats-drop-rate'
                : 'gathering-setup-gdr',
            controller: _dropRate,
            label: 'Base drop rate %',
            help: _dropRateHelpButton(),
            hint: widget.inline && !widget.statsConfirmed
                ? 'Example: ${_plainNumber(widget.initial.gatheringDropRatePercent)}'
                : '0',
          ),
        ],
      ),
    ],
  );

  Widget _advancedOptions() => Theme(
    data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
    child: KeyedSubtree(
      key: _advancedKey,
      child: ExpansionTile(
        key: ValueKey(
          widget.inline ? 'inline-stats-advanced' : 'gathering-stats-advanced',
        ),
        controller: _advanced,
        expansionAnimationStyle: AnimationStyle(
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
        ),
        onExpansionChanged: widget.onAdvancedExpandedChanged,
        expandedAlignment: Alignment.centerLeft,
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(top: 16, bottom: 10),
        title: Text(
          'Advanced options',
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(fontSize: 14.5, color: muted),
        ),
        children: [
          Wrap(
            spacing: 24,
            runSpacing: 20,
            children: [
              _optionGroup('Gathering minigame', [
                _choice(
                  key: 'minigame-none',
                  label: 'Off',
                  selected: _minigame == BairogMinigameMode.none,
                  onTap: () =>
                      _updateDraft(() => _minigame = BairogMinigameMode.none),
                ),
                _choice(
                  key: 'minigame-normal',
                  label: 'Normal · 5%',
                  selected: _minigame == BairogMinigameMode.normal,
                  onTap: () =>
                      _updateDraft(() => _minigame = BairogMinigameMode.normal),
                ),
                _choice(
                  key: 'minigame-event',
                  label: 'Event · 10%',
                  selected: _minigame == BairogMinigameMode.event,
                  onTap: () =>
                      _updateDraft(() => _minigame = BairogMinigameMode.event),
                ),
              ]),
              _optionGroup('Extra-gather pet tier', [
                for (final tier in BairogHedgehogTier.values)
                  _choice(
                    key: 'hedgehog-${tier.storageValue}',
                    label: tier == BairogHedgehogTier.none
                        ? 'None'
                        : 'T${tier.storageValue}',
                    selected: _hedgehog == tier,
                    onTap: () => _updateDraft(() => _hedgehog = tier),
                  ),
              ]),
            ],
          ),
          const SizedBox(height: 24),
          _lootOptionsSection(),
          const SizedBox(height: 24),
          _energyRecoverySection(),
        ],
      ),
    ),
  );

  Widget _lootOptionsSection() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _sectionHeader('LOOT OPTIONS'),
      const SizedBox(height: 10),
      Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          _toggle(
            key: 'agris',
            label: 'Agris',
            help: 'Uses Agris Fever points to increase the main material.',
            selected: _agris,
            assign: (value) => _agris = value,
          ),
          _toggle(
            key: 'afuaru',
            label: 'Afuaru',
            help:
                'Rare goblin that can appear while lumbering or gathering sap. Adds his average loot.',
            selected: _afuaru,
            assign: (value) => _afuaru = value,
          ),
          _toggle(
            key: 'treasure-chests',
            label: 'Treasure chests',
            help:
                'Buried Trace chests found while gathering. Adds average rewards and deducts one Gold Key per chest.',
            selected: _chest,
            assign: (value) => _chest = value,
          ),
          _toggle(
            key: 'minigame-chest',
            label: '10× minigame chest',
            help:
                'Adds the average value of rare chest procs during 10× minigames. They are not guaranteed.',
            selected: _chestX10,
            assign: (value) => _chestX10 = value,
          ),
          _toggle(
            key: 'fever-time',
            label: 'Fever Time',
            help:
                'Automatic weekend gathering bonus. You don\'t activate it yourself. Turn this on during Fever Time to include the extra Sharp Shard chance.',
            selected: _fever,
            assign: (value) => _fever = value,
          ),
          _toggle(
            key: 'evergreen-shard',
            label: 'Evergreen Shard',
            help:
                'Rare gathering drop that replaced the old WON Life EXP Crystal. Adds its average value.',
            selected: _evergreenShard,
            assign: (value) => _evergreenShard = value,
          ),
          _toggle(
            key: 'marketplace-tax',
            label: 'After Marketplace tax',
            help: 'Uses the 84.5% Central Market payout.',
            selected: _afterTax,
            assign: (value) => _afterTax = value,
          ),
        ],
      ),
      const SizedBox(height: 10),
      const Text(
        'Rare drops use long-term averages. Your actual hour can be higher or lower.',
        key: ValueKey('loot-options-average-note'),
        style: TextStyle(fontSize: 12.5, color: muted, height: 1.4),
      ),
    ],
  );

  Widget _energyRecoverySection() => Column(
    key: const ValueKey('gathering-setup-energy-recovery-section'),
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _sectionHeader('ENERGY RECOVERY'),
      const SizedBox(height: 10),
      const Text(
        'Energy use assumes Gathering Professional 3+.',
        style: TextStyle(fontSize: 13, color: muted, height: 1.4),
      ),
      const SizedBox(height: 16),
      _compactFields(
        children: [
          _numberField(
            key: 'gathering-setup-energy',
            controller: _energy,
            label: 'Starting Energy',
            hint: '500',
          ),
          _numberField(
            key: 'gathering-setup-energy-recovery',
            controller: _energyRecovery,
            label: 'Recovery / 3 min',
            hint: '3',
          ),
        ],
      ),
      const SizedBox(height: 14),
      _compactTiles(
        key: const ValueKey('gathering-setup-energy-expenses-grid'),
        children: [
          for (final expense in bairogEnergyExpenses) _expenseToggle(expense),
        ],
      ),
    ],
  );

  Widget _sectionHeader(String label) => Row(
    children: [
      Flexible(
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.2,
            color: accent,
          ),
        ),
      ),
      const SizedBox(width: 12),
      Expanded(child: Divider(height: 1, color: context.glass.insetLine)),
    ],
  );

  Widget _compactFields({required List<Widget> children}) => LayoutBuilder(
    builder: (context, constraints) {
      final scale = MediaQuery.textScalerOf(context).scale(1);
      final width = (245 * scale).clamp(0.0, constraints.maxWidth);
      return Wrap(
        spacing: 16,
        runSpacing: 18,
        children: [
          for (final child in children) SizedBox(width: width, child: child),
        ],
      );
    },
  );

  Widget _optionGroup(String label, List<Widget> children) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _fieldLabel(label),
      const SizedBox(height: 10),
      Wrap(spacing: 8, runSpacing: 8, children: children),
    ],
  );

  Widget _compactTiles({Key? key, required List<Widget> children}) =>
      LayoutBuilder(
        builder: (context, constraints) {
          final scale = MediaQuery.textScalerOf(context).scale(1);
          final twoColumns = constraints.maxWidth >= 680 * scale;
          const gap = 8.0;
          final width = twoColumns
              ? (constraints.maxWidth - gap) / 2
              : (540 * scale).clamp(0.0, constraints.maxWidth);
          return Wrap(
            key: key,
            spacing: gap,
            runSpacing: gap,
            children: [
              for (final child in children)
                SizedBox(width: width, child: child),
            ],
          );
        },
      );

  Widget _numberField({
    required String key,
    required TextEditingController controller,
    required String label,
    required String hint,
    bool integer = false,
    Widget? help,
  }) => TextField(
    key: ValueKey(key),
    controller: controller,
    enabled: widget.enabled,
    onChanged: (_) => _numberChanged(controller),
    keyboardType: TextInputType.numberWithOptions(decimal: !integer),
    inputFormatters: widget.inline
        ? null
        : [
            FilteringTextInputFormatter.allow(
              integer ? RegExp(r'[0-9]') : RegExp(r'[0-9.,]'),
            ),
          ],
    style: Theme.of(context).textTheme.titleMedium?.copyWith(
      fontSize: 18,
      fontWeight: FontWeight.w600,
    ),
    decoration: InputDecoration(
      labelText: label,
      hintText: hint,
      suffixIcon: help,
      labelStyle: Theme.of(
        context,
      ).textTheme.bodyMedium?.copyWith(fontSize: 14, color: muted),
      floatingLabelStyle: Theme.of(
        context,
      ).textTheme.bodyMedium?.copyWith(fontSize: 14, color: muted),
      hintStyle: Theme.of(
        context,
      ).textTheme.bodyMedium?.copyWith(fontSize: 14, color: muted),
      errorText: widget.inline ? _fieldError(controller) : null,
      errorMaxLines: 2,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
    ),
  );

  Widget _dropRateHelpButton() => Tooltip(
    key: const ValueKey('gathering-drop-rate-help-hover'),
    message:
        'Use “Additional Drop Rate (excluding Mastery)”.\n\n'
        'Leave out bonuses selected in Prepare.',
    constraints: const BoxConstraints(maxWidth: 340),
    textAlign: TextAlign.left,
    child: IconButton(
      key: const ValueKey('gathering-drop-rate-help'),
      visualDensity: VisualDensity.compact,
      onPressed: () => showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          key: const ValueKey('gathering-drop-rate-help-dialog'),
          title: const Text('Gathering Drop Rate'),
          scrollable: true,
          content: const Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Open Gathering details for your tool.'),
              SizedBox(height: 12),
              Text(
                'Use “Additional Drop Rate (excluding Mastery)”, not “Basic Resource Drop Rate”.',
              ),
              SizedBox(height: 12),
              Text(
                'Subtract bonuses already active in-game if you also select them in Prepare. Prepare adds them back.',
              ),
              SizedBox(height: 12),
              Text('52% with a selected +10% bonus: enter 42%.'),
              SizedBox(height: 12),
              Text('Gathering level is already reflected in Mastery.'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
      icon: const Icon(Icons.info_outline_rounded, size: 18, color: muted),
    ),
  );

  Widget _fieldLabel(String label) => Text(
    label,
    style: const TextStyle(
      fontSize: 14,
      color: ink,
      fontWeight: FontWeight.w600,
    ),
  );

  Widget _choice({
    required String key,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) => GlassControl(
    key: ValueKey(key),
    selected: selected,
    radius: 10,
    child: InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: widget.enabled ? onTap : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
            color: ink,
          ),
        ),
      ),
    ),
  );

  Widget _toggle({
    required String key,
    required String label,
    required String help,
    required bool selected,
    required ValueChanged<bool> assign,
  }) => Tooltip(
    message: help,
    waitDuration: const Duration(milliseconds: 350),
    excludeFromSemantics: true,
    child: Semantics(
      key: ValueKey('loot-option-semantics-$key'),
      hint: help,
      toggled: selected,
      child: GlassControl(
        selected: selected,
        radius: 8,
        child: FilterChip(
          key: ValueKey('loot-option-$key'),
          labelStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: ink,
          ),
          label: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(child: Text(label)),
              const SizedBox(width: 4),
              const ExcludeSemantics(
                child: Icon(Icons.info_outline, size: 13, color: muted),
              ),
            ],
          ),
          selected: selected,
          color: const WidgetStatePropertyAll(Colors.transparent),
          showCheckmark: true,
          onSelected: widget.enabled
              ? (value) => _updateDraft(() => assign(value))
              : null,
          visualDensity: VisualDensity.compact,
          side: BorderSide.none,
        ),
      ),
    ),
  );

  Widget _expenseToggle(BairogEnergyExpense expense) {
    final selected = _expenses.contains(expense.bdoItemId);
    final buff = widget.catalog.buffs
        .where((entry) => entry.id == 'buff-${expense.bdoItemId}')
        .firstOrNull;
    final icon = buff?.icon ?? '';
    return GlassControl(
      selected: selected,
      radius: 9,
      child: InkWell(
        borderRadius: BorderRadius.circular(9),
        onTap: widget.enabled
            ? () => _updateDraft(() {
                selected
                    ? _expenses.remove(expense.bdoItemId)
                    : _expenses.add(expense.bdoItemId);
              })
            : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          child: Row(
            children: [
              GameIcon(icon, size: 36, grade: buff?.grade),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      expense.name,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      expense.usesPerHour != null
                          ? '${_plainNumber(expense.usesPerHour!)} uses/hour'
                          : '${_plainNumber(expense.durationHours!)} hour duration',
                      style: const TextStyle(fontSize: 12.5, color: muted),
                    ),
                  ],
                ),
              ),
              if (buff != null)
                IconButton(
                  key: ValueKey('energy-expense-info-${buff.id}'),
                  onPressed: () => showBuffInfo(context, widget.catalog, buff),
                  tooltip: 'About ${buff.name}',
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints(
                    minWidth: 34,
                    minHeight: 34,
                  ),
                  icon: const Icon(Icons.info_outline, size: 17, color: muted),
                ),
              Checkbox(
                value: selected,
                visualDensity: VisualDensity.compact,
                onChanged: widget.enabled
                    ? (value) => _updateDraft(() {
                        value == true
                            ? _expenses.add(expense.bdoItemId)
                            : _expenses.remove(expense.bdoItemId);
                      })
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _apply() {
    final mastery = int.tryParse(_mastery.text.trim());
    final dropRate = _double(_dropRate.text);
    final energy = _double(_energy.text);
    final recovery = _double(_energyRecovery.text);
    if (mastery == null || mastery < 0 || mastery > 3000) {
      setState(
        () => _validationMessage = 'Mastery must be between 0 and 3,000.',
      );
      return;
    }
    if (dropRate == null || dropRate < 0) {
      setState(
        () => _validationMessage =
            'Gathering Item Drop Rate must be zero or higher.',
      );
      return;
    }
    if (energy == null || energy < 0 || recovery == null || recovery < 0) {
      setState(
        () => _validationMessage = 'Energy values must be zero or higher.',
      );
      return;
    }
    Navigator.pop(context, _validDraft!);
  }

  String? _fieldError(TextEditingController controller) {
    if (_untouchedOptional &&
        (controller == _mastery || controller == _dropRate)) {
      return null;
    }
    if (controller == _mastery) {
      final value = int.tryParse(controller.text.trim());
      return value == null || value < 0 || value > 3000
          ? 'Enter a whole number from 0 to 3,000.'
          : null;
    }
    final value = _double(controller.text);
    return value == null || value < 0
        ? 'Enter zero or a positive number.'
        : null;
  }

  static double? _double(String value) {
    final parsed = double.tryParse(value.trim().replaceAll(',', '.'));
    return parsed != null && parsed.isFinite ? parsed : null;
  }

  static String _plainNumber(num value) =>
      value.toString().replaceFirst(RegExp(r'\.0$'), '');
}
