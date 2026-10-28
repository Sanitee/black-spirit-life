import 'package:flutter/material.dart';

import '../../domain/formatting/planner_formatters.dart';

/// Abbreviate toward zero, so a displayed gain never rounds up.
String formatCompactOpportunitySilver(num value) {
  if (!value.isFinite) return '—';
  final magnitude = value.abs();
  final (unit, suffix) = magnitude >= 1000000000
      ? (1000000000, 'b')
      : magnitude >= 1000000
      ? (1000000, 'm')
      : magnitude >= 1000
      ? (1000, 'k')
      : (1, '');
  final shortened = (magnitude / unit * 10).floor() / 10;
  final signed = value < 0 ? -shortened : shortened;
  return '${formatQuantity(signed)}$suffix';
}

/// Click again to return to the abbreviated value; the amount is read-only.
class OpportunitySilverAmount extends StatefulWidget {
  const OpportunitySilverAmount({
    required this.value,
    required this.style,
    this.estimated = false,
    this.showPlus = false,
    this.silverSuffix = false,
    this.initiallyExpanded = false,
    this.wholeSilver = false,
    this.unicodeMinus = false,
    this.textKey,
    super.key,
  });

  final num? value;
  final TextStyle style;
  final bool estimated, showPlus, silverSuffix;
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
      return Text('—', key: widget.textKey, style: widget.style);
    }
    final value = widget.wholeSilver ? rawValue.round().toDouble() : rawValue;
    final prefix =
        '${widget.estimated ? '≈ ' : ''}${widget.showPlus && value > 0 ? '+' : ''}';
    final suffix = widget.silverSuffix ? ' silver' : '';
    String signed(String text) =>
        widget.unicodeMinus ? text.replaceFirst('-', '−') : text;
    final full = signed('$prefix${formatQuantity(value.toDouble())}$suffix');
    final compact = signed(
      '$prefix${formatCompactOpportunitySilver(value)}$suffix',
    );
    return Semantics(
      button: true,
      label: _expanded ? 'Shorten amount' : 'Show full amount',
      value: full,
      child: InkWell(
        onTap: () => setState(() => _expanded = !_expanded),
        borderRadius: BorderRadius.circular(3),
        child: Text(
          _expanded ? full : compact,
          key: widget.textKey,
          style: widget.style,
        ),
      ),
    );
  }
}
