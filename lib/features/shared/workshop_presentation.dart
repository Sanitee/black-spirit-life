import 'package:flutter/material.dart';

import '../../visual/visual.dart';

/// A passive display mount: original artwork and its hit bounds stay intact.
class WorkshopItemMount extends StatelessWidget {
  const WorkshopItemMount({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = context.visualTheme.palette;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [palette.surfaceRaised, palette.surfaceInset],
        ),
        boxShadow: [
          BoxShadow(
            color: palette.shadow.withValues(alpha: .26),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
          BoxShadow(
            color: palette.trimBright.withValues(alpha: .10),
            blurRadius: 3,
            spreadRadius: .6,
          ),
        ],
      ),
      child: child,
    );
  }
}

/// A fine material seam, not another framed panel or a layout spacer.
class WorkshopSectionRule extends StatelessWidget {
  const WorkshopSectionRule({this.emphasis = false, super.key});

  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    final palette = context.visualTheme.palette;
    return SizedBox(
      height: 1,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            stops: const [0, .18, 1],
            colors: [
              palette.trimBright.withValues(alpha: emphasis ? .70 : .42),
              palette.trim.withValues(alpha: .36),
              palette.trim.withValues(alpha: .06),
            ],
          ),
        ),
      ),
    );
  }
}
