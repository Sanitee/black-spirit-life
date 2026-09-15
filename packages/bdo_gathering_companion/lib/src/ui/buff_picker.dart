import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../domain/models.dart';
import '../domain/pets.dart';
import 'hover_pinned_details.dart';
import 'pet_recommendations.dart';
import 'theme.dart';

String effectText(Catalog catalog, String key, num value) {
  final unit = catalog.statUnit(key);
  final suffix = unit == '%'
      ? '%'
      : unit.isEmpty
      ? ''
      : ' $unit';
  return '${value > 0 ? '+' : ''}${numberText(value)}$suffix';
}

List<String> _qualitativeEffects(Buff buff) => [
  // The catalog records this effect in usage notes without an audited rate.
  // Keep the effect visible without exposing the surrounding advice.
  if (buff.notes.contains('Constantly consumes MP/WP/SP.'))
    'Constantly consumes MP/WP/SP.',
];

/// Short, readable rows for cards and the details dialog. The catalog keeps
/// the complete audited sentence; presentation should not turn it into a wall
/// of text.
List<String> compactBuffEffectLines(Buff buff) {
  var summary = buff.effectSummary.trim();
  if (summary.isEmpty) return const [];
  summary = summary.replaceFirst(
    RegExp(r'^Combination bonus:\s*', caseSensitive: false),
    '',
  );
  summary = summary.replaceFirst(
    RegExp(
      r'\s*Component stats are listed in details\.?\s*$',
      caseSensitive: false,
    ),
    '',
  );
  return summary
      .split(RegExp(r'\s*·\s*'))
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList(growable: false);
}

class _BuffIngredient {
  const _BuffIngredient(this.name, this.quantity);

  final String name;
  final String quantity;
}

class _BuffAcquisition {
  const _BuffAcquisition({
    required this.heading,
    this.lines = const [],
    this.ingredients = const [],
  });

  final String heading;
  final List<String> lines;
  final List<_BuffIngredient> ingredients;
}

_BuffAcquisition? _buffAcquisition(Buff buff) {
  final summary = buff.obtainSummary.trim();
  if (summary.isEmpty) return null;
  final method = RegExp(
    r'^(Simple Alchemy|Simple Cooking|Alchemy|Cooking|Heating|Grinding|Shaking):\s*(.+)$',
    caseSensitive: false,
  ).firstMatch(summary);
  if (method == null) {
    return _BuffAcquisition(heading: 'How to get', lines: [summary]);
  }

  final heading = switch (method.group(1)!.toLowerCase()) {
    'simple alchemy' => 'Simple Alchemy',
    'simple cooking' => 'Simple Cooking',
    'alchemy' => 'Alchemy',
    'cooking' => 'Cooking',
    'heating' => 'Heating',
    'grinding' => 'Grinding',
    'shaking' => 'Shaking',
    _ => method.group(1)!,
  };
  final body = method.group(2)!.replaceFirst(RegExp(r'\.\s*$'), '');
  final pieces = body
      .replaceAll(RegExp(r',\s+and\s+'), ', ')
      .split(RegExp(r',\s*'))
      .map((part) => part.trim())
      .where((part) => part.isNotEmpty)
      .toList(growable: false);
  final ingredients = <_BuffIngredient>[];
  for (final piece in pieces) {
    final match = RegExp(r'^(.+?)\s+x([0-9][0-9.,]*)$').firstMatch(piece);
    if (match == null) {
      return _BuffAcquisition(heading: heading, lines: pieces);
    }
    ingredients.add(_BuffIngredient(match.group(1)!.trim(), match.group(2)!));
  }
  return _BuffAcquisition(heading: heading, ingredients: ingredients);
}

({String icon, int? grade})? _ingredientArtwork(Catalog catalog, String name) {
  final normalized = name.trim().toLowerCase();
  for (final item in catalog.items) {
    if (item.name.trim().toLowerCase() == normalized && item.icon.isNotEmpty) {
      return (icon: item.icon, grade: null);
    }
  }
  for (final buff in catalog.buffs) {
    if (buff.name.trim().toLowerCase() == normalized && buff.icon.isNotEmpty) {
      return (icon: buff.icon, grade: buff.grade);
    }
  }
  return null;
}

