import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

import 'resource_map_chrome_theme.dart';

/// One map option, with its own glass backing and no painted list footprint.
/// The child retains its existing action, focus order and semantics.
class ResourceMapPill extends StatefulWidget {
  const ResourceMapPill({
    super.key,
    required this.child,
    this.selected = false,
    this.padding = EdgeInsets.zero,
  });

  final Widget child;
  final bool selected;
  final EdgeInsetsGeometry padding;

  @override
  State<ResourceMapPill> createState() => _ResourceMapPillState();
}

class _ResourceMapPillState extends State<ResourceMapPill> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final chrome = context.mapChrome;
    final strength = math.max(.02, chrome.uiOpacity);
    final active = widget.selected || _hovered || _focused;
    final fill = active ? math.max(.24, strength) : strength;
    const radius = BorderRadius.all(Radius.circular(10));
    final top = Color.lerp(chrome.chromeHighlight, chrome.primary, .045)!;
    final bottom = Color.lerp(chrome.chromeRaised, chrome.chromeBase, .28)!;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onFocusChange: (value) => setState(() => _focused = value),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: radius,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: .22 * strength),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: radius,
            child: BackdropFilter(
              filter: ImageFilter.blur(
                sigmaX: 14 * math.min(1, strength / .6),
                sigmaY: 14 * math.min(1, strength / .6),
              ),
              child: AnimatedContainer(
                duration: MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : const Duration(milliseconds: 150),
                curve: Curves.easeOutCubic,
                decoration: BoxDecoration(
                  borderRadius: radius,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      top.withValues(alpha: fill * .96),
                      bottom.withValues(alpha: fill * .98),
                    ],
                  ),
                  border: Border.all(
                    color:
                        (_focused || widget.selected
                                ? chrome.primary
                                : chrome.readingOutline)
                            .withValues(alpha: active ? .65 : .34 * strength),
                  ),
                ),
                child: Material(
                  type: MaterialType.transparency,
                  child: Padding(padding: widget.padding, child: widget.child),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
