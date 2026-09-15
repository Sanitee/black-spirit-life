import 'package:flutter/material.dart';

import '../domain/bairog_calculator.dart';
import '../domain/models.dart';
import '../domain/pets.dart';
import 'buff_picker.dart';
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
        Text(
          title,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        if (description != null) ...[
          const SizedBox(height: 4),
          Text(description, style: const TextStyle(fontSize: 13, color: muted)),
        ],
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
      const Text(
        'Artifact options',
        style: TextStyle(fontSize: 14, color: muted),
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
      child: GlassSurface(
        key: const ValueKey('preparation-stats'),
        radius: 18,
        gradient: context.glass.groupGradient,
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
      Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 18,
        runSpacing: 3,
        children: [
          Text(
            text,
            style: prominent
                ? Theme.of(context).textTheme.headlineSmall
                : Theme.of(context).textTheme.titleLarge,
          ),
          ?action,
        ],
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
        child: GlassControl(
          key: ValueKey('preparation-$group-${buff.id}'),
          selected: selected,
          radius: 13,
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
                      color: selected ? accent : muted,
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
                    icon: const Icon(
                      Icons.info_outline,
                      size: 18,
                      color: muted,
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
                const Icon(Icons.info_outline, size: 16, color: muted),
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
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: accent,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Choose one pair; these are alternatives.',
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 8),
            const Text(
              'Reference only. Include your artifact bonuses in your base stats.',
              style: TextStyle(fontSize: 13, color: muted),
            ),
          ],
        ),
      ),
    ),
  );
}
