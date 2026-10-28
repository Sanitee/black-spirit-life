import 'package:flutter/material.dart';

import '../domain/bairog_calculator.dart';
import '../domain/models.dart';
import '../domain/pets.dart';
import 'buff_picker.dart';
import 'field_desk_materials.dart';
import 'gathering_crystal_recommendation.dart';
import 'gathering_setup_dialog.dart';
import 'hover_pinned_details.dart';
import 'matchlock_damage_advice.dart';
import 'pet_recommendations.dart';
import 'theme.dart';

/// Preparation controls share the host's profile; only disclosure is local.
class GatheringPreparationPanel extends StatefulWidget {
  const GatheringPreparationPanel({
    super.key,
    required this.catalog,
    required this.methodId,
    required this.spotId,
    required this.selectedBuffIds,
    required this.selectedPetIds,
    required this.pets,
    required this.baseSettings,
    required this.effectiveSettings,
    required this.statsConfirmed,
    required this.onToggleBuff,
    required this.onTogglePet,
    required this.onPreset,
    required this.onClearBuffs,
    required this.onClearPets,
    required this.onStatsChanged,
    required this.onStatsValidityChanged,
    this.statsEnabled = true,
    this.statsContextId,
    this.compactRecommendations = false,
    this.onEditStats,
  });

  final Catalog catalog;
  final String methodId;
  final String? spotId;
  final Set<String> selectedBuffIds, selectedPetIds;
  final List<PetRecommendation> pets;
  final BairogCalculatorSettings baseSettings, effectiveSettings;
  final bool statsConfirmed;
  final ValueChanged<Buff> onToggleBuff;
  final ValueChanged<PetRecommendation> onTogglePet;
  final ValueChanged<Map<String, dynamic>> onPreset;
  final VoidCallback onClearBuffs, onClearPets;
  final void Function(BairogCalculatorSettings, bool) onStatsChanged;
  final ValueChanged<bool> onStatsValidityChanged;
  final bool statsEnabled;
  final Object? statsContextId;

  /// Hosted field desk: recommendations in a popup, with stats in the rail.
  final bool compactRecommendations;
  final VoidCallback? onEditStats;

  @override
  State<GatheringPreparationPanel> createState() =>
      _GatheringPreparationPanelState();
}

class _GatheringPreparationPanelState extends State<GatheringPreparationPanel> {
  bool _allBuffs = false;
  int _advancedRequest = 0;
  bool _statsAdvanced = false;
  final _libraryAnchor = GlobalKey();
  bool _revealLibraryPending = false;

  Method get _method => widget.catalog.methods.firstWhere(
    (method) => method.id == widget.methodId,
    orElse: () => widget.catalog.methods.first,
  );

  Map<String, dynamic>? get _starter => widget.catalog.presets
      .where(
        (preset) =>
            preset['id'] ==
            switch (widget.methodId) {
              'sniper' => 'sniper-simple',
              'hunting' => 'hunting-simple',
              _ => 'gathering-simple',
            },
      )
      .firstOrNull;

  List<Buff> _buffs(Iterable<String> ids) => widget.catalog.buffs
      .where((buff) => ids.contains(buff.id))
      .toList(growable: false);

