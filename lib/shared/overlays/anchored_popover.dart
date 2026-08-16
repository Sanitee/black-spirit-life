import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Coordinates application popovers so opening a new one dismisses the
/// previous layer and Escape respects each retained surface's own contract.
final class AppOverlayCoordinator {
  Object? _owner;
  VoidCallback? _dismiss;
  bool _dismissOnEscape = true;

  bool get hasOpenOverlay => _dismiss != null;

  void show({
    required Object owner,
    required VoidCallback dismiss,
    bool dismissOnEscape = true,
  }) {
    if (identical(_owner, owner)) {
      _dismiss = dismiss;
      _dismissOnEscape = dismissOnEscape;
      return;
    }
    final previousDismiss = _dismiss;
    _owner = null;
    _dismiss = null;
    previousDismiss?.call();
    _owner = owner;
    _dismiss = dismiss;
    _dismissOnEscape = dismissOnEscape;
  }

  void hide(Object owner) {
    if (!identical(_owner, owner)) return;
    _owner = null;
    _dismiss = null;
    _dismissOnEscape = true;
  }

  bool dismissTop() {
    final dismiss = _dismiss;
    if (dismiss == null || !_dismissOnEscape) return false;
    _owner = null;
    _dismiss = null;
    _dismissOnEscape = true;
    dismiss();
    return true;
  }
}

class AppOverlayCoordinatorScope extends InheritedWidget {
  const AppOverlayCoordinatorScope({
    required this.coordinator,
    required super.child,
    super.key,
  });

  final AppOverlayCoordinator coordinator;

  static AppOverlayCoordinator? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<AppOverlayCoordinatorScope>()
      ?.coordinator;

  @override
  bool updateShouldNotify(AppOverlayCoordinatorScope oldWidget) =>
      !identical(coordinator, oldWidget.coordinator);
}

/// Root host for coordinated popovers. Modal routes can install their own
/// nearer Escape shortcut and therefore keep normal nested dismissal order.
class AppOverlayCoordinatorHost extends StatefulWidget {
  const AppOverlayCoordinatorHost({
    required this.child,
    this.onEscapeUnhandled,
    super.key,
  });

  final Widget child;
  final VoidCallback? onEscapeUnhandled;

  @override
  State<AppOverlayCoordinatorHost> createState() =>
      _AppOverlayCoordinatorHostState();
}

class _AppOverlayCoordinatorHostState extends State<AppOverlayCoordinatorHost> {
  final AppOverlayCoordinator _coordinator = AppOverlayCoordinator();

  void _handleEscape() {
    if (!_coordinator.dismissTop()) widget.onEscapeUnhandled?.call();
  }

  @override
  Widget build(BuildContext context) => AppOverlayCoordinatorScope(
    coordinator: _coordinator,
    child: CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.escape): _handleEscape,
      },
      child: widget.child,
    ),
  );
}

typedef AnchoredPopoverBuilder =
    Widget Function(BuildContext context, VoidCallback close);
typedef AnchoredPopoverAnchorBuilder =
    Widget Function(BuildContext context, VoidCallback toggle, bool isShowing);

/// Marks an intentional, non-interactive part of an [AnchoredPopover] as a
/// desktop drag surface.
///
/// Keep buttons, text fields, and scrollable bodies outside this region. That
/// lets them retain their normal pointer gestures while a title or otherwise
/// unused part of a popover can move the whole surface.
class AnchoredPopoverDragRegion extends StatelessWidget {
  const AnchoredPopoverDragRegion({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scope = _AnchoredPopoverDragScope.maybeOf(context);
    if (scope == null) return child;
    return MouseRegion(
      cursor: SystemMouseCursors.move,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        dragStartBehavior: DragStartBehavior.down,
        onPanStart: scope.onStart,
        onPanUpdate: scope.onUpdate,
        onPanEnd: scope.onEnd,
        onPanCancel: scope.onCancel,
        child: child,
      ),
    );
  }
}

class _AnchoredPopoverDragScope extends InheritedWidget {
  const _AnchoredPopoverDragScope({
    required this.onStart,
    required this.onUpdate,
    required this.onEnd,
    required this.onCancel,
    required super.child,
  });

