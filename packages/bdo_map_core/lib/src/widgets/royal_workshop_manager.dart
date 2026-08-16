import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../royal_workshop/royal_workshop_models.dart';
import 'readable_select_controls.dart';
import 'resource_map_desktop_shell.dart';

class BdoRoyalWorkshopManager extends StatefulWidget {
  const BdoRoyalWorkshopManager({
    super.key,
    required this.plan,
    required this.goods,
    required this.onChanged,
    required this.onOpenYukjoHousing,
    this.onMarkManager,
    this.onClose,
    this.yukjoHiredWorkers = 0,
    this.yukjoLodgingSlots = 1,
  });

  final BdoRoyalWorkshopPlan plan;
  final List<BdoRoyalWorkshopGood> goods;
  final ValueChanged<BdoRoyalWorkshopPlan> onChanged;
  final VoidCallback onOpenYukjoHousing;
  final ValueChanged<BdoRoyalWorkshopArea>? onMarkManager;
  final VoidCallback? onClose;
  final int yukjoHiredWorkers;
  final int yukjoLodgingSlots;

  @override
  State<BdoRoyalWorkshopManager> createState() =>
      _BdoRoyalWorkshopManagerState();
}

class _BdoRoyalWorkshopManagerState extends State<BdoRoyalWorkshopManager> {
  String? _selectedAreaId;
  bool _estimateExpanded = false;
  final Map<String, int> _draftWorkshopIndexByArea = <String, int>{};

  Map<int, BdoRoyalWorkshopGood> get _goodsById => <int, BdoRoyalWorkshopGood>{
    for (final good in widget.goods) good.id: good,
  };

  void _updateArea(BdoRoyalWorkshopArea area, BdoRoyalWorkshopAreaPlan next) {
    widget.onChanged(widget.plan.withAreaPlan(area.id, next));
  }

  void _updateTask(
    BdoRoyalWorkshopArea area,
    BdoRoyalWorkshopAreaPlan areaPlan,
    int workshopIndex,
    BdoRoyalWorkshopSlotPlan next,
  ) {
    _updateArea(area, areaPlan.withWorkshopPlan(workshopIndex, next));
  }

  BdoRoyalWorkshopGood? _matchingGood(String value, BdoRoyalWorkshopKind kind) {
    final normalized = value.trim().toLowerCase();
    if (normalized.isEmpty) return null;
    for (final good in widget.goods) {
      if (good.kind == kind && good.name.toLowerCase() == normalized) {
        return good;
      }
    }
    return null;
  }

  Set<String> _workersUsedOutside(String areaId) => <String>{
    for (final entry in widget.plan.areaPlans.entries)
      if (entry.key != areaId &&
          entry.value.effectiveWorkerName.trim().isNotEmpty)
        entry.value.effectiveWorkerName.trim().toLowerCase(),
  };

  @override
  Widget build(BuildContext context) {
    final selected = bdoRoyalWorkshopAreasById[_selectedAreaId];
    return DecoratedBox(
      decoration: BoxDecoration(
        color: ResourceMapAtlasColors.paperRaised,
        border: Border.all(color: ResourceMapAtlasColors.divider),
        borderRadius: BorderRadius.circular(18),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x5A000000),
            blurRadius: 28,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Column(
          children: <Widget>[
            _buildHeader(selected),
            const Divider(height: 1, color: ResourceMapAtlasColors.divider),
            Expanded(
              child: AnimatedSwitcher(
                duration: MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : const Duration(milliseconds: 190),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(.025, 0),
                      end: Offset.zero,
                    ).animate(animation),
                    child: child,
                  ),
                ),
                child: selected == null
                    ? _buildOverview(context)
                    : _buildArea(context, selected),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BdoRoyalWorkshopArea? selected) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 12, 14, 12),
      child: Row(
        children: <Widget>[
          if (selected != null)
            IconButton(
              key: const ValueKey<String>('royal-workshop-back-overview'),
              tooltip: 'Back to palace',
              onPressed: () => setState(() {
                _selectedAreaId = null;
                _estimateExpanded = false;
                _draftWorkshopIndexByArea.clear();
              }),
              icon: const Icon(Icons.arrow_back_rounded),
            )
          else
            const _RoyalCrest(),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  selected?.name ?? 'Seoul Royal Workshops',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: ResourceMapAtlasColors.ink,
                    fontSize: 18,
                    height: 1.15,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -.25,
                  ),
                ),
                Text(
                  selected == null
                      ? 'Gyeongbokgung Palace • 8 work areas'
                      : selected.kind == BdoRoyalWorkshopKind.production
                      ? 'Production area'
                      : 'Processing area',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: ResourceMapAtlasColors.muted,
                    fontSize: 11.5,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
          _RoyalStatusChip(
            icon: widget.plan.accessInvested
                ? Icons.check_rounded
                : Icons.lock_outline_rounded,
            label: widget.plan.accessInvested ? '5 CP active' : 'Needs 5 CP',
            active: widget.plan.accessInvested,
          ),
          if (widget.onClose != null) ...<Widget>[
            const SizedBox(width: 7),
            IconButton(
              key: const ValueKey<String>('royal-workshop-close'),
              tooltip: 'Close Royal Workshops',
              onPressed: widget.onClose,
              icon: const Icon(Icons.close_rounded),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildOverview(BuildContext context) {
    final estimate = estimateRoyalWorkshopIncome(
      plan: widget.plan,
      goodsById: _goodsById,
    );
    return LayoutBuilder(
      key: const ValueKey<String>('resource-map-royal-workshop-overview'),
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 760;
        final palace = _PalaceOverview(
          plan: widget.plan,
          goodsById: _goodsById,
          onAreaPressed: (area) => setState(() => _selectedAreaId = area.id),
        );
        final summary = _buildOverviewSummary(estimate);
        return ListView(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 22),
          children: <Widget>[
            _RoyalAccessBanner(
              invested: widget.plan.accessInvested,
              onPressed: () => widget.onChanged(
                widget.plan.copyWith(
                  accessInvested: !widget.plan.accessInvested,
                ),
              ),
            ),
            const SizedBox(height: 14),
            if (wide)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(flex: 6, child: palace),
                  const SizedBox(width: 18),
                  Expanded(flex: 4, child: summary),
                ],
              )
            else ...<Widget>[palace, const SizedBox(height: 14), summary],
          ],
        );
      },
    );
  }

