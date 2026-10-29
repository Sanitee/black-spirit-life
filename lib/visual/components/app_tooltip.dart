import 'package:flutter/material.dart';

/// Ordinary labels remain available to accessibility without opening a popup.
/// Hover content is opt-in only for a specific user-approved reference/hint.
class AppTooltip extends Tooltip {
  const AppTooltip({
    super.key,
    super.message,
    super.richMessage,
    super.constraints,
    super.padding,
    super.margin,
    super.verticalOffset,
    super.preferBelow,
    super.excludeFromSemantics,
    super.decoration,
    super.textStyle,
    super.textAlign,
    super.waitDuration,
    super.showDuration,
    super.exitDuration,
    super.enableTapToDismiss,
    super.triggerMode,
    super.enableFeedback,
    super.onTriggered,
    super.mouseCursor,
    super.ignorePointer,
    super.positionDelegate,
    super.child,
    this.approvedHover = false,
  });

  final bool approvedHover;

  @override
  TooltipState createState() => _AppTooltipState();
}

class _AppTooltipState extends TooltipState {
  @override
  Widget build(BuildContext context) {
    final hint = widget as AppTooltip;
    if (hint.approvedHover) return super.build(context);
    final excluded =
        hint.excludeFromSemantics ??
        TooltipTheme.of(context).excludeFromSemantics ??
        false;
    return Semantics(
      tooltip: excluded
          ? null
          : hint.message ?? hint.richMessage?.toPlainText(),
      child: hint.child ?? const SizedBox.shrink(),
    );
  }
}

/// Material icon buttons otherwise create their own implicit hover tooltip.
class QuietIconButton extends IconButton {
  const QuietIconButton({
    super.key,
    super.iconSize,
    super.visualDensity,
    super.padding,
    super.alignment,
    super.splashRadius,
    super.color,
    super.focusColor,
    super.hoverColor,
    super.highlightColor,
    super.splashColor,
    super.disabledColor,
    required super.onPressed,
    super.onHover,
    super.onLongPress,
    super.mouseCursor,
    super.focusNode,
    super.autofocus,
    super.tooltip,
    super.enableFeedback,
    super.constraints,
    super.style,
    super.isSelected,
    super.selectedIcon,
    super.statesController,
    required super.icon,
    this.approvedHover = false,
  });

  final bool approvedHover;

  @override
  Widget build(BuildContext context) => approvedHover
      ? super.build(context)
      : Semantics(
          tooltip: tooltip,
          child: TooltipVisibility(visible: false, child: super.build(context)),
        );
}
