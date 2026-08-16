import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

typedef DraggableDialogSurfaceBuilder =
    Widget Function(BuildContext context, Alignment alignment);

typedef DraggablePositionedSurfaceBuilder =
    Widget Function(BuildContext context, Offset position, bool manuallyMoved);

/// Keeps a substantial dialog movable without changing its visual treatment.
///
/// [builder] receives an alignment clamped to the safe viewport. Dialogs use
/// that value for [Dialog.alignment], while custom modal surfaces can pass it
/// to an [Align]. A fresh route naturally starts centered; [identity] also
/// resets the position when a stateful surface is reused for new content.
class DraggableDialogSurface extends StatefulWidget {
  const DraggableDialogSurface({
    required this.identity,
    required this.builder,
    this.estimatedSize,
    super.key,
  });

  final Object identity;
  final Size? estimatedSize;
  final DraggableDialogSurfaceBuilder builder;

  @override
  State<DraggableDialogSurface> createState() => _DraggableDialogSurfaceState();
}

class _DraggableDialogSurfaceState extends State<DraggableDialogSurface> {
  Alignment _alignment = Alignment.center;

  @override
  void didUpdateWidget(DraggableDialogSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.identity != widget.identity) {
      _alignment = Alignment.center;
    }
  }

  void _moveBy(Offset delta) {
    final media = MediaQuery.of(context);
    final safeWidth = math.max(
      1.0,
      media.size.width - media.padding.horizontal,
    );
    final safeHeight = math.max(
      1.0,
      media.size.height - media.padding.vertical,
    );
    final estimatedSize = widget.estimatedSize;
    final dialogWidth = math.min(
      safeWidth,
      estimatedSize?.width ?? safeWidth * 0.58,
    );
    final dialogHeight = math.min(
      safeHeight,
      estimatedSize?.height ?? safeHeight * 0.62,
    );
    final horizontalTravel = math.max(48.0, safeWidth - dialogWidth);
    final verticalTravel = math.max(48.0, safeHeight - dialogHeight);
    final next = Alignment(
      _alignment.x + ((delta.dx * 2) / horizontalTravel),
      _alignment.y + ((delta.dy * 2) / verticalTravel),
    );
    setState(() {
      _alignment = Alignment(next.x.clamp(-1.0, 1.0), next.y.clamp(-1.0, 1.0));
    });
  }

  @override
  Widget build(BuildContext context) {
    return _DraggableDialogScope(
      onMove: _moveBy,
      child: widget.builder(context, _alignment),
    );
  }
}

/// Makes a map-anchored flyout movable while preserving its initial anchor.
///
/// The surface follows [initialPosition] until the player drags it. From then
/// on it stays at the chosen viewport position and is clamped using
/// [estimatedSize]. A different [identity] starts from its own anchor again.
class DraggablePositionedSurface extends StatefulWidget {
  const DraggablePositionedSurface({
    required this.identity,
    required this.viewportSize,
    required this.initialPosition,
    required this.estimatedSize,
    required this.builder,
    this.viewportPadding = const EdgeInsets.all(12),
    super.key,
  });

  final Object identity;
  final Size viewportSize;
  final Offset initialPosition;
  final Size estimatedSize;
  final EdgeInsets viewportPadding;
  final DraggablePositionedSurfaceBuilder builder;

  @override
  State<DraggablePositionedSurface> createState() =>
      _DraggablePositionedSurfaceState();
}

