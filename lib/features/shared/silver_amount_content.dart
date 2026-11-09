import 'package:flutter/material.dart';

/// Shared currency artwork and spacing around a read-only silver value.
class SilverAmountContent extends StatelessWidget {
  const SilverAmountContent({required this.child, super.key});

  static const iconSize = 18.0;
  static const gap = 5.0;
  static const leadingWidth = iconSize + gap;

  final Widget child;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Image.asset(
        'assets/icons/item_artwork/1.webp',
        package: 'bdo_gathering_companion',
        width: iconSize,
        height: iconSize,
        excludeFromSemantics: true,
      ),
      const SizedBox(width: gap),
      Flexible(child: child),
    ],
  );
}
