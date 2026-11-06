import 'package:flutter/material.dart';

import '../../visual/visual.dart';
import '../opportunities/opportunity_silver_amount.dart';

/// Read-only silver: the same artwork, compact notation and click-to-expand
/// amount in the host and its independently packaged feature views.
class SharedSilverAmount extends StatelessWidget {
  const SharedSilverAmount({
    required this.value,
    required this.style,
    this.prefix = '',
    this.suffix = '',
    this.textKey,
    super.key,
  });
  final num? value;
  final TextStyle style;
  final String prefix, suffix;
  final Key? textKey;

  @override
  Widget build(BuildContext context) {
    final textStyle = context.visualTheme.typography.meta.merge(style);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Image.asset(
          'assets/icons/item_artwork/1.webp',
          package: 'bdo_gathering_companion',
          width: 18,
          height: 18,
          excludeFromSemantics: true,
        ),
        const SizedBox(width: 5),
        Flexible(
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (prefix.isNotEmpty) Text(prefix, style: textStyle),
              OpportunitySilverAmount(
                value: value,
                style: textStyle,
                textKey: textKey,
              ),
              if (suffix.isNotEmpty) Text(suffix, style: textStyle),
            ],
          ),
        ),
      ],
    );
  }
}
