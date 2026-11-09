import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/state/planner_application_controller.dart';
import '../../domain/catalog/item_name_presentation.dart';
import '../../domain/formatting/ingredient_group_labels.dart';
import '../../domain/formatting/planner_formatters.dart';
import '../../domain/market/recipe_craft_comparison.dart';
import '../../domain/market/shared_market_models.dart';
import '../../domain/models/catalog_models.dart';
import '../../domain/opportunities/opportunity_card_reading.dart';
import '../../domain/opportunities/opportunity_market_models.dart';
import '../../domain/planner/planner_models.dart';
import '../../domain/state/craft_completion.dart';
import '../../shared/overlays/anchored_popover.dart';
import '../../visual/components/sculpted_panel.dart';
import '../../visual/visual.dart';
import '../opportunities/opportunity_silver_amount.dart';
import '../shared/inventory_count_badge.dart';
import '../shared/item_name_copy_scope.dart';
import '../shared/market_count_badges.dart';
import '../shared/missing_count_badge.dart';
import '../shared/npc_source_marker.dart';
import 'planner_choice_market.dart';
import 'planner_shared.dart' show PlannerItemIcon;

typedef PanelAnchor = Widget Function(BuildContext, VoidCallback, bool);

class PlannerOwnedChoices extends StatelessWidget {
  const PlannerOwnedChoices({
    required this.controller,
    required this.parentName,
    required this.ingredient,
    required this.options,
    required this.selected,
    required this.anchorBuilder,
    this.beforeSelection,
    this.overlayScope = 'need',
    super.key,
  });
  final ModeFeatureController controller;
  final String parentName;
  final Ingredient ingredient;
  final List<String> options;
  final String selected;
  final PanelAnchor anchorBuilder;
  final ValueChanged<String>? beforeSelection;
  final String overlayScope;
  @override
  Widget build(BuildContext context) => AnchoredPopover(
    overlayId:
        'planner-owned-choices:$overlayScope:$parentName:${ingredient.name}',
    preferredWidth: double.infinity,
    contentSizedWidth: true,
    alignEnd: false,
    maximumHeight: 640,
    consumeOutsideTap: false,
    anchorBuilder: anchorBuilder,
    popoverBuilder: (context, close) => _OwnedChoicePanel(
      controller: controller,
      parentName: parentName,
      ingredient: ingredient,
      options: options,
      selected: selected,
      beforeSelection: beforeSelection,
      close: close,
    ),
  );
}

