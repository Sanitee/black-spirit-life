import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../visual/visual.dart';

/// Content-sized reading controls hosted by the title bar's anchored popover.
/// Scaling and persistence belong to its controller, not this presentation.
class ContentSizePopover extends StatefulWidget {
  const ContentSizePopover({
    required this.label,
    required this.keys,
    this.heading,
    required this.value,
    required this.maximum,
    required this.onChanged,
    required this.onChangeEnd,
    required this.onReset,
    required this.onClose,
    super.key,
  });

  final String label;
  final ContentSizePopoverKeys keys;
  final String? heading;
  final double value;
  final double maximum;
  final ValueChanged<double> onChanged;
  final VoidCallback onChangeEnd;
  final VoidCallback onReset;
  final VoidCallback onClose;

  @override
  State<ContentSizePopover> createState() => _ContentSizePopoverState();
}

class _ContentSizePopoverState extends State<ContentSizePopover> {
  late final FocusNode? _previousFocus;

  @override
  void initState() {
    super.initState();
    _previousFocus = FocusManager.instance.primaryFocus;
  }

  void _close({bool restoreFocus = false}) {
    widget.onClose();
    if (restoreFocus && (_previousFocus?.context?.mounted ?? false)) {
      _previousFocus?.requestFocus();
    }
  }

  void _finishPointerChange() {
    // A quick tap can resolve the slider's gesture after raw pointer-up.
    // Commit after that dispatch so the new preview, not the old value, saves.
    scheduleMicrotask(() {
      if (mounted) widget.onChangeEnd();
    });
  }

  @override
  Widget build(BuildContext context) {
    final spec = context.visualTheme;
    final maximum = widget.maximum.clamp(1.0, 1.25);
    final effective = widget.value.clamp(1.0, maximum);
    final percentage = (effective * 100).round();
    final maximumPercentage = maximum * 100;
    final enabled = maximum > 1;
    final slider = Listener(
      onPointerUp: (_) => _finishPointerChange(),
      onPointerCancel: (_) => _finishPointerChange(),
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        includeSemantics: false,
        onKeyEvent: (_, event) {
          if (event is KeyUpEvent) widget.onChangeEnd();
          return KeyEventResult.ignored;
        },
        child: AppSlider(
          key: widget.keys.slider,
          value: effective * 100,
          min: 100,
          max: maximumPercentage,
          divisions: enabled ? (maximumPercentage - 100).round() : null,
          label: '$percentage%',
          semanticLabel: widget.label,
          autofocus: enabled,
          onChanged: enabled ? (value) => widget.onChanged(value / 100) : null,
        ),
      ),
    );
    // The anchored host owns outside dismissal and overlay coordination.
    // Shrink-wrap here so an otherwise small popup never fills its height cap.
    return SingleChildScrollView(
      primary: false,
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): () =>
              _close(restoreFocus: true),
        },
        child: FocusTraversalGroup(
          child: DecoratedBox(
            key: widget.keys.backing,
            // Standard's glass is intentionally very clear. This small
            // control overlays workspace content, so give only it a solid
            // backing; the normal theme surface still draws its finish.
            decoration: BoxDecoration(
              color: spec.isStandard
                  ? spec.palette.surface.withValues(alpha: 1)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(spec.geometry.panelRadius),
            ),
            child: AppSurface(
              key: widget.keys.surface,
              role: AppSurfaceRole.popup,
              padding: const EdgeInsets.all(12),
              semanticLabel: widget.label,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      Text(
                        widget.heading ?? widget.label,
                        style: spec.typography.section.copyWith(
                          fontSize: 16,
                          color: spec.palette.text,
                        ),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '$percentage%',
                            key: widget.keys.value,
                            style: spec.typography.section.copyWith(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: spec.palette.text,
                            ),
                          ),
                          const SizedBox(width: 6),
                          AppButton(
                            key: widget.keys.close,
                            role: AppButtonRole.icon,
                            minimumSize: const Size(28, 28),
                            padding: const EdgeInsets.all(4),
                            semanticLabel: 'Close ${widget.label}',
                            autofocus: !enabled,
                            onPressed: () => _close(restoreFocus: true),
                            child: const Icon(Icons.close, size: 16),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (enabled)
                    slider
                  else
                    Tooltip(
                      message:
                          'Enlarge the window to increase ${widget.label}.',
                      child: slider,
                    ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: AppButton.label(
                      'Reset 100%',
                      key: widget.keys.reset,
                      minimumSize: const Size(0, 34),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 7,
                      ),
                      onPressed: widget.value == 1 ? null : widget.onReset,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

@immutable
class ContentSizePopoverKeys {
  const ContentSizePopoverKeys(this.prefix);
  final String prefix;
  Key get surface => ValueKey('$prefix-popover');
  Key get backing => ValueKey('$prefix-backing');
  Key get slider => ValueKey('$prefix-zoom-slider');
  Key get value => ValueKey('$prefix-zoom-value');
  Key get reset => ValueKey('$prefix-zoom-reset');
  Key get close => ValueKey('$prefix-close');
}