class _DraggablePositionedSurfaceState
    extends State<DraggablePositionedSurface> {
  Offset? _manualPosition;

  bool get _manuallyMoved => _manualPosition != null;

  @override
  void didUpdateWidget(DraggablePositionedSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.identity != widget.identity) {
      _manualPosition = null;
    } else if (_manualPosition != null &&
        (oldWidget.viewportSize != widget.viewportSize ||
            oldWidget.estimatedSize != widget.estimatedSize)) {
      _manualPosition = _clamp(_manualPosition!);
    }
  }

  Offset _clamp(Offset position) {
    final padding = widget.viewportPadding;
    final maximumLeft = math.max(
      padding.left,
      widget.viewportSize.width -
          padding.right -
          math.min(widget.estimatedSize.width, widget.viewportSize.width),
    );
    final maximumTop = math.max(
      padding.top,
      widget.viewportSize.height -
          padding.bottom -
          math.min(widget.estimatedSize.height, widget.viewportSize.height),
    );
    return Offset(
      position.dx.clamp(padding.left, maximumLeft),
      position.dy.clamp(padding.top, maximumTop),
    );
  }

  void _moveBy(Offset delta) {
    setState(() {
      _manualPosition = _clamp(
        (_manualPosition ?? widget.initialPosition) + delta,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final position = _manualPosition ?? widget.initialPosition;
    return _DraggableDialogScope(
      onMove: _moveBy,
      child: widget.builder(context, position, _manuallyMoved),
    );
  }
}

class _DraggableDialogScope extends InheritedWidget {
  const _DraggableDialogScope({required this.onMove, required super.child});

  final ValueChanged<Offset> onMove;

  static _DraggableDialogScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_DraggableDialogScope>();

  @override
  bool updateShouldNotify(_DraggableDialogScope oldWidget) =>
      onMove != oldWidget.onMove;
}

/// A title or empty-header region that moves its surrounding dialog.
///
/// Only pan gestures are claimed, so child buttons continue to receive taps.
class DraggableDialogDragHandle extends StatelessWidget {
  const DraggableDialogDragHandle({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scope = _DraggableDialogScope.maybeOf(context);
    if (scope == null) {
      return child;
    }
    return MouseRegion(
      cursor: SystemMouseCursors.move,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        dragStartBehavior: DragStartBehavior.down,
        onPanUpdate: (details) => scope.onMove(details.delta),
        child: child,
      ),
    );
  }
}

/// An [AlertDialog] whose title acts as a drag handle.
///
/// This intentionally forwards the standard dialog slots and spacing instead
/// of restyling them, keeping every map dialog visually unchanged.
class DraggableAlertDialog extends StatelessWidget {
  const DraggableAlertDialog({
    required this.identity,
    this.dialogKey,
    this.estimatedSize,
    this.icon,
    this.iconPadding,
    this.iconColor,
    this.title,
    this.titleIsDragHandle = true,
    this.titlePadding,
    this.titleTextStyle,
    this.content,
    this.contentPadding,
    this.contentTextStyle,
    this.actions,
    this.actionsPadding,
    this.actionsAlignment,
    this.actionsOverflowAlignment,
    this.actionsOverflowDirection,
    this.actionsOverflowButtonSpacing,
    this.buttonPadding,
    this.backgroundColor,
    this.elevation,
    this.shadowColor,
    this.surfaceTintColor,
    this.semanticLabel,
    this.insetPadding,
    this.clipBehavior = Clip.none,
    this.shape,
    this.scrollable = false,
    super.key,
  });

  final Object identity;
  final Key? dialogKey;
  final Size? estimatedSize;
  final Widget? icon;
  final EdgeInsetsGeometry? iconPadding;
  final Color? iconColor;
  final Widget? title;
  final bool titleIsDragHandle;
  final EdgeInsetsGeometry? titlePadding;
  final TextStyle? titleTextStyle;
  final Widget? content;
  final EdgeInsetsGeometry? contentPadding;
  final TextStyle? contentTextStyle;
  final List<Widget>? actions;
  final EdgeInsetsGeometry? actionsPadding;
  final MainAxisAlignment? actionsAlignment;
  final OverflowBarAlignment? actionsOverflowAlignment;
  final VerticalDirection? actionsOverflowDirection;
  final double? actionsOverflowButtonSpacing;
  final EdgeInsetsGeometry? buttonPadding;
  final Color? backgroundColor;
  final double? elevation;
  final Color? shadowColor;
  final Color? surfaceTintColor;
  final String? semanticLabel;
  final EdgeInsets? insetPadding;
  final Clip clipBehavior;
  final ShapeBorder? shape;
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    return DraggableDialogSurface(
      identity: identity,
      estimatedSize: estimatedSize,
      builder: (context, alignment) => AlertDialog(
        key: dialogKey,
        icon: icon,
        iconPadding: iconPadding,
        iconColor: iconColor,
        title: title == null
            ? null
            : titleIsDragHandle
            ? DraggableDialogDragHandle(child: title!)
            : title,
        titlePadding: titlePadding,
        titleTextStyle: titleTextStyle,
        content: content,
        contentPadding: contentPadding,
        contentTextStyle: contentTextStyle,
        actions: actions,
        actionsPadding: actionsPadding,
        actionsAlignment: actionsAlignment,
        actionsOverflowAlignment: actionsOverflowAlignment,
        actionsOverflowDirection: actionsOverflowDirection,
        actionsOverflowButtonSpacing: actionsOverflowButtonSpacing,
        buttonPadding: buttonPadding,
        backgroundColor: backgroundColor,
        elevation: elevation,
        shadowColor: shadowColor,
        surfaceTintColor: surfaceTintColor,
        semanticLabel: semanticLabel,
        insetPadding: insetPadding,
        clipBehavior: clipBehavior,
        shape: shape,
        alignment: alignment,
        scrollable: scrollable,
      ),
    );
  }
}