class _OwnedChoicePanel extends StatelessWidget {
  const _OwnedChoicePanel({
    required this.controller,
    required this.parentName,
    required this.ingredient,
    required this.options,
    required this.selected,
    required this.beforeSelection,
    required this.close,
  });
  final ModeFeatureController controller;
  final String parentName;
  final Ingredient ingredient;
  final List<String> options;
  final String selected;
  final ValueChanged<String>? beforeSelection;
  final VoidCallback close;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller.state,
    builder: (context, _) {
      final orderedOptions = [
        ...options.where(
          (option) => option.toLowerCase() == selected.toLowerCase(),
        ),
        ...options.where(
          (option) => option.toLowerCase() != selected.toLowerCase(),
        ),
      ];
      final values = [
        for (final option in orderedOptions)
          controller.previewSubstituteAmounts(
            parentName: parentName,
            ingredient: ingredient,
            selection: option,
          ),
      ];
      final group = ingredientGroupLabel(ingredient);

      final panel = PlannerChoiceMarket(
        controller: controller,
        resolveAcrossModes: true,
        names: values.map((value) => value.name).toList(),
        builder: (context, marketFor, now) => DefaultTextStyle(
          style: context.visualTheme.typography.body.copyWith(
            color: context.visualTheme.palette.text,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
          child: Builder(
            builder: (context) {
              final entries = [
                for (var i = 0; i < values.length; i++)
                  _ChoiceEntry(
                    controller,
                    orderedOptions[i],
                    values[i],
                    marketFor(values[i].name),
                    now,
                  ),
              ];
              final widths = _ChoiceWidths.measure(context, entries);
              final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
              Widget heading(
                String label, {
                bool left = false,
                double? width,
              }) => SizedBox(
                width: width,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  child: Text(
                    label,
                    textAlign: left ? TextAlign.left : TextAlign.center,
                    style: _choiceHeading(context),
                  ),
                ),
              );
              Widget cells({
                required Widget ingredient,
                required Widget inventory,
                required Widget market,
              }) => Row(
                children: [
                  SizedBox(width: widths.ingredient, child: ingredient),
                  SizedBox(width: 32 * scale),
                  SizedBox(
                    width: widths.inventory,
                    child: Center(child: inventory),
                  ),
                  SizedBox(width: 14 * scale),
                  SizedBox(width: widths.market, child: market),
                ],
              );
              return SizedBox(
                width: widths.total,
                child: SculptedPanel(
                  key: const ValueKey('planner-owned-choices-panel'),
                  title: group,
                  onClose: close,
                  body: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: widths.total - 2,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            child: cells(
                              ingredient: heading('Ingredient', left: true),
                              inventory: heading('Inventory'),
                              market: Align(
                                alignment: Alignment.centerLeft,
                                child: heading('Market', width: widths.stock),
                              ),
                            ),
                          ),
                          for (final (index, entry) in entries.indexed)
                            Semantics(
                              key: ValueKey('P13:${entry.option}'),
                              selected:
                                  entry.option.toLowerCase() ==
                                  selected.toLowerCase(),
                              button: true,
                              label:
                                  '${entry.value.name}, owned ${formatQuantity(entry.value.owned)}, missing ${formatQuantity(entry.value.missing)}',
                              child: InkWell(
                                key: ValueKey(
                                  'planner-owned-option:${entry.option}',
                                ),
                                onTap: controller.owner.mutationsFrozen
                                    ? null
                                    : () {
                                        beforeSelection?.call(entry.option);
                                        close();
                                        controller.selectSubstitute(
                                          parentName: parentName,
                                          ingredient: ingredient,
                                          selection: entry.option,
                                        );
                                      },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 12,
                                  ),
                                  decoration: BoxDecoration(
                                    color:
                                        entry.option.toLowerCase() ==
                                            selected.toLowerCase()
                                        ? context.visualTheme.palette.trim
                                              .withAlpha(55)
                                        : index.isEven
                                        ? context
                                              .visualTheme
                                              .palette
                                              .surfaceRaised
                                              .withAlpha(65)
                                        : context
                                              .visualTheme
                                              .palette
                                              .surfaceInset
                                              .withAlpha(30),
                                    border: Border(
                                      top: BorderSide(
                                        color: context.visualTheme.palette.trim
                                            .withAlpha(65),
                                      ),
                                    ),
                                  ),
                                  child: cells(
                                    ingredient: Row(
                                      children: [
                                        PlannerItemIcon(
                                          controller: controller,
                                          name: entry.value.name,
                                          size: widths.icon,
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  Text(
                                                    itemDisplayName(
                                                      entry.value.name,
                                                    ),
                                                    style: _choiceName(context),
                                                    maxLines: 1,
                                                    softWrap: false,
                                                  ),
                                                  if (entry.vendorHint !=
                                                      null) ...[
                                                    const SizedBox(width: 12),
                                                    NpcSourceMarker(
                                                      vendorHint:
                                                          entry.vendorHint,
                                                    ),
                                                  ],
                                                ],
                                              ),
                                              const SizedBox(height: 8),
                                              Row(
                                                children: [
                                                  MissingCountBadge(
                                                    key: ValueKey(
                                                      'choice-missing:${entry.value.name}',
                                                    ),
                                                    missing:
                                                        entry.value.missing,
                                                  ),
                                                  const SizedBox(width: 12),
                                                  Flexible(
                                                    child: Semantics(
                                                      label:
                                                          'Estimated cost to buy all ${formatQuantity(entry.value.needed)} ${entry.value.name}',
                                                      child: OpportunitySilverAmount(
                                                        value: entry.total,
                                                        wholeSilver: true,
                                                        showIcon: true,
                                                        textKey: ValueKey(
                                                          'choice-buy-all:${entry.value.name}',
                                                        ),
                                                        style: _choiceCost(
                                                          context,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                    inventory: InventoryCountBadge(
                                      key: ValueKey(
                                        'choice-owned:${entry.value.name}',
                                      ),
                                      owned: entry.value.owned,
                                      density: MarketBadgeDensity.comfortable,
                                    ),
                                    market: MarketCountBadges(
                                      stock: entry.stock.stock,
                                      preorders: entry.stock.preorders,
                                      showMarket: entry.showMarket,
                                      density: MarketBadgeDensity.comfortable,
                                      compactNumbers: true,
                                      singleLine: true,
                                      stockColumnWidth: widths.stock,
                                      stockColumnAlignment: Alignment.center,
                                      wrapKey: ValueKey(
                                        'choice-market:${entry.value.name}',
                                      ),
                                    ),
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
            },
          ),
        ),
      );
      return Semantics(
        container: true,
        explicitChildNodes: true,
        label: 'Substitute choices for ${ingredient.name}',
        child: panel,
      );
    },
  );
}

TextStyle _choiceName(BuildContext context) =>
    context.visualTheme.typography.body.copyWith(
      fontSize: 16,
      fontWeight: FontWeight.w600,
      color: context.visualTheme.palette.text,
    );
TextStyle _choiceHeading(BuildContext context) =>
    context.visualTheme.typography.meta.copyWith(
      fontSize: 13,
      fontWeight: FontWeight.w600,
      fontStyle: FontStyle.normal,
      color: context.visualTheme.palette.textMuted,
    );
TextStyle _choiceCost(BuildContext context) =>
    context.visualTheme.typography.body.copyWith(
      fontSize: 14,
      fontWeight: FontWeight.w600,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

class _ChoiceEntry {
  _ChoiceEntry(
    ModeFeatureController controller,
    this.option,
    this.value,
    OpportunityMarketItem? market,
    DateTime now,
  ) : vendorHint = npcVendorHint(controller, value.name),
      npc = controller.resolveItemSource(value.name).npcPrice > 0,
      showMarket =
          choiceMarketIdentity(
            controller,
            value.name,
            acrossModes: true,
          ).marketId !=
          null,
      stock = OpportunityCardStock(market, now, sharedMarketFreshness) {
    final price = npc
        ? controller.resolveItemSource(value.name).npcPrice
        : recipeMarketUnitPrice(market, now, sharedMarketFreshness);
    total = value.needed == 0
        ? 0.0
        : price == null
        ? null
        : price * value.needed;
  }
  final String option;
  final ({String name, double owned, double missing, double needed}) value;
  final bool npc, showMarket;
  final String? vendorHint;
  final OpportunityCardStock stock;
  late final double? total;
}

class _ChoiceWidths {
  const _ChoiceWidths(
    this.ingredient,
    this.inventory,
    this.stock,
    this.orders,
    this.scale,
    this.icon,
  );
  final double ingredient, inventory, stock, orders, scale, icon;
  double get market => stock + (orders > 0 ? 7 + orders : 0);
  double get total =>
      30 + ingredient + 32 * scale + inventory + 14 * scale + market;

  static _ChoiceWidths measure(
    BuildContext context,
    List<_ChoiceEntry> entries,
  ) {
    double textWidth(String text, TextStyle style) {
      final painter = TextPainter(
        text: TextSpan(
          text: text,
          style: DefaultTextStyle.of(context).style.merge(style),
        ),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
        maxLines: 1,
      )..layout();
      final width = painter.width.ceilToDouble();
      painter.dispose();
      return width;
    }

    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
    final icon = 42.0 * scale.clamp(1.0, 1.35);
    double marketWidth(int? stock, int? orders) => MarketCountBadges(
      stock: stock,
      preorders: orders,
      compactNumbers: true,
      density: MarketBadgeDensity.comfortable,
    ).preferredWidth(context);
    var label = textWidth('Ingredient', _choiceHeading(context));
    final npc = const NpcSourceMarker().preferredWidth(context);
    var inventory = textWidth('Inventory', _choiceHeading(context));
    var stock = textWidth('Market', _choiceHeading(context));
    var orders = 0.0;
    for (final entry in entries) {
      final missing = MissingCountBadge(
        missing: entry.value.missing,
      ).preferredWidth(context);
      final price =
          textWidth(
            entry.total == null
                ? '—'
                : formatCompactOpportunitySilver(entry.total!),
            _choiceCost(context),
          ) +
          26;
      label = math.max(
        label,
        icon +
            12 +
            math.max(
              textWidth(
                    itemDisplayName(entry.value.name),
                    _choiceName(context),
                  ) +
                  (entry.vendorHint != null ? 12 + npc : 0),
              missing + 12 + price,
            ),
      );
      inventory = math.max(
        inventory,
        InventoryCountBadge(
          owned: entry.value.owned,
          density: MarketBadgeDensity.comfortable,
        ).preferredWidth(context),
      );
      if (entry.showMarket) {
        stock = math.max(stock, marketWidth(entry.stock.stock, null));
        if ((entry.stock.preorders ?? 0) > 0) {
          orders = math.max(
            orders,
            marketWidth(0, entry.stock.preorders) - marketWidth(0, null) - 7,
          );
        }
      }
    }
    return _ChoiceWidths(
      label + 4,
      inventory + 2,
      stock + 2,
      orders,
      scale,
      icon,
    );
  }
}

Widget _meta(
  BuildContext context,
  String label, {
  bool right = false,
  double fontSize = 12,
}) => Text(
  label,
  textAlign: right ? TextAlign.right : TextAlign.left,
  style: context.visualTheme.typography.meta.copyWith(
    color: context.visualTheme.palette.textMuted,
    fontSize: fontSize,
    fontStyle: FontStyle.normal,
  ),
);

class PlannerShoppingList extends StatelessWidget {
  const PlannerShoppingList({
    required this.controller,
    required this.anchorBuilder,
    super.key,
  });
  final ModeFeatureController controller;
  final PanelAnchor anchorBuilder;
  @override
  Widget build(BuildContext context) => AnchoredPopover(
    overlayId: 'planner-shopping-list',
    preferredWidth: 486,
    alignEnd: false,
    maximumHeight: 680,
    consumeOutsideTap: true,
    anchorBuilder: anchorBuilder,
    popoverBuilder: (context, close) => AnimatedBuilder(
      animation: controller.plan,
      builder: (context, _) {
        final groups = shoppingGroups(controller);
        return SculptedPanel(
          key: const ValueKey('planner-shopping-list-panel'),
          title: 'Shopping list',
          onClose: close,
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 7, 14, 7),
                child: _meta(context, 'Missing', right: true),
              ),
              if (groups.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('Nothing missing'),
                ),
              for (final group in groups.entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: SculptedRail(
                    label: group.key,
                    centerLabel: true,
                    child: Column(
                      children: [
                        for (final row in group.value)
                          _MaterialRow(
                            controller: controller,
                            name: row.name,
                            amount: formatQuantity(row.missing),
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          footer: Align(
            alignment: Alignment.centerRight,
            child: AppButton.label(
              'Copy list',
              key: const ValueKey('planner-shopping-copy'),
              onPressed: groups.isEmpty
                  ? null
                  : () async {
                      final text = shoppingText(groups);
                      final copy = ItemNameCopyScope.textActionOf(context);
                      if (copy != null) {
                        await copy(text, 'Shopping list copied');
                      } else {
                        await Clipboard.setData(ClipboardData(text: text));
                      }
                    },
            ),
          ),
        );
      },
    ),
  );
}

/// This is a projection of Need First, not a second shopping calculation.
Map<String, List<MissingMaterial>> shoppingGroups(
  ModeFeatureController controller,
) {
  final npc = <MissingMaterial>[];
  final other = <MissingMaterial>[];
  for (final row in controller.plan.value.missing.where(
    (row) => row.missing > 0,
  )) {
    final source = controller.resolveItemSource(row.name);
    (source.npcPrice > 0 ? npc : other).add(row);
  }
  return {
    if (npc.isNotEmpty) 'NPC': npc,
    if (other.isNotEmpty) 'Market / gather': other,
  };
}

String shoppingText(Map<String, List<MissingMaterial>> groups) => groups.entries
    .map(
      (group) =>
          '${group.key}\n${group.value.map((row) => '${row.name} ×${formatQuantity(row.missing)}').join('\n')}',
    )
    .join('\n\n');

class PlannerUndoReview extends StatelessWidget {
  const PlannerUndoReview({
    required this.controller,
    required this.anchorBuilder,
    required this.onConflict,
    super.key,
  });
  final ModeFeatureController controller;
  final PanelAnchor anchorBuilder;
  final VoidCallback onConflict;
  @override
  Widget build(BuildContext context) => AnchoredPopover(
    overlayId: 'planner-undo-review',
    preferredWidth: 480,
    alignEnd: false,
    maximumHeight: 680,
    consumeOutsideTap: true,
    anchorBuilder: anchorBuilder,
    popoverBuilder: (context, close) => _UndoPanel(
      controller: controller,
      review: controller.completionReview,
      close: close,
      onConflict: onConflict,
    ),
  );
}

class _UndoPanel extends StatefulWidget {
  const _UndoPanel({
    required this.controller,
    required this.review,
    required this.close,
    required this.onConflict,
  });
  final ModeFeatureController controller;
  final CraftCompletionReview? review;
  final VoidCallback close;
  final VoidCallback onConflict;
  @override
  State<_UndoPanel> createState() => _UndoPanelState();
}

class _UndoPanelState extends State<_UndoPanel> {
  // Freeze what was shown; a second completion must never be undone invisibly.
  late final review = widget.review;
  @override
  Widget build(BuildContext context) => SculptedPanel(
    key: const ValueKey('planner-undo-review-panel'),
    title: 'Undo last craft',
    onClose: widget.close,
    body: Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        children: [
          if (review == null)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Nothing to undo'),
            ),
          if (review != null) ...[
            if (review!.remove.isNotEmpty)
              _group('Remove', review!.remove, false),
            if (review!.remove.isNotEmpty && review!.restore.isNotEmpty)
              const SizedBox(height: 10),
            if (review!.restore.isNotEmpty)
              _group('Return', review!.restore, true),
          ],
        ],
      ),
    ),
    footer: Align(
      alignment: Alignment.centerRight,
      child: AppButton.label(
        'Undo this craft',
        key: const ValueKey('planner-undo-confirm'),
        onPressed: review == null
            ? null
            : () {
                final undone = widget.controller.undoCompletion(
                  expectedReceipt: review!.token,
                );
                widget.close();
                if (!undone) widget.onConflict();
              },
      ),
    ),
  );
  Widget _group(String label, Map<String, double> rows, bool positive) =>
      SculptedRail(
        label: label,
        width: 78,
        child: Column(
          children: [
            for (final row in rows.entries)
              _MaterialRow(
                controller: widget.controller,
                name: row.key,
                amount: '${positive ? '+' : '−'}${formatQuantity(row.value)}',
                positive: positive,
              ),
          ],
        ),
      );
}

class _MaterialRow extends StatelessWidget {
  const _MaterialRow({
    required this.controller,
    required this.name,
    required this.amount,
    this.positive,
  });
  final ModeFeatureController controller;
  final String name;
  final String amount;
  final bool? positive;
  @override
  Widget build(BuildContext context) {
    final p = context.visualTheme.palette;
    final figure = Text(
      amount,
      textAlign: TextAlign.right,
      style: TextStyle(
        color: positive == null
            ? p.text
            : positive!
            ? Color.lerp(p.success, p.text, .55)
            : Color.lerp(p.danger, p.text, .4),
      ),
    );
    return Container(
      key: ValueKey('planner-review-item:$name'),
      constraints: const BoxConstraints(minHeight: 48),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        children: [
          PlannerItemIcon(controller: controller, name: name, size: 32),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: p.trim.withValues(alpha: .28)),
                ),
              ),
              child: MediaQuery.textScalerOf(context).scale(14) > 21
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [Text(itemDisplayName(name)), figure],
                    )
                  : Row(
                      children: [
                        Expanded(child: Text(itemDisplayName(name))),
                        const SizedBox(width: 12),
                        figure,
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