  final GestureDragStartCallback onStart;
  final GestureDragUpdateCallback onUpdate;
  final GestureDragEndCallback onEnd;
  final GestureDragCancelCallback onCancel;

  static _AnchoredPopoverDragScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_AnchoredPopoverDragScope>();

  @override
  bool updateShouldNotify(_AnchoredPopoverDragScope oldWidget) => false;
}

enum AnchoredPopoverPlacement {
  /// Prefer below the anchor, flipping above when the lower viewport is tight.
  vertical,

  /// Prefer the anchor's right side, flipping left when it would clip.
  beside,
}

/// A nonmodal, outside-dismissible popover positioned against a real widget.
///
/// The placement delegate clamps to the viewport and supports either vertical
/// dropdown placement or a desktop annotation beside its anchor. Outside
/// pointer events normally continue to their target; retained surfaces can
/// opt into a consuming outside-dismiss region.
class AnchoredPopover extends StatefulWidget {
  const AnchoredPopover({
    required this.overlayId,
    required this.popoverBuilder,
    required this.anchorBuilder,
    this.preferredWidth = 382,
    this.maximumHeight = 420,
    this.alignEnd = true,
    this.margin = 12,
    this.gap = 6,
    this.placement = AnchoredPopoverPlacement.vertical,
    this.dismissOnEscape = true,
    this.consumeOutsideTap = false,
    this.onOpenChanged,
    super.key,
  });

  final String overlayId;
  final AnchoredPopoverBuilder popoverBuilder;
  final AnchoredPopoverAnchorBuilder anchorBuilder;
  final double preferredWidth;
  final double maximumHeight;
  final bool alignEnd;
  final double margin;
  final double gap;
  final AnchoredPopoverPlacement placement;

  /// Whether the root overlay coordinator may dismiss this popover on Escape.
  final bool dismissOnEscape;

  /// Whether the outside-dismiss region consumes the pointer activation.
  ///
  /// Most application popovers remain nonmodal. Small annotation cards can
  /// opt into the retained desktop behavior where the first outside click
  /// only dismisses the card instead of also activating the control beneath.
  final bool consumeOutsideTap;
  final ValueChanged<bool>? onOpenChanged;

  @override
  State<AnchoredPopover> createState() => _AnchoredPopoverState();
}

