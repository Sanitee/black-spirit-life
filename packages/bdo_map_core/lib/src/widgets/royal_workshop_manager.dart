import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../royal_workshop/royal_workshop_models.dart';
import 'readable_select_controls.dart';
import 'resource_map_chrome_theme.dart';
import 'resource_map_panel_metrics.dart';

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
    final theme = Theme.of(context);
    final controlText = theme.textTheme.labelLarge!.copyWith(
      fontSize: ResourceMapPanelMetrics.primary,
      fontWeight: FontWeight.w500,
    );
    final buttonStyle = ButtonStyle(
      textStyle: WidgetStatePropertyAll(controlText),
      minimumSize: const WidgetStatePropertyAll(Size(0, 32)),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      ),
      visualDensity: VisualDensity.compact,
    );
    return Theme(
      data: theme.copyWith(
        textTheme: theme.textTheme.copyWith(
          bodyLarge: theme.textTheme.bodyLarge?.copyWith(
            fontSize: ResourceMapPanelMetrics.primary,
          ),
          titleMedium: theme.textTheme.titleMedium?.copyWith(
            fontSize: ResourceMapPanelMetrics.primary,
          ),
        ),
        inputDecorationTheme: theme.inputDecorationTheme.copyWith(
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 10,
          ),
          labelStyle: const TextStyle(
            fontSize: ResourceMapPanelMetrics.secondary,
          ),
          floatingLabelStyle: const TextStyle(
            // InputDecorator scales a floating label to 75%.
            fontSize: ResourceMapPanelMetrics.secondary / .75,
          ),
        ),
        textButtonTheme: TextButtonThemeData(style: buttonStyle),
        outlinedButtonTheme: OutlinedButtonThemeData(style: buttonStyle),
        filledButtonTheme: FilledButtonThemeData(style: buttonStyle),
        iconButtonTheme: const IconButtonThemeData(
          style: ButtonStyle(
            minimumSize: WidgetStatePropertyAll(Size(32, 32)),
            padding: WidgetStatePropertyAll(EdgeInsets.all(6)),
            visualDensity: VisualDensity.compact,
          ),
        ),
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: context.mapChrome.paperRaised,
          border: Border.all(color: context.mapChrome.divider),
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
              Divider(height: 1, color: context.mapChrome.divider),
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
      ),
    );
  }

  Widget _buildHeader(BdoRoyalWorkshopArea? selected) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
      child: Row(
        children: <Widget>[
          if (selected != null)
            MapQuietIconButton(
              key: const ValueKey<String>('royal-workshop-back-overview'),
              tooltip: 'Back to palace',
              onPressed: () => setState(() {
                _selectedAreaId = null;
                _estimateExpanded = false;
                _draftWorkshopIndexByArea.clear();
              }),
              icon: Icon(Icons.arrow_back_rounded),
            )
          else
            const _RoyalCrest(),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              selected?.name ?? 'Royal Workshops',
              style: TextStyle(
                color: context.mapChrome.ink,
                fontSize: ResourceMapPanelMetrics.heading,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (widget.onClose != null) ...<Widget>[
            const SizedBox(width: 7),
            MapQuietIconButton(
              key: const ValueKey<String>('royal-workshop-close'),
              tooltip: 'Close Royal Workshops',
              onPressed: widget.onClose,
              icon: Icon(Icons.close_rounded),
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
    return ListView(
      key: const ValueKey<String>('resource-map-royal-workshop-overview'),
      padding: const EdgeInsets.all(12),
      children: <Widget>[
        Wrap(
          spacing: 8,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            _RoyalAccessBanner(
              invested: widget.plan.accessInvested,
              onPressed: () => widget.onChanged(
                widget.plan.copyWith(
                  accessInvested: !widget.plan.accessInvested,
                ),
              ),
            ),
            OutlinedButton.icon(
              key: const ValueKey<String>('royal-workshop-open-yukjo-housing'),
              icon: const Icon(Icons.home_work_outlined, size: 18),
              label: const Text('Yukjo setup'),
              onPressed: widget.onOpenYukjoHousing,
            ),
            if (estimate.includedAreaCount > 0)
              Tooltip(
                message: 'Net silver per online hour. Rare rolls excluded.',
                child: Text(
                  '${_shortSilver(estimate.netSilverPerOnlineHour)} / h',
                  key: const ValueKey<String>('royal-workshop-income-summary'),
                  style: TextStyle(
                    color: context.mapChrome.positive,
                    fontSize: ResourceMapPanelMetrics.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
        if (widget.plan.duplicateWorkerNames.isNotEmpty) ...<Widget>[
          const SizedBox(height: 8),
          _RoyalNotice(
            icon: Icons.warning_amber_rounded,
            color: context.mapChrome.warning,
            text: 'Worker assigned twice.',
          ),
        ],
        const SizedBox(height: 10),
        _PalaceOverview(
          plan: widget.plan,
          goodsById: _goodsById,
          onAreaPressed: (area) => setState(() => _selectedAreaId = area.id),
        ),
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
        final wide =
            constraints.maxWidth / MediaQuery.textScalerOf(context).scale(1) >=
            620;
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
          padding: const EdgeInsets.all(12),
          children: <Widget>[
            if (wide)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  SizedBox(width: 220, child: workshops),
                  const SizedBox(width: 12),
                  Expanded(child: management),
                ],
              )
            else ...<Widget>[workshops, const SizedBox(height: 16), management],
          ],
        );
      },
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
            Expanded(
              child: Text(
                'Workshops',
                style: TextStyle(
                  color: context.mapChrome.ink,
                  fontSize: ResourceMapPanelMetrics.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (widget.onMarkManager != null)
              MapQuietIconButton(
                key: ValueKey<String>('royal-workshop-manager-${area.id}'),
                tooltip: area.managerName,
                onPressed: () => widget.onMarkManager!(area),
                icon: const Icon(Icons.near_me_outlined, size: 18),
              ),
          ],
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
            icon: Icon(Icons.undo_rounded, size: 17),
            label: Text('Reset unlocks'),
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
    final readiness = [
      if (!widget.plan.accessInvested) '5 CP required',
      if (currentWorker.isEmpty) 'Choose a worker',
      if (widget.plan.hasDuplicateWorkerName(currentWorker))
        'Worker already in use',
      if (workshopChangePending) 'Confirm workshop change',
      if (!slotPlan.hasRecordedGood) 'Choose an item',
    ].join(' · ');
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
          style: TextStyle(
            color: context.mapChrome.ink,
            fontSize: ResourceMapPanelMetrics.heading,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 10),
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
          const SizedBox(height: 10),
        ],
        if (widget.yukjoHiredWorkers <= 0 && currentWorker.isEmpty)
          _RoyalNotice(
            icon: Icons.person_add_alt_1_rounded,
            color: context.mapChrome.accent,
            text: 'No workers',
            actionLabel: 'Set workers',
            onAction: widget.onOpenYukjoHousing,
          )
        else
          LayoutBuilder(
            builder: (context, constraints) {
              final workerLabels = <String>['Choose worker', ...visibleWorkers];
              final menuWidth = readableSelectMenuWidth(
                context,
                workerLabels,
                triggerWidth: constraints.maxWidth,
              );
              return InputDecorator(
                isEmpty: false,
                decoration: const InputDecoration(
                  labelText: 'Worker',
                  prefixIcon: Icon(Icons.engineering_outlined, size: 19),
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
                        child: Text('Choose worker'),
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
        const SizedBox(height: 10),
        if (area.kind == BdoRoyalWorkshopKind.production) ...<Widget>[
          _RoyalActionRow(
            key: const ValueKey<String>('royal-workshop-refresh-toggle'),
            icon: widget.plan.freeRefreshAvailable
                ? Icons.refresh_rounded
                : Icons.check_circle_outline_rounded,
            title: widget.plan.freeRefreshAvailable
                ? 'Refresh'
                : 'Refresh used',
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
                    color: context.mapChrome.paperRaised,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(11),
                      side: BorderSide(color: context.mapChrome.divider),
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
                                  ? context.mapChrome.accent.withValues(
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
                    ? 'Item'
                    : 'Recipe',
                prefixIcon: Icon(
                  area.kind == BdoRoyalWorkshopKind.production
                      ? Icons.casino_outlined
                      : Icons.inventory_2_outlined,
                  size: 19,
                ),
                suffixIcon: const Tooltip(
                  message: 'Names only. Check the item shown in your workshop.',
                  child: Icon(Icons.info_outline_rounded, size: 18),
                ),
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
        const SizedBox(height: 10),
        Row(
          children: <Widget>[
            Expanded(
              child: OutlinedButton.icon(
                onPressed: widget.onOpenYukjoHousing,
                icon: Icon(Icons.warehouse_outlined, size: 18),
                label: Text('Yukjo setup'),
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Tooltip(
                message: readiness,
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
                    areaPlan.effectiveIsRunning
                        ? 'Mark stopped'
                        : 'Mark running',
                  ),
                ),
              ),
            ),
          ],
        ),
        if (widget.plan.hasDuplicateWorkerName(currentWorker))
          Padding(
            padding: const EdgeInsets.only(top: 7),
            child: Text(
              'Worker already in use',
              style: TextStyle(
                color: context.mapChrome.muted,
                fontSize: ResourceMapPanelMetrics.secondary,
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final twoColumns =
            constraints.maxWidth / MediaQuery.textScalerOf(context).scale(1) >=
            440;
        final width = twoColumns
            ? (constraints.maxWidth - 8) / 2
            : constraints.maxWidth;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            for (final area in bdoRoyalWorkshopAreas)
              SizedBox(
                width: width,
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
        );
      },
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
        color: context.mapChrome.accent.withValues(alpha: .08),
        border: Border.all(
          color: context.mapChrome.accent.withValues(alpha: .52),
        ),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(
                  Icons.swap_horiz_rounded,
                  size: 18,
                  color: context.mapChrome.accent,
                ),
                SizedBox(width: 7),
                Expanded(
                  child: Text(
                    'Change active workshop?',
                    style: TextStyle(
                      color: context.mapChrome.ink,
                      fontSize: ResourceMapPanelMetrics.primary,
                      fontWeight: FontWeight.w600,
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
              style: TextStyle(
                color: context.mapChrome.muted,
                fontSize: ResourceMapPanelMetrics.secondary,
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
                  child: Text('Cancel'),
                ),
                const SizedBox(width: 6),
                FilledButton(
                  key: const ValueKey<String>('royal-workshop-change-confirm'),
                  onPressed: onConfirm,
                  child: Text('Change workshop'),
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
    return Material(
      color: context.mapChrome.paper,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(9),
        side: BorderSide(color: context.mapChrome.divider),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: ValueKey<String>('royal-workshop-area-button-${area.id}'),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.all(9),
          child: Row(
            children: <Widget>[
              _RoyalAreaGlyph(
                kind: area.kind,
                size: ResourceMapPanelMetrics.navigationArtwork,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      area.name,
                      style: TextStyle(
                        color: context.mapChrome.ink,
                        fontSize: ResourceMapPanelMetrics.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (recordedName.isNotEmpty)
                      Text(
                        recordedName,
                        style: TextStyle(
                          color: context.mapChrome.muted,
                          fontSize: ResourceMapPanelMetrics.secondary,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                plan.effectiveIsRunning
                    ? Icons.play_circle_fill_rounded
                    : Icons.chevron_right_rounded,
                size: 18,
                color: plan.effectiveIsRunning
                    ? context.mapChrome.positive
                    : context.mapChrome.muted,
              ),
            ],
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
        ? context.mapChrome.primary
        : unlocked
        ? context.mapChrome.text
        : context.mapChrome.muted;
    return Material(
      color: selected
          ? context.mapChrome.primary.withValues(alpha: .12)
          : context.mapChrome.paper,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: selected
              ? context.mapChrome.primary
              : context.mapChrome.divider,
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
                          fontSize: ResourceMapPanelMetrics.secondary,
                          fontWeight: FontWeight.w600,
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
                      style: TextStyle(
                        color: color,
                        fontSize: ResourceMapPanelMetrics.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (!unlocked)
                      Text(
                        '${definition.morningGratitudeTokenCost} tokens',
                        style: TextStyle(
                          color: context.mapChrome.muted,
                          fontSize: ResourceMapPanelMetrics.secondary,
                        ),
                      ),
                  ],
                ),
              ),
              if (onUnlock != null)
                Tooltip(
                  message: 'Mark unlocked',
                  child: Icon(
                    Icons.lock_open_rounded,
                    semanticLabel: 'Mark unlocked',
                    color: context.mapChrome.accent,
                    size: ResourceMapPanelMetrics.controlGlyph,
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
        color: context.mapChrome.paper,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: context.mapChrome.divider),
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
                  Icon(
                    Icons.query_stats_rounded,
                    color: context.mapChrome.accent,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          'Income',
                          style: TextStyle(
                            color: context.mapChrome.ink,
                            fontSize: ResourceMapPanelMetrics.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (hourly != null)
                    Text(
                      _shortSilver(hourly!),
                      style: TextStyle(
                        color: context.mapChrome.positive,
                        fontSize: ResourceMapPanelMetrics.secondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  const SizedBox(width: 6),
                  Icon(
                    expanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    color: context.mapChrome.muted,
                  ),
                ],
              ),
            ),
          ),
          _RoyalDetailsReveal(
            child: expanded
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(12, 2, 12, 12),
                    child: Column(
                      children: <Widget>[
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
                            Expanded(
                              child: Text(
                                'Rare roll',
                                style: TextStyle(
                                  color: context.mapChrome.text,
                                  fontSize: ResourceMapPanelMetrics.secondary,
                                ),
                              ),
                            ),
                            MapQuietIconButton(
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
                              icon: Icon(Icons.remove_rounded, size: 18),
                            ),
                            Text(
                              '${plan.repeatCount}',
                              key: ValueKey<String>(
                                'royal-workshop-cycles-${area.id}-$workshopIndex',
                              ),
                              style: TextStyle(
                                color: context.mapChrome.ink,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            MapQuietIconButton(
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
                              icon: Icon(Icons.add_rounded, size: 18),
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

class _RoyalDetailsReveal extends StatelessWidget {
  const _RoyalDetailsReveal({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => MediaQuery.disableAnimationsOf(context)
      ? child
      : AnimatedSize(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          child: child,
        );
}

class _RoyalAccessBanner extends StatelessWidget {
  const _RoyalAccessBanner({required this.invested, required this.onPressed});

  final bool invested;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      key: const ValueKey<String>('royal-workshop-invested'),
      onPressed: onPressed,
      icon: Icon(
        invested ? Icons.check_circle_outline_rounded : Icons.lock_open_rounded,
        size: 18,
      ),
      label: Text(invested ? '5 CP invested' : 'Record 5 CP'),
    );
  }
}

class _RoyalActionRow extends StatelessWidget {
  const _RoyalActionRow({
    super.key,
    required this.icon,
    required this.title,
    required this.onPressed,
  });

  final IconData icon;
  final String title;
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
            Icon(icon, color: context.mapChrome.accent, size: 19),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    style: TextStyle(
                      color: context.mapChrome.ink,
                      fontSize: ResourceMapPanelMetrics.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: context.mapChrome.muted,
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
                style: TextStyle(
                  color: context.mapChrome.text,
                  fontSize: ResourceMapPanelMetrics.secondary,
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

class _RoyalCrest extends StatelessWidget {
  const _RoyalCrest();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: ResourceMapPanelMetrics.navigationArtwork,
      height: ResourceMapPanelMetrics.navigationArtwork,
      decoration: BoxDecoration(
        color: context.mapChrome.accent.withValues(alpha: .12),
        shape: BoxShape.circle,
        border: Border.all(
          color: context.mapChrome.accent.withValues(alpha: .6),
        ),
      ),
      child: Icon(
        Icons.account_balance_rounded,
        color: context.mapChrome.accent,
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
        ? context.mapChrome.positive
        : context.mapChrome.accent;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: context.mapChrome.paperRaised,
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
