import 'package:flutter/material.dart';

import '../lodging/lodging_data.dart';
import '../lodging/town_house_investment.dart';
import 'house_use_icon.dart';
import 'resource_map_chrome_theme.dart';
import 'resource_map_panel_metrics.dart';

String houseUseLabel(HouseUsage use) => use.typeId == 3 ? 'Stable' : use.label;

/// Housing follows the same compact type and row rhythm as the map controls.
abstract final class TownHousePanelMetrics {
  static const double primary = ResourceMapPanelMetrics.primary;
  static const double artwork = 28;
  static const double rowHeight = 40;
}

/// A content-only surface: the map shell supplies the one shared glass layer.
class TownHousePanel extends StatelessWidget {
  const TownHousePanel({
    super.key,
    required this.town,
    required this.goals,
    required this.plan,
    required this.owned,
    required this.ownedUsages,
    required this.selectedHouseId,
    required this.browseAll,
    required this.onGoalsChanged,
    required this.onSelectHouse,
    required this.onOwnedChanged,
    required this.onUseChanged,
    required this.onBrowseChanged,
    required this.onFit,
    required this.onShopLodging,
    this.onImport,
    this.error,
  });
  final LodgingTown town;
  final List<TownHouseGoal> goals;
  final TownHouseInvestment? plan;
  final Set<String> owned;
  final Map<String, int> ownedUsages;
  final String? selectedHouseId;
  final bool browseAll;
  final ValueChanged<List<TownHouseGoal>> onGoalsChanged;
  final ValueChanged<String?> onSelectHouse;
  final ValueChanged<LodgingHouse> onOwnedChanged;
  final void Function(LodgingHouse, int) onUseChanged;
  final ValueChanged<bool> onBrowseChanged;
  final VoidCallback onFit;
  final VoidCallback onShopLodging;
  final VoidCallback? onImport;
  final String? error;

  List<HouseUsage> get _uses {
    final types = <int, HouseUsage>{};
    for (final house in town.houses) {
      for (final use in house.usages) {
        if (use.level > (types[use.typeId]?.level ?? 0)) {
          types[use.typeId] = use;
        }
      }
    }
    return types.values.toList()..sort((a, b) => a.label.compareTo(b.label));
  }