  @override
  Widget build(BuildContext context) {
    if (widget.compactRecommendations) return _compactRecommendations();
    final starter = _starter;
    final kit = _buffs(strings(starter?['buffIds']));
    final gathering = _method.activity == 'gathering';
    final foods = _buffs(const ['buff-9691', 'buff-9301', 'buff-9216']);
    final dropRate = _buffs(const [
      'buff-1159',
      'buff-721092',
      'buff-45302',
      'buff-45514',
    ]);
    final energy = _buffs(const ['buff-820150', 'buff-821144', 'buff-821145']);
    final instantEnergy = _buffs(const [
      'buff-589',
      'buff-17503',
      'buff-17325',
    ]);
    final groupedIds = {...foods, ...dropRate}.map((buff) => buff.id).toSet();
    final otherKit = kit
        .where((buff) => !groupedIds.contains(buff.id))
        .toList();
    final lightstones = widget.catalog.buffs
        .where(
          (buff) =>
              buff.category == 'lightstones' &&
              buff.recommendedFor.contains(_method.activity),
        )
        .toList(growable: false);
    final featuredIds = {
      ...kit.map((buff) => buff.id),
      ...lightstones.map((buff) => buff.id),
      if (gathering) ...[
        ...groupedIds,
        ...energy.map((buff) => buff.id),
        ...instantEnergy.map((buff) => buff.id),
      ],
    };
    final extras = _buffs(widget.selectedBuffIds.difference(featuredIds));
    return Column(
      key: const ValueKey('gathering-preparation-panel'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _stats(context),
        const SizedBox(height: 26),
        Column(
          key: const ValueKey('preparation-kit-section'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _heading(
              'Recommended Items',
              prominent: true,
              action: starter == null
                  ? null
                  : TextButton.icon(
                      key: const ValueKey('preparation-use-kit'),
                      onPressed: () => widget.onPreset(starter),
                      icon: const Icon(Icons.done_all_rounded, size: 18),
                      label: const Text('Use basic kit'),
                    ),
            ),
            const SizedBox(height: 12),
            if (gathering) ...[
              _recommendationGroup(
                'Food · choose one',
                foods,
                description: 'Seafood Cron Meal and Fig Pie do not stack.',
              ),
              _recommendationGroup(
                'Gathering drop rate',
                dropRate,
                description:
                    'Choose one alchemy stone. Labor elixir replaces Verdure Draught.',
              ),
              _recommendationGroup('Other items', otherKit),
            ] else
              _choices(kit, group: 'kit'),
            if (extras.isNotEmpty) ...[
              const SizedBox(height: 22),
              _heading('Also selected'),
              const SizedBox(height: 10),
              _choices(extras, group: 'selected'),
            ],
            if (lightstones.isNotEmpty) ...[
              const SizedBox(height: 24),
              _heading('Lightstone set'),
              const SizedBox(height: 10),
              _choices(lightstones, group: 'lightstones'),
            ],
            if (_method.activity == 'gathering') ...[
              const SizedBox(height: 20),
              Container(
                key: const ValueKey('preparation-gear-reference'),
                padding: const EdgeInsets.only(left: 14),
                decoration: BoxDecoration(
                  border: Border(
                    left: BorderSide(color: context.glass.strongLine, width: 2),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const GatheringCrystalRecommendation(),
                    const SizedBox(height: 10),
                    _artifactOptions(),
                  ],
                ),
              ),
            ],
            if (widget.methodId == 'hunting') ...[
              const SizedBox(height: 22),
              const MatchlockDamageAdvice(),
            ],
            const SizedBox(height: 18),
            PetRecommendations(
              methodId: widget.methodId,
              spotId: widget.spotId,
              pets: widget.pets,
              selectedIds: widget.selectedPetIds,
              onToggle: widget.onTogglePet,
              onClear: widget.onClearPets,
              framed: false,
            ),
            if (widget.baseSettings.hedgehogTier != BairogHedgehogTier.none)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  key: const ValueKey('preparation-pet-tier'),
                  onPressed: () => setState(() => _advancedRequest++),
                  child: Text(
                    'Extra-gather pet: T${widget.baseSettings.hedgehogTier.storageValue}',
                  ),
                ),
              ),
          ],
        ),
        if (gathering) ...[
          const SizedBox(height: 24),
          Column(
            key: const ValueKey('preparation-energy-section'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _heading('Energy recovery', prominent: true),
              const SizedBox(height: 12),
              _recommendationGroup(
                'Recovery over time',
                energy,
                group: 'energy',
                description: 'Mystical and Mellow are alternatives.',
              ),
              _recommendationGroup(
                'Energy potions',
                instantEnergy,
                group: 'instant-energy',
                description:
                    'Reference only. Potions and tonics restore a fixed amount, not regeneration.',
              ),
            ],
          ),
        ],
        const SizedBox(height: 20),
        _libraryReveal(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                key: _libraryAnchor,
                alignment: Alignment.centerLeft,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: 230 * MediaQuery.textScalerOf(context).scale(1),
                  ),
                  child: GlassControl(
                    selected: _allBuffs,
                    radius: 12,
                    child: ListTile(
                      key: const ValueKey('preparation-all-buffs-toggle'),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                      ),
                      title: Text(
                        'All buffs',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      trailing: Icon(
                        _allBuffs ? Icons.expand_less : Icons.expand_more,
                      ),
                      onTap: _toggleLibrary,
                    ),
                  ),
                ),
              ),
              if (_allBuffs)
                Padding(
                  key: const ValueKey('preparation-all-buffs'),
                  padding: const EdgeInsets.only(top: 18, bottom: 12),
                  child: BuffPicker(
                    catalog: widget.catalog,
                    activity: _method.activity,
                    methodId: widget.methodId,
                    spotId: widget.spotId,
                    selected: widget.selectedBuffIds,
                    // Pets already have one dedicated chooser above.
                    pets: const [],
                    onToggle: widget.onToggleBuff,
                    onPreset: widget.onPreset,
                    onClear: widget.onClearBuffs,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _compactRecommendations() {
    final starter = _starter;
    final kit = _buffs(strings(starter?['buffIds']));
    final kitIds = kit.map((buff) => buff.id).toSet();
    final extras = _buffs(widget.selectedBuffIds.difference(kitIds));
    final gathering = _method.activity == 'gathering';
    return Column(
      key: const ValueKey('gathering-compact-recommendations'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _heading(
          'Basic kit',
          action: starter == null
              ? null
              : TextButton(
                  key: const ValueKey('preparation-use-kit'),
                  onPressed: () => widget.onPreset(starter),
                  child: const Text('Select kit'),
                ),
        ),
        for (final buff in kit) _compactBuff(buff, 'kit'),
        if (extras.isNotEmpty)
          ExpansionTile(
            key: const ValueKey('recommendations-also-selected'),
            tilePadding: EdgeInsets.zero,
            title: Text('Also selected (${extras.length})'),
            children: [
              for (final buff in extras) _compactBuff(buff, 'selected'),
            ],
          ),
        ExpansionTile(
          key: const ValueKey('recommendations-library'),
          tilePadding: EdgeInsets.zero,
          title: const Text('Other buffs & alternatives'),
          children: [
            BuffPicker(
              catalog: widget.catalog,
              activity: _method.activity,
              methodId: widget.methodId,
              spotId: widget.spotId,
              selected: widget.selectedBuffIds,
              pets: const [],
              onToggle: widget.onToggleBuff,
              onPreset: widget.onPreset,
              onClear: widget.onClearBuffs,
            ),
          ],
        ),
        ExpansionTile(
          key: const ValueKey('recommendations-gear'),
          tilePadding: EdgeInsets.zero,
          title: const Text('Pets, crystals & gear'),
          children: [
            if (gathering) ...[
              const GatheringCrystalRecommendation(),
              const SizedBox(height: 12),
              _artifactOptions(),
              const SizedBox(height: 12),
            ],
            if (widget.methodId == 'hunting') const MatchlockDamageAdvice(),
            PetRecommendations(
              methodId: widget.methodId,
              spotId: widget.spotId,
              pets: widget.pets,
              selectedIds: widget.selectedPetIds,
              onToggle: widget.onTogglePet,
              onClear: widget.onClearPets,
              framed: false,
            ),
            if (widget.baseSettings.hedgehogTier != BairogHedgehogTier.none &&
                widget.onEditStats != null)
              TextButton(
                key: const ValueKey('preparation-pet-tier'),
                onPressed: widget.onEditStats,
                child: Text(
                  'Extra-gather pet: T${widget.baseSettings.hedgehogTier.storageValue}',
                ),
              ),
          ],
        ),
        if (gathering && widget.statsConfirmed)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              'With selected buffs · ${numberText(widget.effectiveSettings.mastery)} mastery'
              ' · ${numberText(widget.effectiveSettings.gatheringDropRatePercent)}% drop rate',
              key: const ValueKey('recommendations-effective-stats'),
              style: TextStyle(
                fontSize: 13,
                color: context.gatheringColors.muted,
              ),
            ),
          ),
      ],
    );
  }

  Widget _compactBuff(Buff buff, String group) {
    final selected =
        !buff.referenceOnly && widget.selectedBuffIds.contains(buff.id);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          BuffHoverDetails(
            catalog: widget.catalog,
            buff: buff,
            targetBuilder: (context, pin) => InkWell(
              onTap: pin,
              borderRadius: BorderRadius.circular(5),
              child: GameIcon(
                buff.icon,
                size: 40,
                grade: buff.grade,
                recessed: true,
              ),
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: InkWell(
              key: ValueKey('recommendation-$group-${buff.id}'),
              onTap: buff.referenceOnly
                  ? () => showBuffInfo(context, widget.catalog, buff)
                  : () => widget.onToggleBuff(buff),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      buff.name,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    for (final line in _recommendationBenefits(buff))
                      Text(
                        line,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: context.gatheringColors.muted,
                        ),
                      ),
                    if (buff.duration != null)
                      Text(
                        formatDurationMinutes(buff.duration!),
                        style: TextStyle(
                          fontSize: 12,
                          color: context.gatheringColors.muted,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          if (!buff.referenceOnly)
            Checkbox(
              key: ValueKey('recommendation-check-$group-${buff.id}'),
              value: selected,
              onChanged: (_) => widget.onToggleBuff(buff),
              semanticLabel: buff.name,
              visualDensity: VisualDensity.compact,
            ),
        ],
      ),
    );
  }

  List<String> _recommendationBenefits(Buff buff) {
    final summary = compactBuffEffectLines(buff);
    if (summary.isNotEmpty) return summary.take(3).toList(growable: false);
    // Use the existing audited stat names, units and values. Lead with the
    // current activity's useful benefits; the icon retains the full tooltip.
    final priority = switch (widget.methodId) {
      'hunting' => const [
        'lifeMastery',
        'huntingMastery',
        'huntingExpPct',
        'attackSpeed',
        'criticalHit',
        'lifeExpPct',
        'movementSpeed',
        'maxWeight',
      ],
      'sniper' => const [
        'lifeMastery',
        'huntingMastery',
        'gatheringItemDropPct',
        'huntingExpPct',
        'lifeExpPct',
        'gatheringSpeed',
        'movementSpeed',
        'maxWeight',
      ],
      _ => const [
        'lifeMastery',
        'gatheringMastery',
        'gatheringItemDropPct',
        'lifeExpPct',
        'gatheringExpPct',
        'gatheringSpeed',
        'movementSpeed',
        'maxWeight',
      ],
    };
    final ordered = <String>{
      for (final key in priority)
        if (buff.effects.containsKey(key)) key,
      ...buff.effects.keys,
    };
    return [
      for (final key in ordered.take(3))
        '${widget.catalog.statLabel(key)} '
            '${effectText(widget.catalog, key, buff.effects[key]!)}',
    ];
  }

  Widget _libraryReveal({required Widget child}) =>
      MediaQuery.disableAnimationsOf(context)
      ? child
      : AnimatedSize(
          key: const ValueKey('preparation-library-reveal'),
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topLeft,
          onEnd: _revealLibrary,
          child: child,
        );

  void _toggleLibrary() {
    setState(() {
      _allBuffs = !_allBuffs;
      _revealLibraryPending = _allBuffs;
    });
    if (MediaQuery.disableAnimationsOf(context)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _revealLibrary());
    }
  }

  void _revealLibrary() {
    if (!mounted || !_allBuffs || !_revealLibraryPending) return;
    final anchorContext = _libraryAnchor.currentContext;
    if (anchorContext == null) return;
    _revealLibraryPending = false;
    Scrollable.ensureVisible(
      anchorContext,
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 180),
      alignment: 0,
      curve: Curves.easeOutCubic,
    );
  }

  Widget _recommendationGroup(
    String title,
    List<Buff> buffs, {
    String group = 'kit',
    String? description,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Flexible(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (description != null) ...[
              const SizedBox(width: 7),
              Tooltip(
                message: description,
                triggerMode: TooltipTriggerMode.tap,
                child: Icon(
                  Icons.info_outline,
                  size: 17,
                  color: context.gatheringColors.muted,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 10),
        _choices(buffs, group: group),
      ],
    ),
  );

  Widget _artifactOptions() => Wrap(
    key: const ValueKey('preparation-artifact-options'),
    spacing: 8,
    runSpacing: 6,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      Text(
        'Artifact options',
        style: TextStyle(fontSize: 14, color: context.gatheringColors.muted),
      ),
      for (final artifact in const [
        (
          id: '735353',
          title: '2× Gathering Item Drop Rate',
          effect: '+4% Gathering Item Drop Rate',
        ),
        (
          id: '735367',
          title: '2× Gathering Mastery',
          effect: '+20 Gathering Mastery',
        ),
      ])
        _ArtifactReference(
          id: artifact.id,
          title: artifact.title,
          effect: artifact.effect,
        ),
    ],
  );

  Widget _stats(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: _statsAdvanced ? 900 : 600),
      child: FieldDeskPanel(
        key: const ValueKey('preparation-stats'),
        radius: 12,
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
        child: GatheringInlineStats(
          catalog: widget.catalog,
          baseSettings: widget.baseSettings,
          effectiveSettings: widget.effectiveSettings,
          statsConfirmed: widget.statsConfirmed,
          onStatsChanged: widget.onStatsChanged,
          onStatsValidityChanged: widget.onStatsValidityChanged,
          enabled: widget.statsEnabled,
          contextId: widget.statsContextId,
          advancedRequest: _advancedRequest,
          onAdvancedExpandedChanged: (value) =>
              setState(() => _statsAdvanced = value),
        ),
      ),
    ),
  );

  Widget _heading(String text, {Widget? action, bool prominent = false}) =>
      FieldDeskSectionHeading(
        title: text,
        action: action,
        prominent: prominent,
      );

  Widget _choices(List<Buff> buffs, {required String group}) => LayoutBuilder(
    builder: (context, constraints) {
      final scale = MediaQuery.textScalerOf(context).scale(1);
      final columns = (constraints.maxWidth / (300 * scale)).floor().clamp(
        1,
        3,
      );
      final width = ((constraints.maxWidth - (columns - 1) * 10) / columns)
          .clamp(0.0, 360 * scale);
      return Wrap(
        key: ValueKey('preparation-$group'),
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final buff in buffs)
            SizedBox(width: width, child: _buffChoice(buff, group)),
        ],
      );
    },
  );

  Widget _buffChoice(Buff buff, String group) {
    final selected =
        !buff.referenceOnly && widget.selectedBuffIds.contains(buff.id);
    return BuffHoverDetails(
      catalog: widget.catalog,
      buff: buff,
      targetBuilder: (context, pin) => Semantics(
        label: buff.name,
        button: true,
        selected: buff.referenceOnly ? null : selected,
        child: FieldDeskSelection(
          selected: selected,
          child: GlassControl(
            key: ValueKey('preparation-$group-${buff.id}'),
            selected: selected,
            radius: 13,
            leadingWidth: 56,
            trailingWidth: 38,
            child: InkWell(
              borderRadius: BorderRadius.circular(13),
              onTap: buff.referenceOnly ? pin : () => widget.onToggleBuff(buff),
              onLongPress: pin,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 10, 6, 10),
                child: Row(
                  children: [
                    GameIcon(buff.icon, size: 40, grade: buff.grade),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        buff.name,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontSize: 14.5,
                          fontWeight: selected
                              ? FontWeight.w600
                              : FontWeight.w500,
                          height: 1.25,
                        ),
                      ),
                    ),
                    if (!buff.referenceOnly)
                      Icon(
                        selected ? Icons.check_circle : Icons.circle_outlined,
                        size: 18,
                        color: selected
                            ? context.gatheringColors.accent
                            : context.gatheringColors.muted,
                      ),
                    IconButton(
                      key: ValueKey('preparation-info-$group-${buff.id}'),
                      onPressed: pin,
                      tooltip: 'About ${buff.name}',
                      constraints: const BoxConstraints.tightFor(
                        width: 32,
                        height: 34,
                      ),
                      padding: EdgeInsets.zero,
                      icon: Icon(
                        Icons.info_outline,
                        size: 18,
                        color: context.gatheringColors.muted,
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

/// Accepted artifact pair references, not selectable buffs or extra stats.
class _ArtifactReference extends StatelessWidget {
  const _ArtifactReference({
    required this.id,
    required this.title,
    required this.effect,
  });

  final String id, title, effect;
  String get icon => 'assets/icons/items/$id.webp';

  @override
  Widget build(BuildContext context) => HoverPinnedDetails(
    hoverKey: ValueKey('preparation-artifact-hover-$id'),
    cardBuilder: (context) => _details(context),
    onPin: () => showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        key: ValueKey('preparation-artifact-details-$id'),
        insetPadding: const EdgeInsets.all(16),
        child: _details(context, pinned: true),
      ),
    ),
    targetBuilder: (context, pin) => Semantics(
      label: '$title. Reference information.',
      button: true,
      child: GlassControl(
        key: ValueKey('preparation-artifact-$id'),
        radius: 8,
        child: InkWell(
          onTap: pin,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                GameIcon(icon, size: 36, grade: 3),
                const SizedBox(width: 7),
                Flexible(
                  child: Text(title, style: const TextStyle(fontSize: 14)),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.info_outline,
                  size: 16,
                  color: context.gatheringColors.muted,
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  Widget _details(
    BuildContext context, {
    bool pinned = false,
  }) => ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 380),
    child: GlassSurface(
      elevated: true,
      padding: const EdgeInsets.all(16),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                GameIcon(icon, size: 36, grade: 3),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (pinned)
                  IconButton(
                    key: ValueKey('close-preparation-artifact-$id'),
                    tooltip: 'Close',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, size: 20),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              effect,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: context.gatheringColors.accent,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Choose one pair; these are alternatives.',
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 8),
            Text(
              'Reference only. Include your artifact bonuses in your base stats.',
              style: TextStyle(
                fontSize: 13,
                color: context.gatheringColors.muted,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
