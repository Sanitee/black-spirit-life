import 'package:bdo_craft_planner_flutter/visual/components/app_tooltip.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../app/window/app_title_bar_visual.dart';
import '../../shared/overlays/anchored_popover.dart';
import '../../visual/visual.dart';
import 'content_size_popover.dart';

/// A quiet title-strip affordance; only its open content observes live sizing.
class ContentSizeTitleAction extends StatefulWidget {
  const ContentSizeTitleAction({
    required this.scale,
    required this.label,
    this.heading,
    required this.overlayId,
    required this.triggerKey,
    required this.popoverKeys,
    required this.onPreview,
    required this.onCommit,
    required this.onReset,
    required this.maximum,
    this.onOpen,
    this.popoverBuilder,
    super.key,
  });

  final ValueListenable<double> scale;
  final String label;
  final String? heading;
  final String overlayId;
  final Key triggerKey;
  final ContentSizePopoverKeys popoverKeys;
  final ValueChanged<double> onPreview;
  final VoidCallback onCommit;
  final VoidCallback onReset;
  final Widget Function(double value, double maximum, VoidCallback close)?
  popoverBuilder;
  final ValueListenable<double> maximum;
  final VoidCallback? onOpen;

  @override
  State<ContentSizeTitleAction> createState() => _ContentSizeTitleActionState();
}

class _ContentSizeTitleActionState extends State<ContentSizeTitleAction> {
  late final FocusNode _triggerFocus = FocusNode(debugLabel: widget.label);
  bool _open = false;

  void _openChanged(bool value) {
    _open = value;
    if (value) {
      widget.onOpen?.call();
    } else {
      widget.onCommit();
    }
  }

  @override
  void didUpdateWidget(ContentSizeTitleAction oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_open && !identical(oldWidget.scale, widget.scale)) {
      oldWidget.onCommit();
    }
  }

  @override
  void dispose() {
    // Removing the Planner title action also removes its portal. Preserve an
    // unfinished pointer/keyboard preview before the action disappears.
    if (_open) widget.onCommit();
    _triggerFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final spec = context.visualTheme;
    final titleVisual = AppTitleBarVisualScope.maybeOf(context);
    // Ledger has pale reading surfaces but a navy title strip. Follow caption
    // foregrounds rather than taking its dark reading-text colour here.
    final foreground =
        titleVisual?.foreground ??
        (spec.isIlluminatedLedger
            ? const Color(0xFFFFF8EA)
            : spec.palette.text);
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: AnchoredPopover(
        overlayId: widget.overlayId,
        preferredWidth: 260,
        maximumHeight: 360,
        alignEnd: true,
        gap: 6,
        onOpenChanged: _openChanged,
        anchorBuilder: (context, toggle, isShowing) => SizedBox(
          width: 36,
          height: 40,
          child: Center(
            child: Semantics(
              expanded: isShowing,
              child: QuietIconButton(
                key: widget.triggerKey,
                focusNode: _triggerFocus,
                tooltip: widget.label,
                onPressed: () {
                  // The popup records this node for explicit close/Escape.
                  // Outside pointer dismissal never requests focus back.
                  _triggerFocus.requestFocus();
                  toggle();
                },
                style: ButtonStyle(
                  fixedSize: const WidgetStatePropertyAll(Size(36, 32)),
                  minimumSize: const WidgetStatePropertyAll(Size.zero),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  padding: const WidgetStatePropertyAll(EdgeInsets.zero),
                  foregroundColor: WidgetStatePropertyAll(foreground),
                  backgroundColor: WidgetStatePropertyAll(
                    isShowing
                        ? foreground.withValues(alpha: .12)
                        : Colors.transparent,
                  ),
                  overlayColor: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.pressed)) {
                      return foreground.withValues(alpha: .18);
                    }
                    if (states.contains(WidgetState.hovered) ||
                        states.contains(WidgetState.focused)) {
                      return foreground.withValues(alpha: .10);
                    }
                    return Colors.transparent;
                  }),
                  shape: WidgetStatePropertyAll(
                    RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  animationDuration:
                      MediaQuery.disableAnimationsOf(context) ||
                          MediaQuery.accessibleNavigationOf(context)
                      ? Duration.zero
                      : spec.motion.interactionDuration,
                ),
                icon: const Icon(Icons.search_rounded, size: 18),
              ),
            ),
          ),
        ),
        popoverBuilder: (context, close) => AnimatedBuilder(
          animation: Listenable.merge([widget.scale, widget.maximum]),
          builder: (context, _) =>
              widget.popoverBuilder?.call(
                widget.scale.value,
                widget.maximum.value,
                close,
              ) ??
              ContentSizePopover(
                label: widget.label,
                heading: widget.heading,
                keys: widget.popoverKeys,
                value: widget.scale.value,
                maximum: widget.maximum.value,
                onChanged: widget.onPreview,
                onChangeEnd: widget.onCommit,
                onReset: widget.onReset,
                onClose: close,
              ),
        ),
      ),
    );
  }
}
