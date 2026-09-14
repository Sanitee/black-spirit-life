part of 'opportunities_workspace.dart';

class _BestUsePane extends StatelessWidget {
  const _BestUsePane({required this.controller});

  final OpportunitiesController controller;

  @override
  Widget build(BuildContext context) {
    if (controller.preferences.section != 'best-use') {
      return const SizedBox.shrink();
    }
    final spec = context.visualTheme;
    final p = controller.preferences;
    final rows = controller.visibleBestUseQuotes;
    return _cardList(
      context,
      count: rows.length,
      keyName: 'best-use-opportunities',
      minimumCardWidth: 400,
      maximumCardWidth: rows.length <= 2 ? 480 : 560,
      maximumColumns: 4,
      header: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _BestUseToolbar(controller: controller),
            const SizedBox(height: 8),
            if (p.bestUseItem.isNotEmpty)
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 16,
                runSpacing: 8,
                children: [
                  Text(
                    '${rows.length} ${rows.length == 1 ? 'recipe' : 'recipes'}'
                    '${p.demandOnly && controller.bestUseDemandPendingCount > 0 ? ' · ${controller.bestUseDemandPendingCount} demand unchecked' : ''}',
                    style: spec.typography.meta,
                  ),
                  Text(
                    'Compared with selling ${p.bestUseItem} after tax',
                    style: spec.typography.meta,
                  ),
                ],
              ),
            if (rows.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 28),
                child: controller.calculatingBestUse
                    ? const Center(child: CircularProgressIndicator())
                    : _empty(
                        context,
                        p.bestUseItem.isEmpty ? 'Choose an item' : 'No matches',
                        p.bestUseItem.isEmpty
                            ? 'Find its best direct crafting uses.'
                            : p.demandOnly &&
                                  controller.bestUseDemandPendingCount > 0
                            ? 'Demand has not been checked for all recipes.'
                            : 'Change the item or filters.',
                      ),
              ),
          ],
        ),
      ),
      builder: (index) => _CraftCard(
        controller: controller,
        quote: rows[index].quote,
        bestUse: rows[index],
      ),
    );
  }
}

class _BestUseToolbar extends StatelessWidget {
  const _BestUseToolbar({required this.controller});

  final OpportunitiesController controller;

  @override
  Widget build(BuildContext context) {
    final spec = context.visualTheme;
    final p = controller.preferences;
    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
    return LayoutBuilder(
      builder: (context, constraints) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 16,
            runSpacing: 12,
            children: [
              SizedBox(
                width: math.min(480 * scale, constraints.maxWidth),
                child: Row(
                  children: [
                    Text('Best use for', style: spec.typography.button),
                    const SizedBox(width: 12),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, fieldConstraints) =>
                            PlannerTargetChooser(
                              controller: controller.modeController,
                              target: PlannerCommandTarget(
                                value: p.bestUseItem,
                                names: controller.bestUseItems,
                                onSelected: (name) {
                                  final selected = controller.bestUseItems
                                      .where(
                                        (item) =>
                                            item.toLowerCase() ==
                                            name.trim().toLowerCase(),
                                      )
                                      .firstOrNull;
                                  if (selected == null) return false;
                                  controller.selectBestUseItem(selected);
                                  return true;
                                },
                              ),
                              actionKey: const ValueKey('best-use-item'),
                              semanticLabel: 'Best use for item',
                              hintText: 'Find an item',
                              emptyText: 'No matching items',
                              controlHeight: math.max(40, 24 * scale + 16),
                              popupWidth: fieldConstraints.maxWidth,
                              popupMaxHeight:
                                  (MediaQuery.sizeOf(context).height - 400)
                                      .clamp(120, 420)
                                      .toDouble(),
                              fieldBuilder:
                                  (
                                    context,
                                    text,
                                    focus,
                                    onChanged,
                                    onTap,
                                    onSubmitted,
                                    onKeyEvent,
                                  ) => OpportunityTextField(
                                    flat: true,
                                    controller: text,
                                    focusNode: focus,
                                    semanticLabel: 'Best use for item',
                                    hintText: 'Find an item',
                                    textStyle: spec.typography.button,
                                    onChanged: onChanged,
                                    onTap: onTap,
                                    onSubmitted: onSubmitted,
                                    onKeyEvent: onKeyEvent,
                                    suffixIcon: const Icon(
                                      Icons.expand_more,
                                      size: 20,
                                    ),
                                  ),
                              optionBuilder:
                                  (
                                    context,
                                    name,
                                    selected,
                                    onSelected,
                                  ) => OpportunityButton(
                                    selected: selected,
                                    role: AppButtonRole.infoChip,
                                    minimumSize: const Size.fromHeight(48),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 8,
                                    ),
                                    semanticLabel: 'Select $name',
                                    onPressed: onSelected,
                                    child: Row(
                                      children: [
                                        ModeItemIcon(
                                          catalogRepository: controller.catalog,
                                          controller: controller.modeController,
                                          name: name,
                                          size: 36,
                                          searchAcrossModes: true,
                                          showFrame: false,
                                          fit: BoxFit.contain,
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Text(
                                            name,
                                            style: spec.typography.body
                                                .copyWith(
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                              itemIconBuilder: (context, name) => ModeItemIcon(
                                catalogRepository: controller.catalog,
                                controller: controller.modeController,
                                name: name,
                                size: 36,
                                searchAcrossModes: true,
                                showFrame: false,
                                fit: BoxFit.contain,
                              ),
                            ),
                      ),
                    ),
                  ],
                ),
              ),
              _CraftSortControl(controller: controller),
            ],
          ),
          const SizedBox(height: 12),
          DecoratedBox(
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: spec.palette.trim.withAlpha(70)),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 16,
                runSpacing: 12,
                children: [
                  Text(
                    'Cooking · Alchemy · Processing',
                    style: spec.typography.meta,
                  ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _CraftFilterPill(
                        controlKey: const ValueKey('best-use-out-of-stock'),
                        label: 'Out of stock',
                        selected: p.demandOnly,
                        onSelected: (value) =>
                            controller.change((p) => p.demandOnly = value),
                      ),
                      _CraftFilterPill(
                        controlKey: const ValueKey(
                          'best-use-ingredients-available',
                        ),
                        label: 'Ingredients available',
                        selected: p.readyOnly,
                        onSelected: (value) =>
                            controller.change((p) => p.readyOnly = value),
                      ),
                      _CraftFilterPill(
                        controlKey: const ValueKey('best-use-profitable'),
                        label: 'Profitable',
                        selected: p.profitableOnly,
                        onSelected: (value) =>
                            controller.change((p) => p.profitableOnly = value),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