  Widget _buildOverviewSummary(BdoRoyalWorkshopIncomeEstimate estimate) {
    final duplicateWorkers = widget.plan.duplicateWorkerNames;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const Text(
          'Your palace',
          style: TextStyle(
            color: ResourceMapAtlasColors.ink,
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 5),
        const Text(
          'Choose an area on the palace plan. Each area uses one Yukjo worker '
          'and runs one selected workshop at a time.',
          style: TextStyle(
            color: ResourceMapAtlasColors.text,
            fontSize: 12.5,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            _RoyalMetric(
              label: 'Assigned',
              value: '${widget.plan.assignedWorkerCount} / 8 workers',
              icon: Icons.engineering_outlined,
            ),
            _RoyalMetric(
              label: 'Running',
              value: '${widget.plan.runningTaskCount} / 8 areas',
              icon: Icons.play_circle_outline_rounded,
            ),
            _RoyalMetric(
              label: 'Yukjo lodging',
              value:
                  '${widget.yukjoHiredWorkers} hired • '
                  '${widget.yukjoLodgingSlots} slots',
              icon: Icons.bed_outlined,
            ),
          ],
        ),
        if (duplicateWorkers.isNotEmpty) ...<Widget>[
          const SizedBox(height: 10),
          _RoyalNotice(
            icon: Icons.warning_amber_rounded,
            color: ResourceMapAtlasColors.warning,
            text:
                'A Yukjo worker is assigned more than once. Open those areas '
                'and choose a different worker slot.',
          ),
        ],
        const SizedBox(height: 14),
        _RoyalActionRow(
          key: const ValueKey<String>('royal-workshop-open-yukjo-housing'),
          icon: Icons.home_work_outlined,
          title: 'Yukjo workers & storage',
          subtitle: 'Set hired workers, lodging and owned houses.',
          onPressed: widget.onOpenYukjoHousing,
        ),
        if (estimate.includedAreaCount > 0) ...<Widget>[
          const SizedBox(height: 13),
          Text(
            '${_shortSilver(estimate.netSilverPerOnlineHour)} / online hour',
            key: const ValueKey<String>('royal-workshop-income-summary'),
            style: const TextStyle(
              color: ResourceMapAtlasColors.positive,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(
            'From ${estimate.includedAreaCount} recorded ordinary '
            '${estimate.includedAreaCount == 1 ? 'task' : 'tasks'}.',
            style: const TextStyle(
              color: ResourceMapAtlasColors.muted,
              fontSize: 11.5,
            ),
          ),
        ],
        if (estimate.excludedRareAreaCount > 0) ...<Widget>[
          const SizedBox(height: 8),
          const _RoyalNotice(
            icon: Icons.casino_outlined,
            color: ResourceMapAtlasColors.warning,
            text:
                'Rare rolls stay visible, but are not treated as dependable '
                'hourly income because their chance is unknown.',
          ),
        ],
      ],
    );
  }

  Widget _buildArea(BuildContext context, BdoRoyalWorkshopArea area) {
    final areaPlan = widget.plan.planFor(area.id);
    final storedActiveIndex = areaPlan.normalizedActiveWorkshopIndex;
    final draftIndex = _draftWorkshopIndexByArea[area.id];
    final activeIndex =
        draftIndex != null && areaPlan.isWorkshopUnlocked(draftIndex)
        ? draftIndex
        : storedActiveIndex;
    final workshopChangePending = activeIndex != storedActiveIndex;
    final slotPlan = areaPlan.planFor(activeIndex);
    final selectedGood = _goodsById[slotPlan.selectedGoodId];
    final workerName = areaPlan.effectiveWorkerName;
    final excludedRare =
        slotPlan.isRareOrSpecial || selectedGood?.rareRoll == true;
    final canRun =
        widget.plan.accessInvested &&
        workerName.isNotEmpty &&
        slotPlan.hasRecordedGood &&
        !workshopChangePending &&
        !widget.plan.hasDuplicateWorkerName(workerName);
    final hourly =
        !excludedRare &&
            slotPlan.netSilverPerCycle != null &&
            slotPlan.hasTimedTask
        ? (slotPlan.netSilverPerCycle! * slotPlan.repeatCount) /
              slotPlan.taskHours!
        : null;

    return LayoutBuilder(
      key: ValueKey<String>('royal-workshop-area-${area.id}'),
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 760;
        final workshops = _buildWorkshopColumn(
          area,
          areaPlan,
          selectedIndex: activeIndex,
        );
        final management = _buildCurrentAreaManagement(
          area: area,
          areaPlan: areaPlan,
          activeIndex: activeIndex,
          slotPlan: slotPlan,
          selectedGood: selectedGood,
          excludedRare: excludedRare,
          canRun: canRun,
          hourly: hourly,
          storedActiveIndex: storedActiveIndex,
          workshopChangePending: workshopChangePending,
        );
        return ListView(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
          children: <Widget>[
            _buildAreaIntro(area, areaPlan),
            const SizedBox(height: 14),
            if (wide)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  SizedBox(width: 310, child: workshops),
                  const SizedBox(width: 18),
                  Expanded(child: management),
                ],
              )
            else ...<Widget>[workshops, const SizedBox(height: 16), management],
          ],
        );
      },
    );
  }

  Widget _buildAreaIntro(
    BdoRoyalWorkshopArea area,
    BdoRoyalWorkshopAreaPlan plan,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _RoyalAreaGlyph(kind: area.kind, size: 46),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                plan.effectiveIsRunning
                    ? 'Work is recorded as running'
                    : 'Choose a workshop, worker and current task',
                style: const TextStyle(
                  color: ResourceMapAtlasColors.ink,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 3),
              const Text(
                'Changing workshops does not add another worker. One area can '
                'only run one workshop at a time.',
                style: TextStyle(
                  color: ResourceMapAtlasColors.muted,
                  fontSize: 11.5,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        TextButton.icon(
          key: ValueKey<String>('royal-workshop-manager-${area.id}'),
          onPressed: widget.onMarkManager == null
              ? null
              : () => widget.onMarkManager!(area),
          icon: const Icon(Icons.near_me_outlined, size: 17),
          label: Text(area.managerName),
        ),
      ],
    );
  }

  Widget _buildWorkshopColumn(
    BdoRoyalWorkshopArea area,
    BdoRoyalWorkshopAreaPlan areaPlan, {
    required int selectedIndex,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            const Expanded(
              child: Text(
                'Workshops',
                style: TextStyle(
                  color: ResourceMapAtlasColors.ink,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Text(
              '${areaPlan.unlockedWorkshopCount}/${area.maximumWorkshops} open',
              style: const TextStyle(
                color: ResourceMapAtlasColors.muted,
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 7),
        Text(
          'Unlock named workshops with ${area.managerName}. Use the manager '
          'button above to mark the exact NPC location.',
          style: const TextStyle(
            color: ResourceMapAtlasColors.muted,
            fontSize: 10.5,
            height: 1.3,
          ),
        ),
        const SizedBox(height: 8),
        for (var index = 0; index < area.maximumWorkshops; index++)
          Padding(
            padding: const EdgeInsets.only(bottom: 7),
            child: _RoyalWorkshopRow(
              key: ValueKey<String>('royal-workshop-slot-${area.id}-$index'),
              definition: area.workshopAt(index),
              number: index + 1,
              unlocked: areaPlan.isWorkshopUnlocked(index),
              selected: index == selectedIndex,
              onPressed: areaPlan.isWorkshopUnlocked(index)
                  ? () => setState(() {
                      if (index == areaPlan.normalizedActiveWorkshopIndex) {
                        _draftWorkshopIndexByArea.remove(area.id);
                      } else {
                        _draftWorkshopIndexByArea[area.id] = index;
                      }
                    })
                  : null,
              onUnlock: areaPlan.isWorkshopUnlocked(index)
                  ? null
                  : () {
                      setState(
                        () => _draftWorkshopIndexByArea[area.id] = index,
                      );
                      _updateArea(
                        area,
                        areaPlan.withWorkshopUnlocked(index, unlocked: true),
                      );
                    },
            ),
          ),
        if (areaPlan.unlockedWorkshopCount > 1)
          TextButton.icon(
            onPressed: () {
              setState(() => _draftWorkshopIndexByArea.remove(area.id));
              _updateArea(
                area,
                areaPlan.copyWith(
                  unlockedWorkshopIndices: const <int>{0},
                  activeWorkshopIndex: 0,
                  isRunning: false,
                ),
              );
            },
            icon: const Icon(Icons.undo_rounded, size: 17),
            label: const Text('Reset recorded unlocks'),
            style: TextButton.styleFrom(alignment: Alignment.centerLeft),
          ),
      ],
    );
  }

  Widget _buildCurrentAreaManagement({
    required BdoRoyalWorkshopArea area,
    required BdoRoyalWorkshopAreaPlan areaPlan,
    required int activeIndex,
    required BdoRoyalWorkshopSlotPlan slotPlan,
    required BdoRoyalWorkshopGood? selectedGood,
    required bool excludedRare,
    required bool canRun,
    required double? hourly,
    required int storedActiveIndex,
    required bool workshopChangePending,
  }) {
    final definition = area.workshopAt(activeIndex);
    final currentWorker = areaPlan.effectiveWorkerName;
    final usedElsewhere = _workersUsedOutside(area.id);
    final availableWorkers = <String>[
      for (var index = 1; index <= widget.yukjoHiredWorkers; index++)
        'Yukjo worker $index',
    ];
    if (currentWorker.isNotEmpty && !availableWorkers.contains(currentWorker)) {
      availableWorkers.add(currentWorker);
    }
    final visibleWorkers = availableWorkers
        .where(
          (worker) =>
              worker == currentWorker ||
              !usedElsewhere.contains(worker.toLowerCase()),
        )
        .toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          definition.name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: ResourceMapAtlasColors.ink,
            fontSize: 17,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          definition.isStartingWorkshop
              ? 'Available when the Royal Workshop is opened'
              : 'Recorded unlocked • '
                    '${definition.morningGratitudeTokenCost} Morning\'s '
                    'Gratitude Tokens',
          style: const TextStyle(
            color: ResourceMapAtlasColors.muted,
            fontSize: 11.5,
          ),
        ),
        const SizedBox(height: 14),
        if (workshopChangePending) ...<Widget>[
          _RoyalPendingWorkshopChange(
            fromName: area.workshopAt(storedActiveIndex).name,
            toName: definition.name,
            onCancel: () =>
                setState(() => _draftWorkshopIndexByArea.remove(area.id)),
            onConfirm: () {
              setState(() => _draftWorkshopIndexByArea.remove(area.id));
              _updateArea(
                area,
                areaPlan.copyWith(
                  activeWorkshopIndex: activeIndex,
                  isRunning: false,
                ),
              );
            },
          ),
          const SizedBox(height: 14),
        ],
        const _RoyalSectionLabel('YUKJO WORKER'),
        if (widget.yukjoHiredWorkers <= 0 && currentWorker.isEmpty)
          _RoyalNotice(
            icon: Icons.person_add_alt_1_rounded,
            color: ResourceMapAtlasColors.accent,
            text:
                'No Yukjo workers are recorded yet. Set your hired workers '
                'first, then return to assign one here.',
            actionLabel: 'Set workers',
            onAction: widget.onOpenYukjoHousing,
          )
        else
          LayoutBuilder(
            builder: (context, constraints) {
              final workerLabels = <String>[
                'No worker assigned',
                ...visibleWorkers,
              ];
              final menuWidth = readableSelectMenuWidth(
                context,
                workerLabels,
                triggerWidth: constraints.maxWidth,
              );
              return InputDecorator(
                isEmpty: false,
                decoration: const InputDecoration(
                  labelText: 'Worker for this area',
                  prefixIcon: Icon(Icons.engineering_outlined, size: 19),
                  helperText:
                      'A worker already used in another area is hidden.',
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    key: ValueKey<String>('royal-workshop-worker-${area.id}'),
                    value: currentWorker,
                    isExpanded: true,
                    itemHeight: null,
                    menuMaxHeight: 320,
                    menuWidth: menuWidth,
                    items: <DropdownMenuItem<String>>[
                      const DropdownMenuItem<String>(
                        value: '',
                        child: Text('No worker assigned'),
                      ),
                      for (final worker in visibleWorkers)
                        DropdownMenuItem<String>(
                          value: worker,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Text(worker, softWrap: true),
                          ),
                        ),
                    ],
                    onChanged: (value) => _updateArea(
                      area,
                      areaPlan.withAreaRuntime(
                        workerName: value,
                        clearWorkerName: value == null || value.isEmpty,
                        isRunning: false,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        const SizedBox(height: 14),
        _RoyalSectionLabel(
          area.kind == BdoRoyalWorkshopKind.production
              ? 'CURRENT PRODUCTION ROLL'
              : 'CURRENT PROCESSING RECIPE',
        ),
        if (area.kind == BdoRoyalWorkshopKind.production) ...<Widget>[
          _RoyalActionRow(
            key: const ValueKey<String>('royal-workshop-refresh-toggle'),
            icon: widget.plan.freeRefreshAvailable
                ? Icons.refresh_rounded
                : Icons.check_circle_outline_rounded,
            title: widget.plan.freeRefreshAvailable
                ? 'Daily free refresh available'
                : 'Daily refresh already used',
            subtitle: 'Record the refresh state shown for production in BDO.',
            onPressed: () => widget.onChanged(
              widget.plan.copyWith(
                freeRefreshAvailable: !widget.plan.freeRefreshAvailable,
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
        Autocomplete<BdoRoyalWorkshopGood>(
          key: ValueKey<String>('royal-workshop-good-$activeIndex'),
          optionsMaxHeight: 320,
          optionsViewOpenDirection: OptionsViewOpenDirection.mostSpace,
          initialValue: TextEditingValue(
            text: slotPlan.recordedGoodName.trim().isNotEmpty
                ? slotPlan.recordedGoodName
                : selectedGood?.name ?? '',
          ),
          displayStringForOption: (good) => good.name,
          optionsBuilder: (value) {
            final query = value.text.trim().toLowerCase();
            if (query.length < 2) return const <BdoRoyalWorkshopGood>[];
            return widget.goods
                .where(
                  (good) =>
                      good.kind == area.kind &&
                      good.name.toLowerCase().contains(query),
                )
                .take(10);
          },
          optionsViewBuilder: (context, onSelected, options) {
            final values = options.toList(growable: false);
            return LayoutBuilder(
              builder: (context, constraints) {
                final preferredWidth = readableSelectMenuWidth(
                  context,
                  values.map((good) => good.name),
                  triggerWidth: constraints.maxWidth,
                  horizontalChrome: 32,
                  minimumWidth: 0,
                );
                final menuWidth = math.min(
                  preferredWidth,
                  constraints.maxWidth,
                );
                return Align(
                  alignment: Alignment.topLeft,
                  child: Material(
                    key: const ValueKey<String>('royal-workshop-good-options'),
                    elevation: 18,
                    shadowColor: const Color(0x3A17211F),
                    color: ResourceMapAtlasColors.paperRaised,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(11),
                      side: const BorderSide(
                        color: ResourceMapAtlasColors.divider,
                      ),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: SizedBox(
                      width: menuWidth,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 320),
                        child: ListView.builder(
                          padding: EdgeInsets.zero,
                          shrinkWrap: true,
                          itemCount: values.length,
                          itemBuilder: (context, index) {
                            final good = values[index];
                            final highlighted =
                                AutocompleteHighlightedOption.of(context) ==
                                index;
                            return ListTile(
                              tileColor: highlighted
                                  ? ResourceMapAtlasColors.accent.withValues(
                                      alpha: .10,
                                    )
                                  : null,
                              title: Text(
                                good.name,
                                softWrap: true,
                                maxLines: null,
                                overflow: TextOverflow.visible,
                              ),
                              onTap: () => onSelected(good),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                );
              },
            );
          },
          onSelected: (good) => _updateTask(
            area,
            areaPlan,
            activeIndex,
            slotPlan.copyWith(
              selectedGoodId: good.id,
              recordedGoodName: good.name,
              isRareOrSpecial: good.rareRoll,
              clearNetSilverPerCycle: good.rareRoll,
            ),
          ),
          fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
            return TextField(
              controller: controller,
              focusNode: focusNode,
              maxLines: null,
              onSubmitted: (_) => onFieldSubmitted(),
              onChanged: (value) {
                final match = _matchingGood(value, area.kind);
                _updateTask(
                  area,
                  areaPlan,
                  activeIndex,
                  slotPlan.copyWith(
                    selectedGoodId: match?.id,
                    clearSelectedGood: match == null,
                    recordedGoodName: value,
                    isRareOrSpecial:
                        match?.rareRoll ?? slotPlan.isRareOrSpecial,
                    clearNetSilverPerCycle: match?.rareRoll == true,
                  ),
                );
              },
              decoration: InputDecoration(
                labelText: area.kind == BdoRoyalWorkshopKind.production
                    ? 'Item currently shown in BDO'
                    : 'Recipe currently selected in BDO',
                hintText: 'Type the current item or recipe',
                prefixIcon: Icon(
                  area.kind == BdoRoyalWorkshopKind.production
                      ? Icons.casino_outlined
                      : Icons.inventory_2_outlined,
                  size: 19,
                ),
                helperText:
                    'Suggestions recognize names; they do not guess which '
                    'workshop can roll each item.',
                helperMaxLines: 2,
              ),
            );
          },
        ),
        const SizedBox(height: 10),
        _RoyalEstimateEditor(
          expanded: _estimateExpanded,
          area: area,
          areaPlan: areaPlan,
          workshopIndex: activeIndex,
          plan: slotPlan,
          selectedGood: selectedGood,
          excludedRare: excludedRare,
          hourly: hourly,
          onToggle: () =>
              setState(() => _estimateExpanded = !_estimateExpanded),
          onChanged: (next) => _updateTask(area, areaPlan, activeIndex, next),
        ),
        const SizedBox(height: 14),
        Row(
          children: <Widget>[
            Expanded(
              child: OutlinedButton.icon(
                onPressed: widget.onOpenYukjoHousing,
                icon: const Icon(Icons.warehouse_outlined, size: 18),
                label: const Text('Yukjo setup'),
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: FilledButton.icon(
                key: ValueKey<String>('royal-workshop-start-${area.id}'),
                onPressed: canRun
                    ? () => _updateArea(
                        area,
                        areaPlan.withAreaRuntime(
                          isRunning: !areaPlan.effectiveIsRunning,
                        ),
                      )
                    : null,
                icon: Icon(
                  areaPlan.effectiveIsRunning
                      ? Icons.stop_circle_outlined
                      : Icons.play_arrow_rounded,
                  size: 19,
                ),
                label: Text(
                  areaPlan.effectiveIsRunning ? 'Mark stopped' : 'Mark running',
                ),
              ),
            ),
          ],
        ),
        if (!canRun)
          const Padding(
            padding: EdgeInsets.only(top: 7),
            child: Text(
              'To mark this area running: record the 5 CP investment, assign '
              'one Yukjo worker, confirm the workshop, and enter the current '
              'item or recipe.',
              style: TextStyle(
                color: ResourceMapAtlasColors.muted,
                fontSize: 11.5,
                height: 1.35,
              ),
            ),
          ),
      ],
    );
  }
}

class _PalaceOverview extends StatelessWidget {
  const _PalaceOverview({
    required this.plan,
    required this.goodsById,
    required this.onAreaPressed,
  });

  final BdoRoyalWorkshopPlan plan;
  final Map<int, BdoRoyalWorkshopGood> goodsById;
  final ValueChanged<BdoRoyalWorkshopArea> onAreaPressed;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1.16,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: ResourceMapAtlasColors.paper,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: ResourceMapAtlasColors.divider),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) => Stack(
            children: <Widget>[
              Positioned.fill(
                child: CustomPaint(painter: const _PalacePlanPainter()),
              ),
              const Positioned(
                left: 14,
                top: 12,
                child: Text(
                  'GYEONGBOKGUNG PALACE',
                  style: TextStyle(
                    color: ResourceMapAtlasColors.muted,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.1,
                  ),
                ),
              ),
              for (final area in bdoRoyalWorkshopAreas)
                Positioned(
                  left: area.mapX * constraints.maxWidth - 48,
                  top: area.mapY * constraints.maxHeight - 31,
                  width: 96,
                  child: _RoyalAreaButton(
                    area: area,
                    plan: plan.planFor(area.id),
                    good:
                        goodsById[plan
                            .planFor(area.id)
                            .activePlan
                            .selectedGoodId],
                    onPressed: () => onAreaPressed(area),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoyalPendingWorkshopChange extends StatelessWidget {
  const _RoyalPendingWorkshopChange({
    required this.fromName,
    required this.toName,
    required this.onCancel,
    required this.onConfirm,
  });

  final String fromName;
  final String toName;
  final VoidCallback onCancel;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: ResourceMapAtlasColors.accent.withValues(alpha: .08),
        border: Border.all(
          color: ResourceMapAtlasColors.accent.withValues(alpha: .52),
        ),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const Row(
              children: <Widget>[
                Icon(
                  Icons.swap_horiz_rounded,
                  size: 18,
                  color: ResourceMapAtlasColors.accent,
                ),
                SizedBox(width: 7),
                Expanded(
                  child: Text(
                    'Change active workshop?',
                    style: TextStyle(
                      color: ResourceMapAtlasColors.ink,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 5),
            Text(
              '$fromName  →  $toName',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: ResourceMapAtlasColors.muted,
                fontSize: 11.5,
                height: 1.3,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: <Widget>[
                TextButton(
                  key: const ValueKey<String>('royal-workshop-change-cancel'),
                  onPressed: onCancel,
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 6),
                FilledButton(
                  key: const ValueKey<String>('royal-workshop-change-confirm'),
                  onPressed: onConfirm,
                  child: const Text('Change workshop'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RoyalAreaButton extends StatelessWidget {
  const _RoyalAreaButton({
    required this.area,
    required this.plan,
    required this.good,
    required this.onPressed,
  });

  final BdoRoyalWorkshopArea area;
  final BdoRoyalWorkshopAreaPlan plan;
  final BdoRoyalWorkshopGood? good;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final recordedName = good?.name ?? plan.activePlan.recordedGoodName.trim();
    return Tooltip(
      message: recordedName.isEmpty
          ? '${area.name}: no current task recorded'
          : '${area.name}: $recordedName',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: ValueKey<String>('royal-workshop-area-button-${area.id}'),
          onTap: onPressed,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Stack(
                  clipBehavior: Clip.none,
                  children: <Widget>[
                    _RoyalAreaGlyph(kind: area.kind, size: 39),
                    if (plan.effectiveIsRunning)
                      const Positioned(
                        right: -4,
                        top: -4,
                        child: Icon(
                          Icons.play_circle_fill_rounded,
                          size: 16,
                          color: ResourceMapAtlasColors.positive,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 3),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: const Color(0xE6151E1C),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 2,
                    ),
                    child: Text(
                      area.name,
                      maxLines: 2,
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: ResourceMapAtlasColors.ink,
                        fontSize: 9.5,
                        height: 1.05,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RoyalWorkshopRow extends StatelessWidget {
  const _RoyalWorkshopRow({
    super.key,
    required this.definition,
    required this.number,
    required this.unlocked,
    required this.selected,
    required this.onPressed,
    required this.onUnlock,
  });

  final BdoRoyalWorkshopDefinition definition;
  final int number;
  final bool unlocked;
  final bool selected;
  final VoidCallback? onPressed;
  final VoidCallback? onUnlock;

  @override
  Widget build(BuildContext context) {
    final color = selected
        ? ResourceMapAtlasColors.primary
        : unlocked
        ? ResourceMapAtlasColors.text
        : ResourceMapAtlasColors.muted;
    return Material(
      color: selected
          ? ResourceMapAtlasColors.primary.withValues(alpha: .12)
          : ResourceMapAtlasColors.paper,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: selected
              ? ResourceMapAtlasColors.primary
              : ResourceMapAtlasColors.divider,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed ?? onUnlock,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 9, 8, 9),
          child: Row(
            children: <Widget>[
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color.withValues(alpha: .13),
                  border: Border.all(color: color.withValues(alpha: .7)),
                ),
                child: unlocked
                    ? Text(
                        '$number',
                        style: TextStyle(
                          color: color,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      )
                    : Icon(Icons.lock_outline_rounded, size: 15, color: color),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      definition.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: color,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      unlocked
                          ? selected
                                ? 'Current workshop'
                                : 'Available'
                          : '${definition.morningGratitudeTokenCost} tokens',
                      style: const TextStyle(
                        color: ResourceMapAtlasColors.muted,
                        fontSize: 10.5,
                      ),
                    ),
                  ],
                ),
              ),
              if (onUnlock != null)
                const Text(
                  'Record unlock',
                  style: TextStyle(
                    color: ResourceMapAtlasColors.accent,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                  ),
                )
              else if (unlocked)
                Icon(
                  selected ? Icons.check_rounded : Icons.chevron_right_rounded,
                  size: 18,
                  color: color,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoyalEstimateEditor extends StatelessWidget {
  const _RoyalEstimateEditor({
    required this.expanded,
    required this.area,
    required this.areaPlan,
    required this.workshopIndex,
    required this.plan,
    required this.selectedGood,
    required this.excludedRare,
    required this.hourly,
    required this.onToggle,
    required this.onChanged,
  });

  final bool expanded;
  final BdoRoyalWorkshopArea area;
  final BdoRoyalWorkshopAreaPlan areaPlan;
  final int workshopIndex;
  final BdoRoyalWorkshopSlotPlan plan;
  final BdoRoyalWorkshopGood? selectedGood;
  final bool excludedRare;
  final double? hourly;
  final VoidCallback onToggle;
  final ValueChanged<BdoRoyalWorkshopSlotPlan> onChanged;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: ResourceMapAtlasColors.paper,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: ResourceMapAtlasColors.divider),
      ),
      child: Column(
        children: <Widget>[
          InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(11),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: <Widget>[
                  const Icon(
                    Icons.query_stats_rounded,
                    color: ResourceMapAtlasColors.accent,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          'Income estimate',
                          style: TextStyle(
                            color: ResourceMapAtlasColors.ink,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          'Optional: add the values shown for your worker.',
                          style: TextStyle(
                            color: ResourceMapAtlasColors.muted,
                            fontSize: 10.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (hourly != null)
                    Text(
                      _shortSilver(hourly!),
                      style: const TextStyle(
                        color: ResourceMapAtlasColors.positive,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  const SizedBox(width: 6),
                  Icon(
                    expanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    color: ResourceMapAtlasColors.muted,
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            child: expanded
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(12, 2, 12, 12),
                    child: Column(
                      children: <Widget>[
                        if (selectedGood?.durationAt150WorkerSpeedHours
                            case final hours?)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Text(
                              'Client reference: about '
                              '${hours.toStringAsFixed(0)} hours at 150 worker '
                              'speed. Use the time shown by your own worker.',
                              style: const TextStyle(
                                color: ResourceMapAtlasColors.muted,
                                fontSize: 10.5,
                                height: 1.3,
                              ),
                            ),
                          ),
                        Row(
                          children: <Widget>[
                            Expanded(
                              child: TextFormField(
                                key: ValueKey<String>(
                                  'royal-workshop-hours-${area.id}-$workshopIndex',
                                ),
                                initialValue: plan.taskHours?.toString(),
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                inputFormatters: <TextInputFormatter>[
                                  FilteringTextInputFormatter.allow(
                                    RegExp(r'[0-9.]'),
                                  ),
                                ],
                                onChanged: (value) => onChanged(
                                  plan.copyWith(
                                    taskHours: double.tryParse(value),
                                    clearTaskHours: value.trim().isEmpty,
                                  ),
                                ),
                                decoration: const InputDecoration(
                                  labelText: 'Task hours',
                                  isDense: true,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextFormField(
                                key: ValueKey<String>(
                                  'royal-workshop-net-${area.id}-$workshopIndex',
                                ),
                                initialValue: plan.netSilverPerCycle == null
                                    ? ''
                                    : (plan.netSilverPerCycle! / 1000000)
                                          .toString(),
                                enabled: !excludedRare,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                inputFormatters: <TextInputFormatter>[
                                  FilteringTextInputFormatter.allow(
                                    RegExp(r'[0-9.]'),
                                  ),
                                ],
                                onChanged: (value) => onChanged(
                                  plan.copyWith(
                                    netSilverPerCycle:
                                        (double.tryParse(value) ?? 0) * 1000000,
                                    clearNetSilverPerCycle: value
                                        .trim()
                                        .isEmpty,
                                  ),
                                ),
                                decoration: const InputDecoration(
                                  labelText: 'Net / cycle (m)',
                                  isDense: true,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: <Widget>[
                            Checkbox(
                              value: excludedRare,
                              onChanged: selectedGood?.rareRoll == true
                                  ? null
                                  : (value) => onChanged(
                                      plan.copyWith(
                                        isRareOrSpecial: value == true,
                                        clearNetSilverPerCycle: value == true,
                                      ),
                                    ),
                            ),
                            const Expanded(
                              child: Text(
                                'Rare/special roll — exclude from steady income',
                                style: TextStyle(
                                  color: ResourceMapAtlasColors.text,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                            IconButton(
                              key: ValueKey<String>(
                                'royal-workshop-cycles-minus-${area.id}-$workshopIndex',
                              ),
                              tooltip: 'One fewer cycle',
                              onPressed: plan.repeatCount <= 1
                                  ? null
                                  : () => onChanged(
                                      plan.copyWith(
                                        repeatCount: plan.repeatCount - 1,
                                      ),
                                    ),
                              icon: const Icon(Icons.remove_rounded, size: 18),
                            ),
                            Text(
                              '${plan.repeatCount}',
                              key: ValueKey<String>(
                                'royal-workshop-cycles-${area.id}-$workshopIndex',
                              ),
                              style: const TextStyle(
                                color: ResourceMapAtlasColors.ink,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            IconButton(
                              key: ValueKey<String>(
                                'royal-workshop-cycles-plus-${area.id}-$workshopIndex',
                              ),
                              tooltip: 'One more cycle',
                              onPressed: plan.repeatCount >= 999
                                  ? null
                                  : () => onChanged(
                                      plan.copyWith(
                                        repeatCount: plan.repeatCount + 1,
                                      ),
                                    ),
                              icon: const Icon(Icons.add_rounded, size: 18),
                            ),
                          ],
                        ),
                      ],
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

class _RoyalAccessBanner extends StatelessWidget {
  const _RoyalAccessBanner({required this.invested, required this.onPressed});

  final bool invested;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: invested
            ? ResourceMapAtlasColors.positive.withValues(alpha: .1)
            : ResourceMapAtlasColors.accent.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(
          color: invested
              ? ResourceMapAtlasColors.positive.withValues(alpha: .55)
              : ResourceMapAtlasColors.accent.withValues(alpha: .55),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        child: Row(
          children: <Widget>[
            Icon(
              invested
                  ? Icons.check_circle_outline_rounded
                  : Icons.lock_open_rounded,
              color: invested
                  ? ResourceMapAtlasColors.positive
                  : ResourceMapAtlasColors.accent,
              size: 22,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    invested
                        ? 'Royal Workshop access recorded'
                        : 'Open the Royal Workshops for 5 CP',
                    style: const TextStyle(
                      color: ResourceMapAtlasColors.ink,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    invested
                        ? 'The planner reserves these 5 CP from worker routes.'
                        : 'Do this from Seoul in BDO, then record it here.',
                    style: const TextStyle(
                      color: ResourceMapAtlasColors.muted,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            TextButton(
              key: const ValueKey<String>('royal-workshop-invested'),
              onPressed: onPressed,
              child: Text(invested ? 'Undo' : 'Record 5 CP'),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoyalActionRow extends StatelessWidget {
  const _RoyalActionRow({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onPressed,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 9),
        child: Row(
          children: <Widget>[
            Icon(icon, color: ResourceMapAtlasColors.accent, size: 19),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    style: const TextStyle(
                      color: ResourceMapAtlasColors.ink,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: ResourceMapAtlasColors.muted,
                      fontSize: 10.5,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: ResourceMapAtlasColors.muted,
              size: 19,
            ),
          ],
        ),
      ),
    );
  }
}

class _RoyalNotice extends StatelessWidget {
  const _RoyalNotice({
    required this.icon,
    required this.color,
    required this.text,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final Color color;
  final String text;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: color.withValues(alpha: .38)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          children: <Widget>[
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(
                  color: ResourceMapAtlasColors.text,
                  fontSize: 11,
                  height: 1.35,
                ),
              ),
            ),
            if (onAction != null && actionLabel != null)
              TextButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ),
      ),
    );
  }
}

class _RoyalMetric extends StatelessWidget {
  const _RoyalMetric({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 132),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: ResourceMapAtlasColors.paper,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: ResourceMapAtlasColors.divider),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 18, color: ResourceMapAtlasColors.primary),
          const SizedBox(width: 7),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  label,
                  style: const TextStyle(
                    color: ResourceMapAtlasColors.muted,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  value,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: ResourceMapAtlasColors.ink,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RoyalStatusChip extends StatelessWidget {
  const _RoyalStatusChip({
    required this.icon,
    required this.label,
    required this.active,
  });

  final IconData icon;
  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final color = active
        ? ResourceMapAtlasColors.positive
        : ResourceMapAtlasColors.accent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: .45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _RoyalCrest extends StatelessWidget {
  const _RoyalCrest();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: ResourceMapAtlasColors.accent.withValues(alpha: .12),
        shape: BoxShape.circle,
        border: Border.all(
          color: ResourceMapAtlasColors.accent.withValues(alpha: .6),
        ),
      ),
      child: const Icon(
        Icons.account_balance_rounded,
        color: ResourceMapAtlasColors.accent,
        size: 21,
      ),
    );
  }
}

class _RoyalAreaGlyph extends StatelessWidget {
  const _RoyalAreaGlyph({required this.kind, required this.size});

  final BdoRoyalWorkshopKind kind;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = kind == BdoRoyalWorkshopKind.production
        ? ResourceMapAtlasColors.positive
        : ResourceMapAtlasColors.accent;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: ResourceMapAtlasColors.paperRaised,
        shape: BoxShape.circle,
        border: Border.all(color: color, width: 2),
        boxShadow: const <BoxShadow>[
          BoxShadow(color: Color(0x66000000), blurRadius: 5),
        ],
      ),
      child: Icon(
        kind == BdoRoyalWorkshopKind.production
            ? Icons.agriculture_outlined
            : Icons.inventory_2_outlined,
        color: color,
        size: size * .5,
      ),
    );
  }
}

class _RoyalSectionLabel extends StatelessWidget {
  const _RoyalSectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: const TextStyle(
          color: ResourceMapAtlasColors.muted,
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: .85,
        ),
      ),
    );
  }
}

class _PalacePlanPainter extends CustomPainter {
  const _PalacePlanPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final courtyard = Paint()
      ..color = const Color(0x243E5A50)
      ..style = PaintingStyle.fill;
    final outline = Paint()
      ..color = const Color(0x8056A89A)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.25;
    final gold = Paint()
      ..color = const Color(0x56C79B58)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final center = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        size.width * .35,
        size.height * .1,
        size.width * .2,
        size.height * .76,
      ),
      const Radius.circular(6),
    );
    canvas.drawRRect(center, courtyard);
    canvas.drawRRect(center, outline);
    for (final y in <double>[.18, .32, .46, .60, .74]) {
      final building = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          size.width * .38,
          size.height * y,
          size.width * .14,
          math.max(4, size.height * .055),
        ),
        const Radius.circular(2),
      );
      canvas.drawRRect(building, gold);
    }
    final outer = Path()
      ..moveTo(size.width * .13, size.height * .91)
      ..lineTo(size.width * .13, size.height * .08)
      ..lineTo(size.width * .78, size.height * .08)
      ..lineTo(size.width * .78, size.height * .91);
    canvas.drawPath(outer, outline);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

String _shortSilver(double value) {
  if (value >= 1000000000) {
    return '${(value / 1000000000).toStringAsFixed(2)}b silver';
  }
  if (value >= 1000000) {
    return '${(value / 1000000).toStringAsFixed(2)}m silver';
  }
  if (value >= 1000) {
    return '${(value / 1000).toStringAsFixed(1)}k silver';
  }
  return '${value.toStringAsFixed(0)} silver';
}
