part of 'recipe_book_item_info_view.dart';

// Only replace the generic availability qualifier. Mixed sources, restrictions,
// prohibitions and legacy notes must retain their exact meaning.
bool _isGenericMarketSource(String value) => const {
  'central market',
  'central market · when in stock',
  'central market · when listed',
}.contains(value.trim().toLowerCase().replaceFirst(RegExp(r'\.$'), ''));

bool _hasMarketPurchaseSource(String value) {
  if (_isGenericMarketSource(value)) return true;
  // Keep compound source prose verbatim, but accompany a positive purchase
  // statement with the same badge. Mentions in prohibitions are not sources.
  if (RegExp(
    r'\b(not|cannot|never|unavailable|no longer)\b',
    caseSensitive: false,
  ).hasMatch(value)) {
    return false;
  }
  return RegExp(
    r'\b(buy\b[^.!?\n]*\b(on|through|from) the central market|sold on the central market|or the central market instead of)\b',
    caseSensitive: false,
  ).hasMatch(value);
}

/// One acquisition section for clicked, hovered, passive and inline references.
class _AcquisitionSection extends StatelessWidget {
  const _AcquisitionSection({
    required this.controller,
    required this.mode,
    required this.name,
    required this.info,
    required this.style,
    this.leadingSpacing = 20,
  });
  final RecipeBookController controller;
  final CraftMode mode;
  final String name;
  final RecipeBookItemInfo info;
  final TextStyle style;
  final double leadingSpacing;

  @override
  Widget build(BuildContext context) {
    final modeController = controller.modeController.owner.modes[mode]!;
    final values = info.acquisitionNotes
        .where((s) => s.trim().isNotEmpty)
        .toList();
    if (values.isEmpty) return const SizedBox.shrink();
    if (info.isTemporarilyArchived || !values.any(_hasMarketPurchaseSource)) {
      return _InfoSection(
        title: 'How to Obtain',
        values: values,
        style: style,
        leadingSpacing: leadingSpacing,
      );
    }
    return PlannerChoiceMarket(
      controller: modeController,
      names: [name],
      resolveAcrossModes: true,
      preferNpcSources: false,
      builder: (context, marketFor, now) {
        final market = marketFor(name);
        final stock = market?.stockFor(now, sharedMarketFreshness);
        final preorders =
            market?.bookIsFresh(now, sharedMarketFreshness) == true
            ? market?.preorderCount
            : null;
        return Padding(
          padding: EdgeInsets.only(
            top: _itemInfoSpacing(context, leadingSpacing),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _InfoSectionHeading(
                title: 'How to Obtain',
                spec: context.visualTheme,
              ),
              SizedBox(height: _itemInfoSpacing(context, 8)),
              for (final value in values)
                if (_hasMarketPurchaseSource(value))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Wrap(
                      spacing: 12,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        // Keep the label's natural width so availability follows
                        // it, rather than filling an unrelated right-side rail.
                        // Longer restrictions retain their bullets and wrap at
                        // the available width; the badges then flow beneath.
                        IntrinsicWidth(
                          child: _InfoBullet(
                            value: _isGenericMarketSource(value)
                                ? 'Central Market'
                                : value,
                            style: style,
                          ),
                        ),
                        SourceAvailabilityBadges(
                          key: ValueKey('reference-acquisition-stock:$name'),
                          stock: stock,
                          preorders: preorders,
                        ),
                      ],
                    ),
                  )
                else
                  _InfoBullet(value: value, style: style),
            ],
          ),
        );
      },
    );
  }
}
