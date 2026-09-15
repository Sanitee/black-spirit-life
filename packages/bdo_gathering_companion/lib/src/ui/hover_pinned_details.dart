import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Shows a non-modal detail card after a short mouse hover and lets secondary
/// click promote the same information to the caller's persistent surface.
///
/// Only one hover card is kept open across the application. Moving from the
/// target into the card is tolerated so long details can be read or scrolled
/// without flicker.
class HoverPinnedDetails extends StatefulWidget {
  const HoverPinnedDetails({
    super.key,
    required this.hoverKey,
    required this.cardBuilder,
    required this.onPin,
    this.child,
    this.targetBuilder,
    this.waitDuration = const Duration(milliseconds: 300),
    this.hideDelay = const Duration(milliseconds: 140),
  }) : assert((child == null) != (targetBuilder == null));

  final Key hoverKey;
  final WidgetBuilder cardBuilder;
  final VoidCallback onPin;
  final Widget? child;

  /// Optional for reference-only targets whose primary action is also pinning.
  /// The provided callback dismisses any hover before opening pinned details.
  /// Ordinary selectable targets keep [child] and their own primary actions.
  final Widget Function(BuildContext context, VoidCallback pin)? targetBuilder;
  final Duration waitDuration;
  final Duration hideDelay;

  @override
  State<HoverPinnedDetails> createState() => _HoverPinnedDetailsState();
}

class _HoverPinnedDetailsState extends State<HoverPinnedDetails> {
  static _HoverPinnedDetailsState? _active;

  final _targetKey = GlobalKey();
  Timer? _showTimer;
  Timer? _hideTimer;
  OverlayEntry? _entry;
  bool _overTarget = false;
  bool _overCard = false;
  bool _suppressUntilExit = false;

  @override
  void dispose() {
    _showTimer?.cancel();
    _hideTimer?.cancel();
    _removeEntry();
    super.dispose();
  }

  void _targetEntered(PointerEnterEvent event) {
    _overTarget = true;
    _hideTimer?.cancel();
    if (_suppressUntilExit || _entry != null) return;
    _showTimer?.cancel();
    _showTimer = Timer(widget.waitDuration, _showCard);
  }

  void _targetExited(PointerExitEvent event) {
    _overTarget = false;
    _suppressUntilExit = false;
    _scheduleHide();
  }

  void _cardEntered(PointerEnterEvent event) {
    _overCard = true;
    _hideTimer?.cancel();
  }

  void _cardExited(PointerExitEvent event) {
    _overCard = false;
    _scheduleHide();
  }

  void _showCard() {
    if (!mounted || !_overTarget || _suppressUntilExit || _entry != null) {
      return;
    }
    final target = _targetKey.currentContext?.findRenderObject();
    if (target is! RenderBox || !target.hasSize) return;
    final overlay = Overlay.of(context, rootOverlay: true);
    final origin = target.localToGlobal(Offset.zero);
    final anchor = origin & target.size;
    _active?._removeEntry();
    _active = this;
    _entry = OverlayEntry(
      builder: (overlayContext) => CustomSingleChildLayout(
        delegate: _HoverCardLayoutDelegate(anchor),
        child: MouseRegion(
          onEnter: _cardEntered,
          onExit: _cardExited,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            // A small viewport can place the card over its original target.
            // Pinning must still work when that card receives the right-click.
            onSecondaryTap: _pin,
            child: KeyedSubtree(
              key: widget.hoverKey,
              // Root overlays are outside the source Material subtree. Carry
              // its theme across and establish normal body typography before
              // building details (otherwise Text uses Flutter's warning style).
              child: InheritedTheme.captureAll(
                context,
                Material(
                  type: MaterialType.transparency,
                  child: Builder(builder: widget.cardBuilder),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    overlay.insert(_entry!);
  }

  void _scheduleHide() {
    _showTimer?.cancel();
    _hideTimer?.cancel();
    _hideTimer = Timer(widget.hideDelay, () {
      if (!_overTarget && !_overCard) _removeEntry();
    });
  }

  void _removeEntry() {
    _showTimer?.cancel();
    _hideTimer?.cancel();
    _entry?.remove();
    _entry = null;
    _overCard = false;
    if (identical(_active, this)) _active = null;
  }

  void _pin() {
    _suppressUntilExit = true;
    _removeEntry();
    widget.onPin();
  }

  @override
  Widget build(BuildContext context) => MouseRegion(
    key: _targetKey,
    onEnter: _targetEntered,
    onExit: _targetExited,
    child: GestureDetector(
      behavior: HitTestBehavior.deferToChild,
      onSecondaryTap: _pin,
      child: widget.targetBuilder?.call(context, _pin) ?? widget.child!,
    ),
  );
}

class _HoverCardLayoutDelegate extends SingleChildLayoutDelegate {
  const _HoverCardLayoutDelegate(this.anchor);

  static const _edge = 12.0;
  static const _gap = 8.0;
  static const _maxWidth = 400.0;

  final Rect anchor;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints(
        minWidth: 0,
        maxWidth: (constraints.maxWidth - _edge * 2).clamp(0, _maxWidth),
        minHeight: 0,
        maxHeight: (constraints.maxHeight - _edge * 2).clamp(0, 620),
      );

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    var left = anchor.right + _gap;
    if (left + childSize.width > size.width - _edge) {
      left = anchor.left - _gap - childSize.width;
    }
    left = left.clamp(_edge, size.width - childSize.width - _edge);

    var top = anchor.top;
    if (top + childSize.height > size.height - _edge) {
      top = size.height - childSize.height - _edge;
    }
    top = top.clamp(_edge, size.height - childSize.height - _edge);
    return Offset(left, top);
  }

  @override
  bool shouldRelayout(_HoverCardLayoutDelegate oldDelegate) =>
      oldDelegate.anchor != anchor;
}
