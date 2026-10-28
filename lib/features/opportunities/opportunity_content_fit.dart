part of 'opportunities_workspace.dart';

/// Bounded per-workspace shaping cache; changing themes, accessibility text or
/// direction naturally uses a different key. No global cache survives disposal.
class _OpportunityFitCache {
  final _sizes = <(String, TextStyle, TextScaler, TextDirection), Size>{};

  double measure(
    BuildContext context,
    String value,
    double fontSize,
    FontWeight weight,
  ) {
    final style = context.visualTheme.typography.body.copyWith(
      fontSize: fontSize,
      fontWeight: weight,
    );
    return measureStyled(context, value, style).width;
  }

  Size measureStyled(BuildContext context, String value, TextStyle style) {
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    final key = (value, style, scaler, direction);
    final cached = _sizes[key];
    if (cached != null) return cached;
    final painter = TextPainter(
      text: TextSpan(text: value, style: style),
      textScaler: scaler,
      textDirection: direction,
    )..layout();
    final size = painter.size;
    painter.dispose();
    if (_sizes.length >= 2048) _sizes.remove(_sizes.keys.first);
    _sizes[key] = size;
    return size;
  }
}

/// Measure existing readouts once per data/layout update, outside the live
/// preview builder. This preserves wrap/header branches without intrinsic passes.
double _opportunitiesMaximum(
  BuildContext context,
  OpportunitiesController controller,
  Size size,
  _OpportunityFitCache cache, {
  required bool rail,
}) {
  final text = MediaQuery.textScalerOf(context).scale(14) / 14;
  final p = controller.preferences;
  final breakpoints = <double>[];
  double measure(String value, double fontSize, FontWeight weight) =>
      cache.measure(context, value, fontSize, weight);
  final now = controller.clock();
  double stockWidth(OpportunityMarketItem? market) {
    final badge = _market(
      context,
      market,
      now,
      maxAge: controller.cachedMarketMaxAge,
    );
    return measure('Stock ${badge.text}', 16, FontWeight.w700).ceilToDouble() +
        18;
  }

  if (p.section == 'best-use') {
    breakpoints.add(280 * text);
    for (final use in controller.visibleBestUseQuotes) {
      breakpoints.add(
        stockWidth(
              controller.outputMarketFor(use.quote.recipeName, mode: use.mode),
            ) +
            122 +
            150 * text,
      );
    }
  } else if (p.section == 'exchanges') {
    final columns = (size.width / (420 * text.clamp(1, 2))).floor().clamp(1, 3);
    final inner =
        math.min(
          560 * text.clamp(1, 2),
          (size.width - (columns - 1) * 12) / columns,
        ) -
        28;
    for (final quote in controller.exchangeQuotes) {
      final display = quote.displayQuote;
      final reward = quote.route.rewards.length == 1
          ? quote.route.rewards.single.item
          : null;
      final market = reward == null
          ? null
          : controller.market.items['${reward.id}'];
      final hasStock =
          reward?.marketable == true &&
          market?.stockFor(now, controller.cachedMarketMaxAge) != null;
      final hasValue = _showExchangeValue(quote);
      final count = (hasValue ? 2 : 0) + (hasStock ? 1 : 0);
      if (count == 0) continue;
      var minimum = 90 * text;
      if (hasValue) {
        minimum = math.max(
          minimum,
          measure(
                _silver(display.netProceeds),
                22,
                FontWeight.w600,
              ).ceilToDouble() +
              2,
        );
        minimum = math.max(
          minimum,
          measure(
                _silver(display.valuePerCurrency),
                15,
                FontWeight.w500,
              ).ceilToDouble() +
              2,
        );
      }
      if (hasStock) minimum = math.max(minimum, stockWidth(market));
      final metricColumns = ((inner + 12) / (minimum + 12)).floor().clamp(
        1,
        count,
      );
      if (metricColumns > 1) {
        breakpoints.add(metricColumns * (minimum + 12) - 12);
      }
    }
  } else {
    // Compact headers wrap; there is no wide financial row to preserve.
    breakpoints.add(240 * text);
  }
  return opportunitiesContentMaximumScale(
    size: size,
    section: p.section,
    textScale: text,
    cardBreakpoints: breakpoints,
    paneBreakpoints: _opportunityToolbarBreakpoints(
      context,
      controller,
      size.width,
      cache,
      rail: rail,
    ),
  );
}

Iterable<double> _opportunityToolbarBreakpoints(
  BuildContext context,
  OpportunitiesController controller,
  double width,
  _OpportunityFitCache cache, {
  required bool rail,
}) sync* {
  final p = controller.preferences;
  if (p.section == 'exchanges') return;
  final typography = context.visualTheme.typography;
  final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
  double button(String value) =>
      cache.measureStyled(context, value, typography.button).width;
  double chip(String value) {
    final label = cache.measureStyled(context, value, typography.button);
    // FilterChip's avatar is a square with the label/content height; the
    // explicit label-left inset is4 and horizontal chip padding is20.
    return label.width + math.max(16, label.height) + 24;
  }

  double run(List<double> children, double available, double gap) =>
      opportunitiesWrapMinimumWidth(
        children,
        available: available,
        spacing: gap,
      );
  final active = controller.activeCraftSort;
  var sortWidth = button('Demand') + button('Profit') + 48 + 12;
  if (active != 'exp') sortWidth += 5 + button(p.craftAscending ? '↑' : '↓');
  if (p.section != 'best-use') {
    sortWidth +=
        button('EXP') +
        24 +
        (active == 'exp' ? math.max(32, button('↓') + 16) : 0);
  }
  if (p.section == 'best-use') {
    yield run(
      [math.min(480 * scale, width), if (!rail) math.min(sortWidth, width)],
      width,
      16,
    );
    final filters = run(
      [chip('Out of stock'), chip('Ingredients available'), chip('Profitable')],
      width,
      8,
    );
    yield filters;
    final modes = cache
        .measureStyled(
          context,
          'Cooking · Alchemy · Processing',
          typography.meta,
        )
        .width;
    yield run([modes, filters], width, 16);
    return;
  }
  final suffix = [if (p.readyOnly) 'available', if (p.useInventory) 'owned'];
  final ingredients =
      button('Ingredients${suffix.isEmpty ? '' : ' · ${suffix.join(' + ')}'}') +
      41;
  final available = width - (rail ? 0 : 16);
  final filters = run(
    [ingredients, chip('Out of stock'), chip('Profitable')],
    available,
    6,
  );
  yield filters + (rail ? 0 : 16);
  if (rail) {
    yield run([math.min(280 * scale, width), filters], width, 16);
  } else {
    final modes = run(
      [
        for (final label in ['Cooking', 'Alchemy', 'Processing'])
          button(label) + 16 + _craftModeIconSize + _craftModeIconGap,
      ],
      width,
      8,
    );
    yield modes;
    yield run([math.min(280 * scale, width), modes], width, 16);
    yield run([math.min(sortWidth, available), filters], available, 12) + 16;
  }
}
