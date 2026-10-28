import 'package:flutter/material.dart';

import '../foundations/theme_spec.dart';

/// Quiet grouping for content that does not need another decorative frame.
class AppSoftTile extends StatelessWidget {
  const AppSoftTile({
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.selected = false,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final palette = context.visualTheme.palette;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          palette.surfaceRaised.withAlpha(100),
          palette.surfaceInset,
        ),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: selected ? palette.primaryBright : Colors.transparent,
        ),
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}
