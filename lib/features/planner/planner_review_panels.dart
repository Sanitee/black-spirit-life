import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/state/planner_application_controller.dart';
import '../../domain/catalog/item_name_presentation.dart';
import '../../domain/formatting/compact_quantity.dart';
import '../../domain/formatting/ingredient_group_labels.dart';
import '../../domain/formatting/planner_formatters.dart';
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
import '../shared/item_name_copy_scope.dart';
import '../shared/market_count_badges.dart';
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
    preferredWidth: 500,
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
      final ownedWidth = _choiceQuantityWidth(
        context,
        values.map((value) => value.owned),
        68,
      );
      final missingWidth = _choiceQuantityWidth(
        context,
        values.map((value) => value.missing),
        76,
      );
      final panel = PlannerChoiceMarket(
        controller: controller,
        resolveAcrossModes: true,
        names: values.map((value) => value.name).toList(),
        builder: (context, marketFor, now) => SculptedPanel(
          key: const ValueKey('planner-owned-choices-panel'),
          title: group,
          onClose: close,
          body: LayoutBuilder(
            builder: (context, constraints) {
              final narrow =
                  constraints.maxWidth -
                          (ownedWidth - 68) -
                          (missingWidth - 76) <
                      360 ||
                  MediaQuery.textScalerOf(context).scale(14) > 21;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!narrow)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 9, 14, 9),
                      child: Row(
                        children: [
                          Expanded(
                            child: _meta(context, 'Ingredient', fontSize: 13),
                          ),
                          SizedBox(
                            width: ownedWidth,
                            child: _meta(
                              context,
                              'Owned',
                              right: true,
                              fontSize: 13,
                            ),
                          ),
                          SizedBox(
                            width: missingWidth,
                            child: _meta(
                              context,
                              'Missing',
                              right: true,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  for (final (index, option) in orderedOptions.indexed)
                    _ChoiceRow(
                      controller: controller,
                      option: option,
                      value: values[index],
                      market: marketFor(values[index].name),
                      now: now,
                      selected: option.toLowerCase() == selected.toLowerCase(),
                      narrow: narrow,
                      ownedWidth: ownedWidth,
                      missingWidth: missingWidth,
                      onTap: controller.owner.mutationsFrozen
                          ? null
                          : () {
                              beforeSelection?.call(option);
                              close();
                              controller.selectSubstitute(
                                parentName: parentName,
                                ingredient: ingredient,
                                selection: option,
                              );
                            },
                    ),
                ],
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

TextStyle _choiceQuantityStyle(BuildContext context) =>
    context.visualTheme.typography.meta.copyWith(
      fontSize: 16,
      fontWeight: FontWeight.w600,
      fontStyle: FontStyle.normal,
      fontFeatures: const [FontFeature.tabularFigures()],
      color: context.visualTheme.palette.text,
    );

double _choiceQuantityWidth(
  BuildContext context,
  Iterable<double> values,
  double minimum,
) {
  var width = minimum;
  final painter = TextPainter(
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
    maxLines: 1,
  );
  for (final value in values) {
    painter.text = TextSpan(
      text: formatCompactQuantity(value),
      style: _choiceQuantityStyle(context),
    );
    painter.layout();
    final needed = painter.width.ceilToDouble() + 12;
    if (needed > width) width = needed;
  }
  painter.dispose();
  return width;
}

class _ChoiceRow extends StatelessWidget {
  const _ChoiceRow({
    required this.controller,
    required this.option,
    required this.value,
    required this.selected,
    required this.narrow,
    required this.ownedWidth,
    required this.missingWidth,
    required this.onTap,
    required this.market,
    required this.now,
  });
  final ModeFeatureController controller;
  final String option;
  final ({String name, double owned, double missing, double needed}) value;
  final OpportunityMarketItem? market;
  final DateTime now;
  final bool selected;
  final bool narrow;
  final double ownedWidth, missingWidth;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final spec = context.visualTheme;
    final p = spec.palette;
    final nameStyle = spec.typography.body.copyWith(
      fontSize: 16,
      fontWeight: FontWeight.w600,
      color: p.text,
    );
    // Retain the Planner's typography; only the displayed number is compact.
    final quantityStyle = _choiceQuantityStyle(context);
    final source = controller.resolveItemSource(value.name);
    final npc = source.npcPrice > 0;
    final stock = OpportunityCardStock(market, now, sharedMarketFreshness);
    final price = npc
        ? source.npcPrice
        : market?.quoteIsFresh(now, sharedMarketFreshness) == true &&
              market?.unlisted != true
        ? market!.basePrice!.toDouble()
        : null;
    final total = value.needed == 0
        ? 0.0
        : price == null
        ? null
        : price * value.needed;
    final marketLine = Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        runSpacing: 6,
        children: [
          MarketCountBadges(
            stock: stock.stock,
            preorders: stock.preorders,
            npc: npc,
            showMarket:
                choiceMarketIdentity(
                  controller,
                  value.name,
                  acrossModes: true,
                ).marketId !=
                null,
            density: MarketBadgeDensity.comfortable,
            wrapKey: ValueKey('choice-market:${value.name}'),
          ),
          Semantics(
            label:
                'Estimated cost to buy all ${formatQuantity(value.needed)} ${value.name}',
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ExcludeSemantics(
                  child: PlannerItemIcon(
                    controller: controller,
                    name: 'Silver',
                    size: 21,
                    showFrame: false,
                  ),
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: OpportunitySilverAmount(
                    value: total,
                    wholeSilver: true,
                    textKey: ValueKey('choice-buy-all:${value.name}'),
                    style: context.visualTheme.typography.body.copyWith(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
    final name = Text(itemDisplayName(value.name), style: nameStyle);
    final missing = Text(
      formatCompactQuantity(value.missing),
      key: ValueKey('choice-missing:${value.name}'),
      maxLines: 1,
      softWrap: false,
      textAlign: TextAlign.right,
      style: quantityStyle.copyWith(
        color: value.missing == 0 ? Color.lerp(p.success, p.text, .55) : p.text,
      ),
    );
    final owned = Text(
      formatCompactQuantity(value.owned),
      key: ValueKey('choice-owned:${value.name}'),
      maxLines: 1,
      softWrap: false,
      textAlign: TextAlign.right,
      style: quantityStyle,
    );
    return Semantics(
      key: ValueKey('P13:$option'),
      selected: selected,
      button: true,
      label:
          '${value.name}, owned ${formatQuantity(value.owned)}, missing ${formatQuantity(value.missing)}',
      child: InkWell(
        key: ValueKey('planner-owned-option:$option'),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          decoration: BoxDecoration(
            color: selected
                ? Color.alphaBlend(p.primary.withValues(alpha: .24), p.surface)
                : null,
            border: Border(
              left: BorderSide(
                width: 2,
                color: selected ? p.trimBright : Colors.transparent,
              ),
            ),
          ),
          padding: const EdgeInsets.only(left: 12, right: 14),
          child: Row(
            children: [
              PlannerItemIcon(
                controller: controller,
                name: value.name,
                size: 36,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: p.trim.withValues(alpha: .28)),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      narrow
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                name,
                                const SizedBox(height: 6),
                                Wrap(
                                  spacing: 16,
                                  runSpacing: 4,
                                  children: [
                                    Text(
                                      'Owned ${formatCompactQuantity(value.owned)}',
                                      key: ValueKey(
                                        'choice-owned:${value.name}',
                                      ),
                                      maxLines: 1,
                                      softWrap: false,
                                      style: quantityStyle,
                                    ),
                                    Text(
                                      'Missing ${formatCompactQuantity(value.missing)}',
                                      key: ValueKey(
                                        'choice-missing:${value.name}',
                                      ),
                                      maxLines: 1,
                                      softWrap: false,
                                      style: quantityStyle,
                                    ),
                                  ],
                                ),
                              ],
                            )
                          : Row(
                              children: [
                                Expanded(child: name),
                                SizedBox(width: ownedWidth, child: owned),
                                SizedBox(width: missingWidth, child: missing),
                              ],
                            ),
                      marketLine,
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

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
