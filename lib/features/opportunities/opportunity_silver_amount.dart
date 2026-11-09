import 'package:flutter/material.dart';

import '../../domain/formatting/compact_silver.dart';
import '../../domain/formatting/planner_formatters.dart';
import '../shared/silver_amount_content.dart';

/// Shared display-only formatting; the full amount remains available on click.
String formatCompactOpportunitySilver(num value) => formatCompactSilver(value);

/// Click again to return to the abbreviated value; the amount is read-only.
class OpportunitySilverAmount extends StatefulWidget {
  const OpportunitySilverAmount({
    required this.value,
    required this.style,
    this.estimated = false,
    this.showPlus = false,
    this.silverSuffix = false,
    this.showIcon = false,
    this.initiallyExpanded = false,
    this.wholeSilver = false,
    this.unicodeMinus = false,
    this.textKey,
    super.key,
  });

  final num? value;
  final TextStyle style;
  final bool estimated, showPlus, silverSuffix;
  final bool showIcon;
  final bool initiallyExpanded, wholeSilver, unicodeMinus;
  final Key? textKey;

  @override
  State<OpportunitySilverAmount> createState() =>
      _OpportunitySilverAmountState();
}

class _OpportunitySilverAmountState extends State<OpportunitySilverAmount> {
  late bool _expanded = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final rawValue = widget.value;
    if (rawValue == null || !rawValue.isFinite) {
      final text = Text('—', key: widget.textKey, style: widget.style);
      return widget.showIcon
          ? Semantics(
              label: 'Silver amount unavailable',
              child: SilverAmountContent(child: text),
            )
          : text;
    }
    final value = widget.wholeSilver ? rawValue.round().toDouble() : rawValue;
    final prefix =
        '${widget.estimated ? '≈ ' : ''}${widget.showPlus && value > 0 ? '+' : ''}';
    final suffix = widget.silverSuffix && !widget.showIcon ? ' silver' : '';
    String signed(String text) =>
        widget.unicodeMinus ? text.replaceFirst('-', '−') : text;
    final full = signed('$prefix${formatQuantity(value.toDouble())}$suffix');
    final compact = signed(
      '$prefix${formatCompactOpportunitySilver(value)}$suffix',
    );
    return Semantics(
      button: true,
      label: _expanded ? 'Shorten amount' : 'Show full amount',
      value: widget.showIcon ? '$full silver' : full,
      child: InkWell(
        onTap: () => setState(() => _expanded = !_expanded),
        borderRadius: BorderRadius.circular(3),
        child: widget.showIcon
            ? SilverAmountContent(
                child: Text(
                  _expanded ? full : compact,
                  key: widget.textKey,
                  style: widget.style,
                ),
              )
            : Text(
                _expanded ? full : compact,
                key: widget.textKey,
                style: widget.style,
              ),
      ),
    );
  }
}
