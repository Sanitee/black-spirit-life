import 'package:bdo_craft_planner_flutter/features/shared/market_count_badges.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Scope icon-only counts to their badge; a bare zero may also be a quantity,
/// an inventory count, a price or an unrelated empty-state value.
Finder stockBadgeText([String? value]) => find.descendant(
  of: find.byType(MarketCountBadges),
  matching: find.byWidgetPredicate(
    (widget) =>
        widget is Text &&
        (value != null
            ? widget.data == value
            : widget.data != null &&
                  widget.data != 'NPC' &&
                  !widget.data!.startsWith('Orders ')),
  ),
);