class BuffPicker extends StatelessWidget {
  const BuffPicker({
    super.key,
    required this.catalog,
    required this.activity,
    required this.selected,
    required this.onToggle,
    required this.onPreset,
    required this.onClear,
    this.selectedPetIds = const {},
    this.pets,
    this.onPetToggle,
    this.onClearPets,
    this.methodId,
    this.spotId,
  });
  final Catalog catalog;
  final String activity;
  final Set<String> selected;
  final ValueChanged<Buff> onToggle;
  final ValueChanged<Map<String, dynamic>> onPreset;
  final VoidCallback onClear;
  final Set<String> selectedPetIds;
  final List<PetRecommendation>? pets;
  final ValueChanged<PetRecommendation>? onPetToggle;
  final VoidCallback? onClearPets;
  final String? methodId, spotId;
  @override
  Widget build(BuildContext context) {
    final presets = catalog.presets
        .where((p) => p['activity'] == activity)
        .toList();
    final eventBuffs =
        catalog.buffs.where((buff) => buff.category == 'events').toList()
          ..sort((a, b) => a.priority.compareTo(b.priority));
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 32),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 10,
            runSpacing: 4,
            children: [
              const Text(
                'Buffs',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
              ),
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 2,
                runSpacing: 4,
                children: [
                  if (eventBuffs.isNotEmpty)
                    _eventItemsMenu(context, eventBuffs),
                  if (selected.isNotEmpty)
                    IconButton(
                      key: const ValueKey('clear-buffs'),
                      onPressed: onClear,
                      tooltip: 'Clear buffs',
                      icon: const Icon(Icons.clear, size: 19),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints.tightFor(
                        width: 32,
                        height: 32,
                      ),
                      visualDensity: VisualDensity.compact,
                    ),
                  if (presets.isNotEmpty)
                    PopupMenuButton<Map<String, dynamic>>(
                      key: const ValueKey('buff-presets'),
                      tooltip: 'Suggested setups',
                      onSelected: onPreset,
                      itemBuilder: (_) => presets
                          .map(
                            (p) => PopupMenuItem(
                              value: p,
                              child: Text(textOf(p, 'name')),
                            ),
                          )
                          .toList(),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 180),
                      icon: const Icon(Icons.more_horiz, size: 22),
                      style: IconButton.styleFrom(
                        minimumSize: const Size(32, 32),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final petGroups = methodId == null ? <String>[] : ['_pets'];
            Widget column(List<String> ids, {double verticalSpacing = 8}) =>
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final entry in ids.indexed) ...[
                      if (entry.$1 > 0) SizedBox(height: verticalSpacing),
                      _categoryPanel(context, entry.$2),
                    ],
                  ],
                );
            Widget columns(
              List<List<String>> groups, {
              List<int>? flexes,
              double spacing = 8,
              double verticalSpacing = 8,
            }) => Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final group in groups.indexed) ...[
                  if (group.$1 > 0) SizedBox(width: spacing),
                  Expanded(
                    flex: flexes?[group.$1] ?? 1,
                    child: column(group.$2, verticalSpacing: verticalSpacing),
                  ),
                ],
              ],
            );
            final knownIds = {
              'foods',
              'draughts',
              'elixirs',
              'perfumes',
              'scrolls',
              'stones',
              'energy',
              'other',
              'lightstones',
              'events',
            };
            final extraIds = catalog.categories
                .map((category) => textOf(category, 'id'))
                .where((id) => !knownIds.contains(id))
                .toList();
            if (constraints.maxWidth < 480) {
              return column([
                ...catalog.categories
                    .map((c) => textOf(c, 'id'))
                    .where((id) => id != 'events'),
                ...petGroups,
              ]);
            }
            if (constraints.maxWidth >= 1200) {
              return columns(
                [
                  ['foods', ...petGroups],
                  ['scrolls', 'lightstones'],
                  ['draughts', 'perfumes'],
                  ['elixirs'],
                  ['stones', 'other'],
                  ['energy', ...extraIds],
                ],
                flexes: const [3, 3, 3, 4, 3, 4],
                spacing: 6,
                verticalSpacing: 4,
              );
            }
            if (constraints.maxWidth >= 1040) {
              return columns([
                ['foods', 'scrolls'],
                ['draughts', 'perfumes', 'lightstones'],
                ['elixirs'],
                ['stones', 'other', ...petGroups],
                ['energy', ...extraIds],
              ], spacing: 6);
            }
            if (constraints.maxWidth >= 780) {
              return columns([
                ['foods', 'scrolls', 'stones'],
                ['draughts', 'perfumes', 'lightstones'],
                ['elixirs', ...petGroups],
                ['energy', 'other', ...extraIds],
              ]);
            }
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                columns([
                  ['foods', 'scrolls', 'stones', 'lightstones'],
                  ['draughts', 'perfumes', ...petGroups, 'other'],
                ], verticalSpacing: 4),
                const SizedBox(height: 4),
                _categoryPanel(context, 'elixirs'),
                const SizedBox(height: 4),
                _categoryPanel(context, 'energy'),
                for (final id in extraIds) ...[
                  const SizedBox(height: 8),
                  _categoryPanel(context, id),
                ],
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _eventItemsMenu(BuildContext context, List<Buff> events) {
    final selectedCount = events
        .where((buff) => selected.contains(buff.id))
        .length;
    return PopupMenuButton<Buff>(
      key: const ValueKey('buff-row-events'),
      tooltip: 'Event items you may own',
      onSelected: (buff) {
        if (buff.referenceOnly) {
          showBuffInfo(context, catalog, buff);
          return;
        }
        onToggle(buff);
      },
      constraints: const BoxConstraints(minWidth: 300, maxWidth: 360),
      itemBuilder: (menuContext) => [
        const PopupMenuItem<Buff>(
          key: ValueKey('event-items-section'),
          enabled: false,
          height: 34,
          child: Text(
            'Event items you may own',
            style: TextStyle(color: muted, fontWeight: FontWeight.w600),
          ),
        ),
        for (final buff in events)
          PopupMenuItem<Buff>(
            key: ValueKey('buff-icon-${buff.id}'),
            value: buff,
            height: 54,
            child: BuffHoverDetails(
              catalog: catalog,
              buff: buff,
              onPin: () {
                Navigator.of(menuContext).pop();
                WidgetsBinding.instance.addPostFrameCallback(
                  (_) => showBuffInfo(context, catalog, buff),
                );
              },
              child: Row(
                children: [
                  GameIcon(buff.icon, size: 40, grade: buff.grade),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          buff.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        Text(
                          buff.effectSummary,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: muted, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  if (!buff.referenceOnly && selected.contains(buff.id))
                    const Icon(Icons.check_circle, size: 17, color: accent),
                ],
              ),
            ),
          ),
      ],
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 32),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.event_available_outlined,
                size: 18,
                color: selectedCount > 0 ? accent : muted,
              ),
              const SizedBox(width: 4),
              const Text(
                'Event items',
                style: TextStyle(fontSize: 13, color: muted),
              ),
              if (selectedCount > 0) ...[
                const SizedBox(width: 3),
                Text(
                  '$selectedCount',
                  style: const TextStyle(
                    fontSize: 12,
                    color: accent,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
              const Icon(Icons.arrow_drop_down, size: 17, color: muted),
            ],
          ),
        ),
      ),
    );
  }

  Widget _categoryPanel(BuildContext context, String id) {
    if (id == '_pets' && methodId != null) {
      return PetRecommendations(
        methodId: methodId!,
        spotId: spotId,
        pets: pets,
        selectedIds: selectedPetIds,
        onToggle: onPetToggle,
        onClear: onClearPets,
      );
    }
    final category = catalog.categories.where((c) => c['id'] == id).firstOrNull;
    if (category == null) return const SizedBox.shrink();
    final buffs = catalog.buffs.where((b) => b.category == id).toList()
      ..sort((a, b) {
        final ar = a.recommendedFor.contains(activity) ? 0 : 1;
        final br = b.recommendedFor.contains(activity) ? 0 : 1;
        return ar != br ? ar.compareTo(br) : a.priority.compareTo(b.priority);
      });
    final label = switch (id) {
      'scrolls' => 'Scrolls & books',
      'stones' => 'Stones',
      'other' => 'Other buffs',
      _ => textOf(category, 'label'),
    };
    return Container(
      key: ValueKey('buff-row-$id'),
      width: double.infinity,
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        gradient: context.glass.groupGradient,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: context.glass.insetLine),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 20),
            child: Tooltip(
              message: textOf(category, 'label'),
              textStyle: const TextStyle(color: ink, fontSize: 14),
              child: Text(
                label,
                style: const TextStyle(
                  color: ink,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  height: 1.2,
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: buffs.map((buff) => _tile(context, buff)).toList(),
          ),
        ],
      ),
    );
  }

  Widget _tile(BuildContext context, Buff buff) {
    final isSelected = !buff.referenceOnly && selected.contains(buff.id);
    void details() => showBuffInfo(context, catalog, buff);
    void activate() => buff.referenceOnly ? details() : onToggle(buff);
    return Semantics(
      key: ValueKey('buff-icon-${buff.id}'),
      button: true,
      selected: buff.referenceOnly ? null : isSelected,
      label: buff.name,
      hint: buff.referenceOnly
          ? 'Reference only. Open effect and acquisition details.'
          : 'Toggle buff. Long press or Shift F10 for effects and duration.',
      onTap: activate,
      onLongPress: details,
      excludeSemantics: true,
      child: BuffHoverDetails(
        catalog: catalog,
        buff: buff,
        child: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.f10, shift: true): details,
          },
          child: GlassControl(
            selected: isSelected,
            radius: 6,
            child: InkWell(
              onTap: activate,
              onLongPress: details,
              excludeFromSemantics: true,
              borderRadius: BorderRadius.circular(6),
              child: SizedBox.square(
                dimension: 44,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    GameIcon(buff.icon, size: 40, grade: buff.grade),
                    if (isSelected && !buff.referenceOnly)
                      Positioned(
                        right: 1,
                        bottom: 1,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: context.glass.popup,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.check_circle,
                            size: 16,
                            color: accent,
                          ),
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

class BuffHoverDetails extends StatelessWidget {
  const BuffHoverDetails({
    super.key,
    required this.catalog,
    required this.buff,
    this.child,
    this.targetBuilder,
    this.onPin,
  }) : assert((child == null) != (targetBuilder == null));
  final Catalog catalog;
  final Buff buff;
  final Widget? child;
  final Widget Function(BuildContext context, VoidCallback pin)? targetBuilder;
  final VoidCallback? onPin;

  @override
  Widget build(BuildContext context) => HoverPinnedDetails(
    hoverKey: ValueKey('buff-hover-card-${buff.id}'),
    onPin: onPin ?? () => showBuffInfo(context, catalog, buff),
    cardBuilder: (context) => _BuffHoverCard(catalog: catalog, buff: buff),
    targetBuilder: targetBuilder,
    child: child,
  );
}

/// Examples for distinct goals, not a preset or a promise that every item stacks.
class RecommendedBuffs extends StatelessWidget {
  const RecommendedBuffs({
    super.key,
    required this.catalog,
    required this.activity,
    this.compact = false,
    this.horizontal = false,
    this.methodId,
    this.spotId,
  });
  final Catalog catalog;
  final String activity;
  final bool compact;

  /// A naturally spaced, wrapping strip for the bottom of the field guide.
  /// Takes precedence over [compact]; both existing layouts remain the default.
  final bool horizontal;
  final String? methodId, spotId;

  static const _shortNames = {
    'buff-791': 'Verdure Draught',
    'buff-750': 'Flowing Time Elixir',
    'buff-768919': "Mercenary’s Life",
    'buff-721092': "Treant’s Tear",
    'buff-9691': 'Seafood Cron Meal',
    'buff-1158': 'Improved Mastery',
    'buff-768064': 'Book of Florin',
    'buff-890': 'Perfume of Verdure',
    'buff-45302': 'Life Spirit Stone',
    'buff-1159': 'Rough Labor Elixir',
    'buff-9301': 'Sweet Fig Pie',
  };

  @override
  Widget build(BuildContext context) {
    final goals = [
      ('exp', 'EXP', ['buff-791', 'buff-750', 'buff-768919', 'buff-721092']),
      (
        'mastery',
        'Mastery',
        ['buff-9691', 'buff-1158', 'buff-768064', 'buff-890'],
      ),
      if (activity == 'gathering')
        (
          'drops',
          'Gathering drops',
          ['buff-721092', 'buff-45302', 'buff-1159', 'buff-9301'],
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final sideBySide = constraints.maxWidth >= 720;
            final width = sideBySide
                ? (constraints.maxWidth - (goals.length - 1) * 8) / goals.length
                : constraints.maxWidth;
            return Wrap(
              spacing: horizontal ? 20 : 8,
              runSpacing: horizontal ? 10 : 6,
              children: [
                ...goals.map((goal) {
                  final options = goal.$3
                      .map(
                        (id) =>
                            catalog.buffs.where((b) => b.id == id).firstOrNull,
                      )
                      .nonNulls
                      .where((b) => b.recommendedFor.contains(activity))
                      .where(
                        (b) => switch (goal.$1) {
                          'exp' =>
                            (b.effects['lifeExpPct'] ?? 0) +
                                    (b.effects[activity == 'gathering'
                                            ? 'gatheringExpPct'
                                            : 'huntingExpPct'] ??
                                        0) >
                                0,
                          'mastery' =>
                            (b.effects['lifeMastery'] ?? 0) +
                                    (b.effects[activity == 'gathering'
                                            ? 'gatheringMastery'
                                            : 'huntingMastery'] ??
                                        0) >
                                0,
                          _ => (b.effects['gatheringItemDropPct'] ?? 0) > 0,
                        },
                      )
                      .toList();
                  if (horizontal) {
                    return _horizontalGoal(
                      context,
                      goal.$1,
                      goal.$1 == 'drops' ? 'Drops' : goal.$2,
                      options,
                      constraints.maxWidth,
                    );
                  }
                  return Container(
                    key: ValueKey('recommended-goal-${goal.$1}'),
                    width: width,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      gradient: context.glass.controlGradient,
                      border: Border.all(color: context.glass.line),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: compact
                        ? _compactGoal(context, goal.$1, goal.$2, options)
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                goal.$2,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  height: 1.15,
                                ),
                              ),
                              const SizedBox(height: 2),
                              LayoutBuilder(
                                builder: (context, constraints) {
                                  final columns = width >= 340 ? 2 : 1;
                                  final itemWidth =
                                      (constraints.maxWidth -
                                          (columns - 1) * 6) /
                                      columns;
                                  return Wrap(
                                    spacing: 6,
                                    runSpacing: 2,
                                    children: options
                                        .map(
                                          (buff) => SizedBox(
                                            width: itemWidth,
                                            child: _recommendedItem(
                                              context,
                                              goal.$1,
                                              buff,
                                            ),
                                          ),
                                        )
                                        .toList(),
                                  );
                                },
                              ),
                            ],
                          ),
                  );
                }),
                if (methodId != null)
                  PetRecommendations(
                    methodId: methodId!,
                    spotId: spotId,
                    framed: !horizontal,
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _horizontalGoal(
    BuildContext context,
    String goal,
    String label,
    List<Buff> options,
    double availableWidth,
  ) {
    const labelWidth = 58.0;
    final naturalWidth = labelWidth + 8 + options.length * 48 - 4;
    final title = Tooltip(
      message: goal == 'drops' ? 'Gathering item drop rate' : label,
      child: Text(
        label,
        style: const TextStyle(
          color: muted,
          fontSize: 14,
          fontWeight: FontWeight.w600,
          height: 1.2,
        ),
      ),
    );
    final icons = Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        for (final buff in options)
          _recommendedItem(context, goal, buff, iconOnly: true, iconSize: 40),
      ],
    );
    return SizedBox(
      key: ValueKey('recommended-goal-$goal'),
      width: naturalWidth.clamp(0, availableWidth).toDouble(),
      child: availableWidth >= naturalWidth
          ? Row(
              children: [
                SizedBox(width: labelWidth, child: title),
                const SizedBox(width: 8),
                Expanded(child: icons),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [title, const SizedBox(height: 4), icons],
            ),
    );
  }

  Widget _compactGoal(
    BuildContext context,
    String goal,
    String label,
    List<Buff> options,
  ) => LayoutBuilder(
    builder: (context, constraints) {
      final title = Text(
        label,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          height: 1.2,
        ),
      );
      final icons = Wrap(
        spacing: 4,
        runSpacing: 4,
        children: [
          for (final buff in options)
            _recommendedItem(context, goal, buff, iconOnly: true),
        ],
      );
      if (constraints.maxWidth >= 308) {
        return Row(
          children: [
            SizedBox(width: 112, child: title),
            const SizedBox(width: 8),
            Expanded(child: icons),
          ],
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [title, const SizedBox(height: 4), icons],
      );
    },
  );

  Widget _recommendedItem(
    BuildContext context,
    String goal,
    Buff buff, {
    bool iconOnly = false,
    double iconSize = 36,
  }) {
    void details() => showBuffInfo(context, catalog, buff);
    return Semantics(
      key: ValueKey('recommended-$goal-${buff.id}'),
      button: true,
      label: buff.name,
      hint:
          'Show effects and duration. This is an alternative, not part of a combined setup.',
      onTap: details,
      onLongPress: details,
      excludeSemantics: true,
      child: BuffHoverDetails(
        catalog: catalog,
        buff: buff,
        child: GlassControl(
          radius: 8,
          child: InkWell(
            onTap: details,
            onLongPress: details,
            excludeFromSemantics: true,
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: iconOnly ? 44 : null,
              height: 44,
              child: iconOnly
                  ? Center(
                      child: GameIcon(
                        buff.icon,
                        size: iconSize,
                        grade: buff.grade,
                      ),
                    )
                  : Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 4,
                      ),
                      child: Row(
                        children: [
                          GameIcon(buff.icon, size: 36, grade: buff.grade),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              _shortNames[buff.id] ?? buff.name,
                              textAlign: TextAlign.left,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 14,
                                height: 1.25,
                              ),
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

Future<void> showBuffInfo(BuildContext context, Catalog catalog, Buff buff) {
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      key: ValueKey('buff-pinned-card-${buff.id}'),
      constraints: const BoxConstraints(maxWidth: 400),
      insetPadding: const EdgeInsets.all(16),
      titlePadding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      contentPadding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      title: _BuffDetailsTitle(buff),
      content: SizedBox(
        width: 368,
        child: SingleChildScrollView(
          child: _BuffDetailsSections(catalog: catalog, buff: buff),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}

class _BuffHoverCard extends StatelessWidget {
  const _BuffHoverCard({required this.catalog, required this.buff});

  final Catalog catalog;
  final Buff buff;

  @override
  Widget build(BuildContext context) => Material(
    color: context.glass.popup,
    elevation: 12,
    shadowColor: Colors.black.withValues(
      alpha: context.glass.shadowOpacity + .08,
    ),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
      side: BorderSide(color: context.glass.line),
    ),
    clipBehavior: Clip.antiAlias,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 400, maxHeight: 620),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _BuffDetailsTitle(buff),
            const SizedBox(height: 12),
            Flexible(
              child: SingleChildScrollView(
                child: _BuffDetailsSections(catalog: catalog, buff: buff),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _BuffDetailsTitle extends StatelessWidget {
  const _BuffDetailsTitle(this.buff);

  final Buff buff;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      GameIcon(buff.icon, size: 36, grade: buff.grade),
      const SizedBox(width: 10),
      Expanded(
        child: Text(
          buff.name,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: itemGradeColor(buff.grade) ?? ink,
          ),
        ),
      ),
    ],
  );
}

class _BuffDetailsSections extends StatelessWidget {
  const _BuffDetailsSections({required this.catalog, required this.buff});

  final Catalog catalog;
  final Buff buff;

  @override
  Widget build(BuildContext context) {
    final summaryLines = compactBuffEffectLines(buff);
    // A component list is already the complete recipe for a combination.
    // Repeating the same recipe as acquisition prose makes the card harder to
    // scan and can drift out of sync with the audited component rows.
    final acquisition = buff.components.isEmpty ? _buffAcquisition(buff) : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (summaryLines.isNotEmpty) ...[
          const _BuffDetailHeading('Effects'),
          const SizedBox(height: 7),
          for (final line in summaryLines)
            _BuffDetailLine(line, key: ValueKey('buff-effect-$line')),
        ] else ...[
          const _BuffDetailHeading('Effects'),
          const SizedBox(height: 7),
          ...buff.effects.entries.map(
            (e) => Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      catalog.statLabel(e.key),
                      style: const TextStyle(fontSize: 14),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    effectText(catalog, e.key, e.value),
                    style: const TextStyle(
                      color: accent,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
          for (final effect in _qualitativeEffects(buff))
            Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: Text(effect, style: const TextStyle(fontSize: 14)),
            ),
          const Divider(height: 16),
          Text(
            buff.duration != null
                ? 'Duration  ${formatDurationMinutes(buff.duration!)}'
                : 'Duration varies',
            style: const TextStyle(fontSize: 14),
          ),
        ],
        if (acquisition != null) ...[
          const Divider(height: 16),
          _BuffDetailHeading(acquisition.heading),
          const SizedBox(height: 7),
          if (acquisition.ingredients.isNotEmpty)
            for (final ingredient in acquisition.ingredients)
              _BuffIngredientRow(
                ingredient: ingredient,
                artwork: _ingredientArtwork(catalog, ingredient.name),
              )
          else
            for (final line in acquisition.lines)
              _BuffDetailLine(line, color: gold),
        ],
        if (buff.components.isNotEmpty) ...[
          const Divider(height: 16),
          const Text(
            'Lightstones',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 7),
          for (final component in buff.components) ...[
            _buffComponentTile(context, component),
            if (component != buff.components.last) const SizedBox(height: 5),
          ],
        ],
      ],
    );
  }
}

class _BuffDetailHeading extends StatelessWidget {
  const _BuffDetailHeading(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Text(
    label,
    style: const TextStyle(
      color: accent,
      fontSize: 13.5,
      fontWeight: FontWeight.w700,
    ),
  );
}

class _BuffDetailLine extends StatelessWidget {
  const _BuffDetailLine(this.text, {super.key, this.color = ink});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(
      text,
      style: TextStyle(fontSize: 14, color: color, height: 1.28),
    ),
  );
}

class _BuffIngredientRow extends StatelessWidget {
  const _BuffIngredientRow({required this.ingredient, required this.artwork});

  final _BuffIngredient ingredient;
  final ({String icon, int? grade})? artwork;

  @override
  Widget build(BuildContext context) => Padding(
    key: ValueKey('buff-obtain-item-${ingredient.name}'),
    padding: const EdgeInsets.only(bottom: 5),
    child: Row(
      children: [
        if (artwork != null) ...[
          GameIcon(artwork!.icon, size: 30, grade: artwork!.grade),
          const SizedBox(width: 8),
        ],
        Expanded(
          child: Text(
            ingredient.name,
            style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '×${ingredient.quantity}',
          style: const TextStyle(
            color: gold,
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}

Widget _buffComponentTile(BuildContext context, BuffComponent component) =>
    Container(
      key: ValueKey('buff-component-${component.id}'),
      width: double.infinity,
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: context.glass.inset,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: context.glass.insetLine),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          GameIcon(component.icon, size: 34, grade: component.grade),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  component.name,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (component.effectSummary.isNotEmpty) ...[
                  const SizedBox(height: 1),
                  Text(
                    component.effectSummary,
                    style: const TextStyle(
                      color: muted,
                      fontSize: 13,
                      height: 1.25,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );

class BuffSummary extends StatelessWidget {
  const BuffSummary({
    super.key,
    required this.catalog,
    required this.totals,
    required this.activity,
    this.baseMastery = 0,
    this.compact = false,
  });
  final Catalog catalog;
  final Map<String, double> totals;
  final String activity;
  final int baseMastery;
  final bool compact;
  @override
  Widget build(BuildContext context) {
    final gathering = activity == 'gathering';
    final exp =
        (totals['lifeExpPct'] ?? 0) +
        (totals[gathering ? 'gatheringExpPct' : 'huntingExpPct'] ?? 0);
    final mastery =
        (totals['lifeMastery'] ?? 0) +
        (totals[gathering ? 'gatheringMastery' : 'huntingMastery'] ?? 0);
    if (compact) {
      return _compactSummary(context, exp, mastery);
    }
    final primary = [
      ('${gathering ? 'Gathering' : 'Hunting'} EXP', '+${numberText(exp)}%'),
      ('Mastery from buffs', '+${numberText(mastery)}'),
      if (baseMastery > 0)
        ('With your base mastery', numberText(baseMastery + mastery)),
      if ((totals['maxWeight'] ?? 0) != 0)
        (
          'Weight limit',
          effectText(catalog, 'maxWeight', totals['maxWeight']!),
        ),
      if ((totals['gatheringItemDropPct'] ?? 0) != 0)
        (
          'Gathering item drop rate',
          effectText(
            catalog,
            'gatheringItemDropPct',
            totals['gatheringItemDropPct']!,
          ),
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (totals.isEmpty)
          const Text(
            'Select buffs to see their combined bonuses.',
            style: TextStyle(color: muted),
          ),
        if (totals.isNotEmpty) ...[
          ...primary.map(
            (r) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(r.$1, style: const TextStyle(fontSize: 14)),
                  ),
                  Text(
                    r.$2,
                    style: const TextStyle(
                      color: accent,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
          ...[
            'gatheringSpeed',
            'movementSpeed',
            'attackSpeed',
            'criticalHit',
          ].where((k) => (totals[k] ?? 0) != 0).map((key) {
            final amount = totals[key]!;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      catalog.statLabel(key),
                      style: const TextStyle(fontSize: 14),
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '+${numberText(amount)} levels',
                        style: const TextStyle(color: accent),
                      ),
                      if (amount >= 5)
                        const Text(
                          'Resulting ability caps at 5',
                          style: TextStyle(fontSize: 14, color: gold),
                        ),
                    ],
                  ),
                ],
              ),
            );
          }),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsets.only(bottom: 8),
            title: const Text(
              'All selected effects',
              style: TextStyle(fontSize: 14),
            ),
            children: totals.entries
                .map(
                  (e) => Padding(
                    padding: const EdgeInsets.only(bottom: 7),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            catalog.statLabel(e.key),
                            style: const TextStyle(fontSize: 14, color: muted),
                          ),
                        ),
                        Text(
                          effectText(catalog, e.key, e.value),
                          style: const TextStyle(fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 7),
          const Text(
            'Buff contributions only. Gear and ability caps affect the final in-game values. EXP includes general Life EXP plus the activity-specific bonus.',
            style: TextStyle(color: muted, fontSize: 14, height: 1.5),
          ),
          if (!gathering)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'Gathering drop-rate and combat bonuses do not all apply equally to matchlock and sniper hunting. No loot or shot-damage multiplier is inferred.',
                style: TextStyle(color: gold, fontSize: 14, height: 1.5),
              ),
            ),
        ],
      ],
    );
  }

  Widget _compactSummary(BuildContext context, double exp, double mastery) {
    if (totals.isEmpty) return const SizedBox.shrink();
    final values = [
      ('exp', 'EXP', '+${numberText(exp)}%'),
      ('mastery', 'Mastery', '+${numberText(mastery)}'),
      (
        'drops',
        'Gathering drops',
        effectText(
          catalog,
          'gatheringItemDropPct',
          totals['gatheringItemDropPct'] ?? 0,
        ),
      ),
      (
        'weight',
        'Weight',
        effectText(catalog, 'maxWeight', totals['maxWeight'] ?? 0),
      ),
    ];
    final detailText = [
      ...totals.entries.map(
        (e) =>
            '${catalog.statLabel(e.key)} ${effectText(catalog, e.key, e.value)}',
      ),
      if (baseMastery > 0)
        'With your base mastery: ${numberText(baseMastery + mastery)}',
      'Raw buff bonuses; gear and in-game caps still apply.',
      'Ability levels cap at 5. EXP combines Life EXP and this activity’s EXP.',
      if (activity != 'gathering')
        'Gathering drop rate does not imply an equal hunting loot bonus.',
    ].join('\n');
    return Tooltip(
      message: detailText,
      textStyle: const TextStyle(color: ink, fontSize: 14, height: 1.4),
      decoration: BoxDecoration(
        color: context.glass.panel,
        border: Border.all(color: context.glass.line),
        borderRadius: BorderRadius.circular(9),
      ),
      padding: const EdgeInsets.all(12),
      excludeFromSemantics: true,
      child: Row(
        key: const ValueKey('compact-buff-summary'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth >= 600 ? 4 : 2;
                final width =
                    (constraints.maxWidth - (columns - 1) * 12) / columns;
                return Wrap(
                  spacing: 12,
                  runSpacing: 10,
                  children: values
                      .map(
                        (v) => SizedBox(
                          key: ValueKey('buff-stat-${v.$1}'),
                          width: width,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                v.$2,
                                style: const TextStyle(
                                  color: muted,
                                  fontSize: 14,
                                  height: 1.3,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                v.$3,
                                style: const TextStyle(
                                  color: accent,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  height: 1.3,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                      .toList(),
                );
              },
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            key: const ValueKey('buff-summary-details'),
            tooltip: 'All buff bonuses',
            onPressed: () => showDialog<void>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Buff bonuses'),
                content: SizedBox(
                  width: 430,
                  child: SingleChildScrollView(
                    child: BuffSummary(
                      catalog: catalog,
                      totals: totals,
                      activity: activity,
                      baseMastery: baseMastery,
                    ),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Close'),
                  ),
                ],
              ),
            ),
            icon: const Icon(Icons.info_outline, size: 20, color: muted),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 36, height: 36),
            visualDensity: VisualDensity.compact,
            style: IconButton.styleFrom(
              minimumSize: const Size(36, 36),
              maximumSize: const Size(36, 36),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ],
      ),
    );
  }
}