class _AnchoredPopoverState extends State<AnchoredPopover> {
  final GlobalKey _anchorKey = GlobalKey();
  final GlobalKey _popoverKey = GlobalKey();
  final OverlayPortalController _portal = OverlayPortalController();
  Rect? _anchorRect;
  Size? _viewportSize;
  Offset? _manualTopLeft;
  Offset? _activeDragTopLeft;
  bool _showing = false;
  AppOverlayCoordinator? _registeredCoordinator;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = AppOverlayCoordinatorScope.maybeOf(context);
    if (identical(next, _registeredCoordinator)) return;
    if (_showing) {
      _registeredCoordinator?.hide(this);
      next?.show(
        owner: this,
        dismiss: _closeFromCoordinator,
        dismissOnEscape: widget.dismissOnEscape,
      );
    }
    _registeredCoordinator = next;
  }

  @override
  void didUpdateWidget(AnchoredPopover oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.overlayId != widget.overlayId) {
      _manualTopLeft = null;
      _activeDragTopLeft = null;
    }
    if (_showing && oldWidget.dismissOnEscape != widget.dismissOnEscape) {
      _registeredCoordinator?.show(
        owner: this,
        dismiss: _closeFromCoordinator,
        dismissOnEscape: widget.dismissOnEscape,
      );
    }
  }

  @override
  void dispose() {
    if (_showing) {
      _registeredCoordinator?.hide(this);
    }
    super.dispose();
  }

  void _toggle() => _showing ? _close() : _open();

  void _open() {
    final anchorContext = _anchorKey.currentContext;
    final anchorBox = anchorContext?.findRenderObject();
    if (anchorBox is! RenderBox || !anchorBox.hasSize) return;
    // OverlayPortal's overlay child is laid out in the root view coordinate
    // space. Asking Overlay.of(context).context for an ancestor RenderBox can
    // resolve an inner theater offset by the route's viewport padding, which
    // displaced beside annotations from the visible anchor.
    final origin = anchorBox.localToGlobal(Offset.zero);
    _anchorRect = origin & anchorBox.size;
    _manualTopLeft = null;
    _activeDragTopLeft = null;
    _registeredCoordinator?.show(
      owner: this,
      dismiss: _closeFromCoordinator,
      dismissOnEscape: widget.dismissOnEscape,
    );
    _portal.show();
    setState(() => _showing = true);
    widget.onOpenChanged?.call(true);
  }

  void _closeFromCoordinator() => _close(releaseCoordinator: false);

  void _close({bool releaseCoordinator = true}) {
    if (!_showing) return;
    _portal.hide();
    if (releaseCoordinator) _registeredCoordinator?.hide(this);
    setState(() => _showing = false);
    widget.onOpenChanged?.call(false);
  }

  _AnchoredPopoverLayoutDelegate? _currentLayoutDelegate() {
    final anchor = _anchorRect;
    final viewport = _viewportSize;
    if (anchor == null || viewport == null) return null;
    return _AnchoredPopoverLayoutDelegate(
      anchor: anchor,
      viewport: viewport,
      margin: widget.margin,
      gap: widget.gap,
      alignEnd: widget.alignEnd,
      placement: widget.placement,
      manualTopLeft: _manualTopLeft,
    );
  }

  void _beginDrag(DragStartDetails _) {
    final popoverBox = _popoverKey.currentContext?.findRenderObject();
    final delegate = _currentLayoutDelegate();
    final viewport = _viewportSize;
    if (popoverBox is! RenderBox ||
        !popoverBox.hasSize ||
        delegate == null ||
        viewport == null) {
      return;
    }
    _activeDragTopLeft = delegate.getPositionForChild(
      viewport,
      popoverBox.size,
    );
  }

  void _updateDrag(DragUpdateDetails details) {
    final popoverBox = _popoverKey.currentContext?.findRenderObject();
    final viewport = _viewportSize;
    final current = _activeDragTopLeft;
    if (popoverBox is! RenderBox ||
        !popoverBox.hasSize ||
        viewport == null ||
        current == null) {
      return;
    }
    final next = _clampPopoverPosition(
      current + details.delta,
      viewport,
      popoverBox.size,
      widget.margin,
    );
    setState(() {
      _activeDragTopLeft = next;
      _manualTopLeft = next;
    });
  }

  void _endDrag(DragEndDetails _) => _activeDragTopLeft = null;

  void _cancelDrag() => _activeDragTopLeft = null;

  @override
  Widget build(BuildContext context) => OverlayPortal(
    controller: _portal,
    overlayChildBuilder: (context) {
      final anchor = _anchorRect;
      if (anchor == null) return const SizedBox.shrink();
      final popover = LayoutBuilder(
        builder: (context, constraints) {
          _viewportSize = constraints.biggest;
          final safeWidth = (constraints.maxWidth - widget.margin * 2)
              .clamp(0.0, double.infinity)
              .toDouble();
          final width = widget.preferredWidth.clamp(0.0, safeWidth).toDouble();
          final above = anchor.top - widget.margin - widget.gap;
          final below =
              constraints.maxHeight -
              widget.margin -
              anchor.bottom -
              widget.gap;
          final verticalSpace =
              widget.placement == AnchoredPopoverPlacement.beside
              ? constraints.maxHeight - widget.margin * 2
              : above > below
              ? above
              : below;
          final maxHeight = widget.maximumHeight
              .clamp(0.0, verticalSpace.clamp(0.0, double.infinity))
              .toDouble();
          return CustomSingleChildLayout(
            delegate: _AnchoredPopoverLayoutDelegate(
              anchor: anchor,
              viewport: constraints.biggest,
              margin: widget.margin,
              gap: widget.gap,
              alignEnd: widget.alignEnd,
              placement: widget.placement,
              manualTopLeft: _manualTopLeft,
            ),
            child: KeyedSubtree(
              key: ValueKey<String>('popover:${widget.overlayId}'),
              child: TapRegion(
                groupId: this,
                onTapOutside: widget.consumeOutsideTap ? null : (_) => _close(),
                child: SizedBox(
                  key: _popoverKey,
                  width: width,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: maxHeight),
                    child: _AnchoredPopoverDragScope(
                      onStart: _beginDrag,
                      onUpdate: _updateDrag,
                      onEnd: _endDrag,
                      onCancel: _cancelDrag,
                      child: widget.popoverBuilder(context, _close),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      );
      return Positioned.fill(
        child: Stack(
          key: ValueKey<String>('popover-region:${widget.overlayId}'),
          fit: StackFit.expand,
          children: <Widget>[
            if (widget.consumeOutsideTap)
              GestureDetector(behavior: HitTestBehavior.opaque, onTap: _close),
            popover,
          ],
        ),
      );
    },
    child: TapRegion(
      groupId: this,
      child: KeyedSubtree(
        key: _anchorKey,
        child: widget.anchorBuilder(context, _toggle, _showing),
      ),
    ),
  );
}

final class _AnchoredPopoverLayoutDelegate extends SingleChildLayoutDelegate {
  const _AnchoredPopoverLayoutDelegate({
    required this.anchor,
    required this.viewport,
    required this.margin,
    required this.gap,
    required this.alignEnd,
    required this.placement,
    required this.manualTopLeft,
  });

  final Rect anchor;
  final Size viewport;
  final double margin;
  final double gap;
  final bool alignEnd;
  final AnchoredPopoverPlacement placement;
  final Offset? manualTopLeft;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      constraints.loosen();

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final manual = manualTopLeft;
    if (manual != null) {
      return _clampPopoverPosition(manual, size, childSize, margin);
    }
    if (placement == AnchoredPopoverPlacement.beside) {
      final desiredRight = anchor.center.dx + gap;
      final rightSpace = size.width - margin - desiredRight;
      final leftSpace = anchor.center.dx - gap - margin;
      final placeLeft = childSize.width > rightSpace && leftSpace > rightSpace;
      final desiredX = placeLeft
          ? anchor.center.dx - gap - childSize.width
          : desiredRight;
      final maxX = (size.width - margin - childSize.width).clamp(
        margin,
        double.infinity,
      );
      final maxY = (size.height - margin - childSize.height).clamp(
        margin,
        double.infinity,
      );
      return Offset(
        desiredX.clamp(margin, maxX).toDouble(),
        (anchor.center.dy - childSize.height / 2)
            .clamp(margin, maxY)
            .toDouble(),
      );
    }
    final desiredX = alignEnd ? anchor.right - childSize.width : anchor.left;
    final maxX = (size.width - margin - childSize.width).clamp(
      margin,
      double.infinity,
    );
    final x = desiredX.clamp(margin, maxX).toDouble();
    final above = anchor.top - margin - gap;
    final below = size.height - margin - anchor.bottom - gap;
    final placeAbove = childSize.height > below && above > below;
    final desiredY = placeAbove
        ? anchor.top - gap - childSize.height
        : anchor.bottom + gap;
    final maxY = (size.height - margin - childSize.height).clamp(
      margin,
      double.infinity,
    );
    return Offset(x, desiredY.clamp(margin, maxY).toDouble());
  }

  @override
  bool shouldRelayout(_AnchoredPopoverLayoutDelegate oldDelegate) =>
      anchor != oldDelegate.anchor ||
      viewport != oldDelegate.viewport ||
      margin != oldDelegate.margin ||
      gap != oldDelegate.gap ||
      alignEnd != oldDelegate.alignEnd ||
      placement != oldDelegate.placement ||
      manualTopLeft != oldDelegate.manualTopLeft;
}

Offset _clampPopoverPosition(
  Offset desired,
  Size viewport,
  Size childSize,
  double margin,
) {
  final maxX = (viewport.width - margin - childSize.width).clamp(
    margin,
    double.infinity,
  );
  final maxY = (viewport.height - margin - childSize.height).clamp(
    margin,
    double.infinity,
  );
  return Offset(
    desired.dx.clamp(margin, maxX).toDouble(),
    desired.dy.clamp(margin, maxY).toDouble(),
  );
}
