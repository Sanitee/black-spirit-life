import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart';

typedef DraggableOverlayInitialPosition =
    Offset Function(Size viewport, Size childSize);

/// Full-route host for a draggable application dialog.
///
/// Use this directly as a `showDialog` builder result instead of wrapping the
/// content in Material's centering [Dialog]. The route still owns the modal
/// barrier; this host owns visible placement and viewport-safe dragging.
class DraggableModalRouteSurface extends StatelessWidget {
  const DraggableModalRouteSurface({
    required this.overlayId,
    required this.child,
    this.insetPadding = const EdgeInsets.all(24),
    super.key,
  });

  final String overlayId;
  final Widget child;
  final EdgeInsets insetPadding;

  @override
  Widget build(BuildContext context) => Material(
    type: MaterialType.transparency,
    child: SafeArea(
      minimum: insetPadding,
      child: DraggableOverlaySurface(
        overlayId: overlayId,
        margin: 0,
        child: child,
      ),
    ),
  );
}

/// Marks a non-interactive title or empty area as the handle for the nearest
/// [DraggableOverlaySurface]. Buttons, fields, links, and scrollable content
/// should remain outside this region so their normal gestures are preserved.
class DraggableOverlayDragRegion extends StatelessWidget {
  const DraggableOverlayDragRegion({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scope = _DraggableOverlayScope.maybeOf(context);
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

class _DraggableOverlayScope extends InheritedWidget {
  const _DraggableOverlayScope({
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

  static _DraggableOverlayScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_DraggableOverlayScope>();

  @override
  bool updateShouldNotify(_DraggableOverlayScope oldWidget) => false;
}

/// Positions a desktop dialog or substantial popup within its viewport and
/// lets an intentional descendant [DraggableOverlayDragRegion] move it.
///
/// The surface remains clamped to the visible viewport. Its manual position is
/// retained during ordinary rebuilds and reset when [overlayId] changes.
class DraggableOverlaySurface extends StatefulWidget {
  const DraggableOverlaySurface({
    required this.overlayId,
    required this.child,
    this.initialPosition,
    this.alignment = Alignment.center,
    this.margin = 16,
    super.key,
  });

  final String overlayId;
  final Widget child;
  final DraggableOverlayInitialPosition? initialPosition;
  final Alignment alignment;
  final double margin;

  @override
  State<DraggableOverlaySurface> createState() =>
      _DraggableOverlaySurfaceState();
}

class _DraggableOverlaySurfaceState extends State<DraggableOverlaySurface> {
  final GlobalKey _surfaceKey = GlobalKey();
  Size? _viewportSize;
  Offset? _manualTopLeft;
  Offset? _activeDragTopLeft;

  @override
  void didUpdateWidget(DraggableOverlaySurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.overlayId != widget.overlayId) {
      _manualTopLeft = null;
      _activeDragTopLeft = null;
    }
  }

  _DraggableOverlayLayoutDelegate _delegate(Size viewport) =>
      _DraggableOverlayLayoutDelegate(
        alignment: widget.alignment,
        margin: widget.margin,
        initialPosition: widget.initialPosition,
        manualTopLeft: _manualTopLeft,
      );

  void _beginDrag(DragStartDetails _) {
    final surface = _surfaceKey.currentContext?.findRenderObject();
    final viewport = _viewportSize;
    if (surface is! RenderBox || !surface.hasSize || viewport == null) return;
    _activeDragTopLeft = _delegate(
      viewport,
    ).getPositionForChild(viewport, surface.size);
  }

  void _updateDrag(DragUpdateDetails details) {
    final surface = _surfaceKey.currentContext?.findRenderObject();
    final viewport = _viewportSize;
    final current = _activeDragTopLeft;
    if (surface is! RenderBox ||
        !surface.hasSize ||
        viewport == null ||
        current == null) {
      return;
    }
    final next = _clampOverlayPosition(
      current + details.delta,
      viewport,
      surface.size,
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
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final viewport = constraints.biggest;
      _viewportSize = viewport;
      return CustomSingleChildLayout(
        delegate: _delegate(viewport),
        child: KeyedSubtree(
          key: _surfaceKey,
          child: _DraggableOverlayScope(
            onStart: _beginDrag,
            onUpdate: _updateDrag,
            onEnd: _endDrag,
            onCancel: _cancelDrag,
            child: widget.child,
          ),
        ),
      );
    },
  );
}

final class _DraggableOverlayLayoutDelegate extends SingleChildLayoutDelegate {
  const _DraggableOverlayLayoutDelegate({
    required this.alignment,
    required this.margin,
    required this.initialPosition,
    required this.manualTopLeft,
  });

  final Alignment alignment;
  final double margin;
  final DraggableOverlayInitialPosition? initialPosition;
  final Offset? manualTopLeft;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      constraints.loosen();

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final desired =
        manualTopLeft ??
        initialPosition?.call(size, childSize) ??
        alignment.inscribe(childSize, Offset.zero & size).topLeft;
    return _clampOverlayPosition(desired, size, childSize, margin);
  }

  @override
  bool shouldRelayout(_DraggableOverlayLayoutDelegate oldDelegate) =>
      alignment != oldDelegate.alignment ||
      margin != oldDelegate.margin ||
      !identical(initialPosition, oldDelegate.initialPosition) ||
      manualTopLeft != oldDelegate.manualTopLeft;
}

Offset _clampOverlayPosition(
  Offset desired,
  Size viewport,
  Size childSize,
  double margin,
) {
  final usableMarginX = margin.clamp(
    0.0,
    (viewport.width - childSize.width).clamp(0.0, double.infinity) / 2,
  );
  final usableMarginY = margin.clamp(
    0.0,
    (viewport.height - childSize.height).clamp(0.0, double.infinity) / 2,
  );
  final maxX = (viewport.width - usableMarginX - childSize.width).clamp(
    usableMarginX,
    double.infinity,
  );
  final maxY = (viewport.height - usableMarginY - childSize.height).clamp(
    usableMarginY,
    double.infinity,
  );
  return Offset(
    desired.dx.clamp(usableMarginX, maxX).toDouble(),
    desired.dy.clamp(usableMarginY, maxY).toDouble(),
  );
}
