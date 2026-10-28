part of 'opportunities_workspace.dart';

/// The selected material is already owned: compare its two uses, not the
/// ordinary buy-all-inputs profit. Values come from the current inspected quote.
class _BestUseDetailsSummary extends StatefulWidget {
  const _BestUseDetailsSummary({
    required this.controller,
    required this.inspection,
    required this.itemName,
    required this.comparison,
  });

  final OpportunitiesController controller;
  final OpportunityRecipeInspection inspection;
  final String itemName;
  final OpportunityBestUseComparison? comparison;

  @override
  State<_BestUseDetailsSummary> createState() => _BestUseDetailsSummaryState();
}

class _BestUseDetailsSummaryState extends State<_BestUseDetailsSummary> {
  bool _showTotals = false;

  @override
  Widget build(BuildContext context) {
    final spec = context.visualTheme;
    final comparison = widget.comparison;
    final quote = widget.inspection.quote;
    final difference = comparison?.profitLossPerUnit;
    return OpportunitySurface(
      key: const ValueKey('best-use-detail-summary'),
      role: AppSurfaceRole.panel,
      padding: const EdgeInsets.all(14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _marketDepthStatus(context, widget.controller),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 16,
            runSpacing: 8,
            children: [
              Text(
                comparison == null
                    ? 'No ${widget.itemName} in this recipe'
                    : 'Per 1 ${widget.itemName} · after tax',
                key: const ValueKey('best-use-unit-context'),
                style: spec.typography.label,
              ),
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  Semantics(
                    expanded: _showTotals,
                    child: OpportunityButton(
                      key: const ValueKey('best-use-batch-totals'),
                      compact: true,
                      semanticLabel: 'Batch totals for ${quote.crafts} crafts',
                      onPressed: () =>
                          setState(() => _showTotals = !_showTotals),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Batch totals · ${quote.crafts} ${quote.crafts == 1 ? 'craft' : 'crafts'}',
                          ),
                          const SizedBox(width: 6),
                          Icon(
                            _showTotals ? Icons.expand_less : Icons.expand_more,
                            size: 18,
                          ),
                        ],
                      ),
                    ),
                  ),
                  _market(
                    context,
                    quote.outputMarket,
                    widget.controller.clock(),
                    maxAge: widget.controller.cachedMarketMaxAge,
                    onDetails: () => _showMarketDetails(context),
                  ),
                  _info(context, 'About this comparison', [
                    'Craft & sell return is the sale after tax minus the cost of the other ingredients. The ${widget.itemName} you already have is not bought again.',
                    'Profit/Loss is that return minus selling the same ${widget.itemName} raw, divided by the quantity used. Positive means crafting earns more; negative means selling it raw earns more.',
                    'Market prices are estimates, not guaranteed sales. A dash means a required price or the selected material is unavailable.',
                  ]),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          _BestUseReadouts(
            children: [
              _readout(
                context,
                'Profit/Loss',
                difference,
                'best-use-profit-loss',
                estimated: comparison?.isEstimated ?? false,
                prominent: true,
                color: difference == null || difference == 0
                    ? spec.palette.textMuted
                    : difference > 0
                    ? spec.palette.success
                    : spec.palette.danger,
              ),
              _readout(
                context,
                'Raw ingredient sale',
                comparison?.rawSalePerUnit,
                'best-use-raw-sale',
              ),
              _readout(
                context,
                'Craft & sell return',
                comparison?.craftingReturnPerUnit,
                'best-use-craft-return',
                estimated: comparison?.isEstimated ?? false,
              ),
            ],
          ),
          if (_showTotals) ...[
            const SizedBox(height: 10),
            const OpportunityReadoutRule(),
            _BestUseReadouts(
              children: [
                _readout(
                  context,
                  'Sale after tax',
                  quote.listingRevenue,
                  'best-use-total-sale',
                ),
                _readout(
                  context,
                  'Other ingredients',
                  comparison?.otherInputCost,
                  'best-use-total-other-cost',
                  estimated: comparison?.isEstimated ?? false,
                ),
                _readout(
                  context,
                  'Sell ${widget.itemName}',
                  comparison?.rawIngredientSale,
                  'best-use-total-raw-sale',
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _readout(
    BuildContext context,
    String label,
    double? value,
    String key, {
    bool prominent = false,
    bool estimated = false,
    Color? color,
  }) {
    final spec = context.visualTheme;
    return Column(
      key: ValueKey(key),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: spec.typography.meta),
        const SizedBox(height: 4),
        OpportunitySilverAmount(
          value: value,
          estimated: estimated,
          showPlus: prominent,
          style: spec.typography.body.copyWith(
            fontSize: prominent ? 24 : 20,
            fontWeight: prominent ? FontWeight.w700 : FontWeight.w600,
            color: color == null
                ? spec.palette.text
                : OpportunitiesVisualSpec.readableValueColor(spec, color),
          ),
        ),
      ],
    );
  }

  void _showMarketDetails(BuildContext context) {
    final controller = widget.controller;
    final inspection = widget.inspection;
    _withMarketDepth(
      controller,
      [?inspection.quote.outputMarket?.itemId],
      () => _dialog(
        context,
        'Market details',
        (context) => AnimatedBuilder(
          animation: controller,
          builder: (context, _) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _marketDepthStatus(context, controller),
              _bookDetails(
                context,
                controller.outputMarketFor(
                  inspection.itemName,
                  mode: inspection.sourceMode,
                ),
                controller.clock(),
                maxAge: controller.cachedMarketMaxAge,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BestUseReadouts extends StatelessWidget {
  const _BestUseReadouts({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
      final columns = constraints.maxWidth >= 620 * scale ? 3 : 1;
      final width = (constraints.maxWidth - (columns - 1) * 20) / columns;
      return Wrap(
        spacing: 20,
        runSpacing: 12,
        children: [
          for (final child in children) SizedBox(width: width, child: child),
        ],
      );
    },
  );
}