  void _change(TownHouseGoal goal, int amount, {int? level}) {
    onGoalsChanged([
      for (final g in goals)
        if (!(g.typeId == goal.typeId && g.typeId > 3 && amount <= 0))
          if (g.typeId == goal.typeId)
            TownHouseGoal(
              g.typeId,
              amount,
              minimumLevel: level ?? g.minimumLevel,
            )
          else
            g,
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final uses = _uses;
    final workshops = goals.where((g) => g.typeId > 3).toList();
    final remaining = uses
        .where(
          (u) => u.typeId > 3 && !workshops.any((g) => g.typeId == u.typeId),
        )
        .toList();
    final ids = browseAll
        ? town.housesById.keys.toSet()
        : <String>{...?plan?.requiredHouseIds, ?selectedHouseId};
    final houses =
        ids.map((id) => town.housesById[id]).whereType<LodgingHouse>().toList()
          ..sort((a, b) => a.sourceKey.compareTo(b.sourceKey));
    final active = goals.any((g) => g.amount > 0);
    final ink = context.mapChrome.ink;
    return DefaultTextStyle.merge(
      style: TextStyle(color: ink, fontSize: TownHousePanelMetrics.primary),
      child: Column(
        key: ValueKey('resource-map-town-housing-${town.townNodeId}'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final type in [1, 2, 3])
            if (uses.any((u) => u.typeId == type))
              _goalRow(
                context,
                uses.firstWhere((u) => u.typeId == type),
                goals.firstWhere((g) => g.typeId == type),
              ),
          for (final goal in workshops)
            _goalRow(
              context,
              uses.firstWhere((u) => u.typeId == goal.typeId),
              goal,
              removable: true,
            ),
          if (remaining.isNotEmpty)
            ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: TownHousePanelMetrics.rowHeight,
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<int>(
                  key: const ValueKey('house-add-workshop'),
                  isExpanded: true,
                  itemHeight: null,
                  style: DefaultTextStyle.of(context).style.copyWith(
                    color: ink,
                    fontSize: TownHousePanelMetrics.primary,
                  ),
                  hint: Text(
                    workshops.isEmpty ? 'Add workshop' : 'Add another workshop',
                  ),
                  isDense: true,
                  icon: const Icon(
                    Icons.add_rounded,
                    size: ResourceMapPanelMetrics.controlGlyph,
                  ),
                  items: [
                    for (final use in remaining)
                      DropdownMenuItem(
                        value: use.typeId,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Row(
                            children: [
                              HouseUseIcon(
                                typeId: use.typeId,
                                size: TownHousePanelMetrics.artwork,
                              ),
                              const SizedBox(width: 8),
                              Expanded(child: Text(_uniqueUseLabel(use, uses))),
                            ],
                          ),
                        ),
                      ),
                  ],
                  onChanged: (type) {
                    if (type != null) {
                      onGoalsChanged([...goals, TownHouseGoal(type, 1)]);
                    }
                  },
                ),
              ),
            ),
          Divider(
            height: 13,
            color: context.mapChrome.softOutline.withValues(alpha: .45),
          ),
          Row(
            children: [
              Expanded(
                child: active
                    ? _summary(context, uses)
                    : const SizedBox.shrink(),
              ),
              IconButton(
                tooltip: 'Show houses on map',
                onPressed: onFit,
                key: ValueKey('resource-map-fit-houses-${town.townNodeId}'),
                constraints: const BoxConstraints.tightFor(
                  width: ResourceMapPanelMetrics.controlTarget,
                  height: ResourceMapPanelMetrics.controlTarget,
                ),
                padding: EdgeInsets.zero,
                style: IconButton.styleFrom(
                  minimumSize: const Size.square(
                    ResourceMapPanelMetrics.controlTarget,
                  ),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                icon: const Icon(
                  Icons.center_focus_strong_rounded,
                  size: ResourceMapPanelMetrics.controlGlyph,
                ),
              ),
              PopupMenuButton<String>(
                tooltip: 'House options',
                padding: EdgeInsets.zero,
                style: IconButton.styleFrom(
                  minimumSize: const Size.square(
                    ResourceMapPanelMetrics.controlTarget,
                  ),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onSelected: (value) {
                  switch (value) {
                    case 'browse':
                      onBrowseChanged(!browseAll);
                    case 'shop':
                      onShopLodging();
                    case 'import':
                      onImport?.call();
                  }
                },
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: 'browse',
                    child: Text(
                      browseAll ? 'Show recommendations' : 'Browse all houses',
                    ),
                  ),
                  if (town.isWorkerTown)
                    const PopupMenuItem(
                      value: 'shop',
                      child: Text('Shop lodging'),
                    ),
                  if (onImport != null)
                    const PopupMenuItem(
                      value: 'import',
                      child: Text('Scan house screenshots'),
                    ),
                ],
                icon: const Icon(
                  Icons.more_horiz_rounded,
                  size: ResourceMapPanelMetrics.controlGlyph,
                ),
              ),
            ],
          ),
          if (error != null)
            Text(error!, style: TextStyle(color: context.mapChrome.error)),
          if (plan != null && !plan!.isFeasible)
            Text(
              'Not enough houses for this target.',
              style: TextStyle(color: context.mapChrome.error),
            ),
          if (browseAll)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => onBrowseChanged(false),
                icon: const Icon(
                  Icons.arrow_back,
                  size: ResourceMapPanelMetrics.controlGlyph,
                ),
                label: const Text('Recommendations'),
              ),
            ),
          for (final house in houses) _houseRow(context, house),
        ],
      ),
    );
  }

  String _uniqueUseLabel(HouseUsage use, List<HouseUsage> uses) {
    if (uses.where((u) => u.label == use.label).length < 2) {
      return houseUseLabel(use);
    }
    final first = town.houses.firstWhere((h) => h.supportsUsage(use.typeId));
    return '${use.label} · ${first.name}';
  }

  Widget _goalRow(
    BuildContext context,
    HouseUsage use,
    TownHouseGoal goal, {
    bool removable = false,
  }) {
    final maximum = town.houses
        .where(
          (h) =>
              !owned.contains(h.id) &&
              (h.usagesByTypeId[use.typeId]?.level ?? 0) >= goal.minimumLevel,
        )
        .fold(0, (sum, h) => sum + houseUseCapacity(h, use.typeId));
    final unit = switch (use.typeId) {
      1 => goal.amount == 1 ? 'bed' : 'beds',
      2 || 3 => goal.amount == 1 ? 'slot' : 'slots',
      _ => '',
    };
    final label = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          _uniqueUseLabel(use, _uses),
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        if (removable && use.level > 1)
          PopupMenuButton<int>(
            key: ValueKey('house-workshop-level-${use.typeId}'),
            tooltip: 'Minimum workshop level',
            initialValue: goal.minimumLevel,
            itemBuilder: (context) => [
              for (var level = 1; level <= use.level; level++)
                PopupMenuItem(
                  value: level,
                  child: Text(
                    'Lv. $level+',
                    style: const TextStyle(
                      fontSize: ResourceMapPanelMetrics.secondary,
                    ),
                  ),
                ),
            ],
            onSelected: (level) => _change(goal, goal.amount, level: level),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 28),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      'Lv. ${goal.minimumLevel}',
                      style: TextStyle(
                        fontSize: ResourceMapPanelMetrics.secondary,
                        color: context.mapChrome.muted,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.arrow_drop_down,
                    size: ResourceMapPanelMetrics.controlGlyph,
                    color: context.mapChrome.muted,
                  ),
                ],
              ),
            ),
          ),
      ],
    );
    final counter = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _step(
          context,
          'Remove ${houseUseLabel(use)}',
          Icons.remove_rounded,
          goal.amount > 0 ? () => _change(goal, goal.amount - 1) : null,
          'house-goal-minus-${use.typeId}',
        ),
        Tooltip(
          message:
              'Extra ${unit.isEmpty ? 'workshops' : unit} at maximum house level.\nExisting houses keep their current use.',
          child: ConstrainedBox(
            constraints: BoxConstraints.tightFor(
              width: _counterValueWidth(context),
            ),
            child: Text(
              '${goal.amount}${unit.isEmpty ? '' : ' $unit'}',
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ),
        _step(
          context,
          'Add ${houseUseLabel(use)}',
          Icons.add_rounded,
          goal.amount < maximum ? () => _change(goal, goal.amount + 1) : null,
          'house-goal-plus-${use.typeId}',
        ),
      ],
    );
    return ConstrainedBox(
      key: ValueKey('house-goal-${use.typeId}'),
      constraints: const BoxConstraints(
        minHeight: TownHousePanelMetrics.rowHeight,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final stacked =
                MediaQuery.textScalerOf(
                      context,
                    ).scale(TownHousePanelMetrics.primary) >
                    TownHousePanelMetrics.primary * 1.6 ||
                constraints.maxWidth - _counterValueWidth(context) - 64 < 100;
            final title = Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                HouseUseIcon(
                  typeId: use.typeId,
                  size: TownHousePanelMetrics.artwork,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: label,
                  ),
                ),
              ],
            );
            if (stacked) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  title,
                  Align(alignment: Alignment.centerRight, child: counter),
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: title),
                counter,
              ],
            );
          },
        ),
      ),
    );
  }

  double _counterValueWidth(BuildContext context) {
    var width = 44.0;
    for (final goal in goals) {
      final unit = switch (goal.typeId) {
        1 => goal.amount == 1 ? ' bed' : ' beds',
        2 || 3 => goal.amount == 1 ? ' slot' : ' slots',
        _ => '',
      };
      final painter = TextPainter(
        text: TextSpan(
          text: '${goal.amount}$unit',
          style: DefaultTextStyle.of(context).style.copyWith(
            fontSize: TownHousePanelMetrics.primary,
            fontWeight: FontWeight.w700,
          ),
        ),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      )..layout();
      if (painter.width + 8 > width) width = painter.width + 8;
      painter.dispose();
    }
    return width.clamp(44, 118);
  }

  Widget _step(
    BuildContext context,
    String label,
    IconData icon,
    VoidCallback? action,
    String key,
  ) => IconButton(
    key: ValueKey(key),
    tooltip: label,
    onPressed: action,
    constraints: const BoxConstraints.tightFor(width: 32, height: 36),
    padding: EdgeInsets.zero,
    style: IconButton.styleFrom(
      minimumSize: const Size(32, 36),
      fixedSize: const Size(32, 36),
      padding: EdgeInsets.zero,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    ),
    icon: Icon(icon, size: ResourceMapPanelMetrics.controlGlyph),
  );

  Widget _summary(BuildContext context, List<HouseUsage> uses) {
    if (error != null) return const SizedBox.shrink();
    if (plan == null) return const Text('Finding houses…');
    if (!plan!.isFeasible) return const SizedBox.shrink();
    return Wrap(
      spacing: 10,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final entry in plan!.addedCapacity.entries)
          Tooltip(
            message:
                '${uses.firstWhere((u) => u.typeId == entry.key).label}: ${entry.value} extra',
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                HouseUseIcon(
                  typeId: entry.key,
                  size: TownHousePanelMetrics.artwork,
                ),
                const SizedBox(width: 4),
                Text(
                  '+${entry.value}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        Text(
          '${plan!.cp} CP',
          key: const ValueKey('house-plan-cp'),
          style: TextStyle(
            color: context.mapChrome.primary,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }

  Widget _houseRow(BuildContext context, LodgingHouse house) {
    final selected = house.id == selectedHouseId;
    final invested = owned.contains(house.id);
    final recommendedUse = plan?.usages[house.id];
    final type = recommendedUse ?? ownedUsages[house.id];
    final usage = house.usagesByTypeId[type];
    final description = usage == null
        ? (plan?.requiredHouseIds.contains(house.id) == true
              ? 'Connection'
              : '')
        : '${houseUseLabel(usage)} · ${usage.typeId <= 3 ? '+${houseUseCapacity(house, usage.typeId)} ${usage.typeId == 1 ? 'beds' : 'slots'}' : 'Lv. ${usage.level}'}';
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            key: ValueKey('resource-map-house-row-${house.id}'),
            onTap: () => onSelectHouse(selected ? null : house.id),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  HouseUseIcon(
                    typeId: type ?? 0,
                    size: TownHousePanelMetrics.artwork,
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          house.name,
                          style: const TextStyle(
                            fontSize: TownHousePanelMetrics.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (description.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            description,
                            style: TextStyle(
                              fontSize: ResourceMapPanelMetrics.secondary,
                              color: context.mapChrome.muted,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    invested ? 'Owned' : '${house.contributionPoints} CP',
                    style: TextStyle(
                      fontSize: ResourceMapPanelMetrics.secondary,
                      color: context.mapChrome.primary,
                    ),
                  ),
                  Icon(
                    selected ? Icons.expand_less : Icons.expand_more,
                    size: ResourceMapPanelMetrics.controlGlyph,
                  ),
                ],
              ),
            ),
          ),
        ),
        _HouseDetailsReveal(
          child: selected
              ? Padding(
                  key: ValueKey('resource-map-selected-house-${house.id}'),
                  padding: const EdgeInsets.only(
                    left: TownHousePanelMetrics.artwork + 9,
                    bottom: 8,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final use in house.usages)
                        InkWell(
                          key: ValueKey('house-use-${house.id}-${use.typeId}'),
                          onTap: () => onUseChanged(house, use.typeId),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Row(
                              children: [
                                HouseUseIcon(
                                  typeId: use.typeId,
                                  size: TownHousePanelMetrics.artwork,
                                ),
                                const SizedBox(width: 7),
                                Expanded(
                                  child: Text(
                                    houseUseLabel(use),
                                    style: const TextStyle(
                                      fontSize: TownHousePanelMetrics.primary,
                                    ),
                                  ),
                                ),
                                Text(
                                  'Lv. ${use.level}',
                                  style: TextStyle(
                                    fontSize: ResourceMapPanelMetrics.secondary,
                                    color: context.mapChrome.muted,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Icon(
                                  invested &&
                                          ownedUsages[house.id] == use.typeId
                                      ? Icons.check_circle
                                      : Icons.radio_button_unchecked,
                                  size: ResourceMapPanelMetrics.controlGlyph,
                                  color: context.mapChrome.primary,
                                ),
                              ],
                            ),
                          ),
                        ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton(
                          key: ValueKey(
                            'resource-map-house-row-owned-${house.id}',
                          ),
                          onPressed: () => onOwnedChanged(house),
                          child: Text(
                            invested ? 'Remove ownership' : 'Mark owned',
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}

class _HouseDetailsReveal extends StatelessWidget {
  const _HouseDetailsReveal({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => MediaQuery.disableAnimationsOf(context)
      ? child
      : AnimatedSize(
          duration: const Duration(milliseconds: 180),
          alignment: Alignment.topCenter,
          curve: Curves.easeOutCubic,
          child: child,
        );
}
