import 'package:flutter/material.dart';

import '../../visual/foundations/theme_spec.dart';
import '../../visual/sakura_night_garden/sakura_backdrop.dart';
import '../../visual/standard/standard_backdrop.dart';
import '../../visual/standard/standard_spec.dart';
import 'app_title_bar.dart';

/// Native client-area frame shared by loading, failure, and first-launch
/// migration surfaces before the full planner workspace is available.
class AppStartupFrame extends StatelessWidget {
  const AppStartupFrame({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final spec = context.visualTheme;
    final bodyStyle = spec.typography.body.copyWith(
      color: spec.palette.text,
      decoration: TextDecoration.none,
    );
    final content = SafeArea(top: false, child: child);
    return Material(
      color: spec.palette.canvasDeep,
      textStyle: bodyStyle,
      child: DefaultTextStyle(
        style: bodyStyle,
        child: Column(
          children: <Widget>[
            const AppTitleBar(),
            Expanded(
              child: spec.isSakuraNightGarden
                  ? SakuraNightGardenBackdrop(child: content)
                  : StandardBackdrop(
                      backgroundId: context.standardVisual.backgroundId,
                      child: content,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
