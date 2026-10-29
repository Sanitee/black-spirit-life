import 'package:bdo_craft_planner_flutter/visual/components/app_tooltip.dart';
import 'package:flutter/material.dart';

import '../foundations/theme_spec.dart';

/// A quiet action with a full keyboard/pointer target, but no resting box.
class AppTextAction extends StatelessWidget {
  const AppTextAction({
    required this.child,
    required this.onPressed,
    this.semanticLabel,
    this.tooltip,
    this.selected = false,
    this.color,
    this.fontSize = 13,
    super.key,
  });

  final Widget child;
  final VoidCallback? onPressed;
  final String? semanticLabel;
  final String? tooltip;
  final bool selected;
  final Color? color;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final spec = context.visualTheme;
    final foreground =
        color ?? (selected ? spec.palette.text : spec.palette.textMuted);
    Widget action = TextButton(
      onPressed: onPressed,
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size(32, 32)),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 5, vertical: 5),
        ),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        animationDuration: spec.motion.interactionDuration,
        textStyle: WidgetStatePropertyAll(
          spec.typography.body.copyWith(
            fontSize: fontSize,
            fontWeight: FontWeight.w600,
            height: 1.2,
          ),
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled)
              ? foreground.withValues(alpha: .45)
              : foreground,
        ),
        overlayColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.focused) ||
                  states.contains(WidgetState.pressed)
              ? spec.palette.trimBright.withValues(alpha: .2)
              : spec.palette.trimBright.withValues(alpha: .1),
        ),
        side: WidgetStateProperty.resolveWith(
          (states) => BorderSide(
            color: states.contains(WidgetState.focused)
                ? spec.palette.trimBright
                : Colors.transparent,
          ),
        ),
        shape: const WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(3)),
          ),
        ),
      ),
      child: child,
    );
    if (semanticLabel != null) {
      action = Semantics(
        label: semanticLabel,
        button: true,
        enabled: onPressed != null,
        child: ExcludeSemantics(child: action),
      );
    }
    if (tooltip != null) {
      action = AppTooltip(message: tooltip!, child: action);
    }
    return action;
  }
}
