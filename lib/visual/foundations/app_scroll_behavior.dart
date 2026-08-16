import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;

/// Keeps app-owned scrolling available without drawing platform scrollbars.
///
/// Lists and panels retain their controllers, keyboard navigation, and scroll
/// semantics. Traditional notched mouse-wheel steps ease between positions;
/// precise pointer input stays direct, reduced motion is honored, and only the
/// automatically injected visual scrollbar chrome is suppressed.
class AppScrollBehavior extends MaterialScrollBehavior {
  const AppScrollBehavior();

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    final decorated = super.buildOverscrollIndicator(context, child, details);
    final controller = details.controller;
    if (controller == null) return decorated;
    return _AppSmoothWheelViewport(
      controller: controller,
      direction: details.direction,
      child: decorated,
    );
  }

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) => child;
}

/// Smooths traditional notched mouse-wheel steps without delaying precise
/// trackpad/direct-manipulation input.
///
/// Flutter applies pointer-wheel movement as an immediate position jump. This
/// wrapper observes the position chosen by Flutter, restores the pre-wheel
/// position in the same event turn, and eases to the accumulated target. It
/// deliberately does not claim the pointer signal, so Flutter's nearest-
/// scrollable resolver continues to prevent nested lists from double-scrolling.
class _AppSmoothWheelViewport extends StatefulWidget {
  const _AppSmoothWheelViewport({
    required this.controller,
    required this.direction,
    required this.child,
  });

  final ScrollController controller;
  final AxisDirection direction;
  final Widget child;

  @override
  State<_AppSmoothWheelViewport> createState() =>
      _AppSmoothWheelViewportState();
}

class _AppSmoothWheelViewportState extends State<_AppSmoothWheelViewport>
    with SingleTickerProviderStateMixin {
  static const double _offsetEpsilon = 0.01;
  static const double _minimumWheelStep = 20;
  static const double _settledDistance = 0.12;
  static const double _responseSeconds = .045;

  double? _targetOffset;
  Ticker? _ticker;
  Duration _lastTick = Duration.zero;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick);
  }

  @override
  void didUpdateWidget(_AppSmoothWheelViewport oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller) ||
        oldWidget.direction != widget.direction) {
      _cancelIntent(stopAnimation: false);
    }
  }

  @override
  void dispose() {
    _ticker?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Listener(
    behavior: HitTestBehavior.translucent,
    onPointerDown: (_) => _cancelIntent(stopAnimation: true),
    onPointerPanZoomStart: (_) => _cancelIntent(stopAnimation: true),
    onPointerSignal: _handlePointerSignal,
    child: widget.child,
  );

  void _handlePointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || !_shouldSmooth(event)) return;
    final controller = widget.controller;
    if (!controller.hasClients || controller.positions.length != 1) return;
    final position = controller.position;
    if (!position.hasContentDimensions) return;
    final before = position.pixels;
    final logicalDelta = _logicalDelta(event.scrollDelta);
    if (logicalDelta.abs() < _minimumWheelStep) return;

    // Flutter resolves the nearest interested Scrollable only after pointer
    // signal dispatch. Waiting one microtask lets us see whether this exact
    // position won; parent/nested scrollables that did not move do nothing.
    scheduleMicrotask(() {
      if (!mounted || !controller.hasClients) return;
      if (controller.positions.length != 1 ||
          !identical(controller.position, position)) {
        return;
      }
      final nativeTarget = position.pixels;
      if ((nativeTarget - before).abs() < _offsetEpsilon) return;

      final accumulatedFrom = _targetOffset ?? before;
      final target = (accumulatedFrom + logicalDelta)
          .clamp(position.minScrollExtent, position.maxScrollExtent)
          .toDouble();
      if ((target - before).abs() < _offsetEpsilon) {
        _targetOffset = null;
        return;
      }

      // This restoration occurs before the next frame, so there is no visible
      // snap. jumpTo also cancels Flutter's one-step pointer activity before
      // the single accumulated animation begins.
      position.jumpTo(before);
      _targetOffset = target;
      final ticker = _ticker;
      if (ticker != null && !ticker.isActive) {
        _lastTick = Duration.zero;
        ticker.start();
      }
    });
  }

  void _tick(Duration elapsed) {
    final target = _targetOffset;
    final controller = widget.controller;
    if (target == null ||
        !controller.hasClients ||
        controller.positions.length != 1) {
      _stopTicker();
      return;
    }
    final position = controller.position;
    final remaining = target - position.pixels;
    if (remaining.abs() <= _settledDistance) {
      position.correctPixels(target);
      position.notifyListeners();
      _targetOffset = null;
      _stopTicker();
      return;
    }

    // Chase the accumulated destination once per display frame. Unlike
    // repeatedly starting animateTo, this keeps the same motion alive when
    // another wheel notch arrives, so rapid scrolling does not lose velocity
    // or pause between steps. The exponential response is refresh-rate
    // independent and therefore feels the same at 60, 120, or 144 Hz.
    final elapsedSeconds = _lastTick == Duration.zero
        ? 1 / 60
        : ((elapsed - _lastTick).inMicroseconds /
                  Duration.microsecondsPerSecond)
              .clamp(1 / 240, .05)
              .toDouble();
    _lastTick = elapsed;
    final progress = 1 - math.exp(-elapsedSeconds / _responseSeconds);
    final next = position.pixels + remaining * progress;
    position.correctPixels(
      next.clamp(position.minScrollExtent, position.maxScrollExtent).toDouble(),
    );
    position.notifyListeners();
  }

  bool _shouldSmooth(PointerScrollEvent event) {
    if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) return false;
    // Trackpad pan/zoom gestures and high-resolution wheel deltas already move
    // continuously. Re-animating them adds lag and fights direct manipulation.
    return event.kind == PointerDeviceKind.mouse;
  }

  double _logicalDelta(Offset scrollDelta) {
    final axis = axisDirectionToAxis(widget.direction);
    final raw = switch (axis) {
      Axis.vertical => scrollDelta.dy,
      Axis.horizontal => scrollDelta.dx != 0 ? scrollDelta.dx : scrollDelta.dy,
    };
    return switch (widget.direction) {
      AxisDirection.down || AxisDirection.right => raw,
      AxisDirection.up || AxisDirection.left => -raw,
    };
  }

  void _stopTicker() {
    final ticker = _ticker;
    if (ticker != null && ticker.isActive) ticker.stop();
    _lastTick = Duration.zero;
  }

  void _cancelIntent({required bool stopAnimation}) {
    _targetOffset = null;
    _stopTicker();
    if (!stopAnimation ||
        !widget.controller.hasClients ||
        widget.controller.positions.length != 1) {
      return;
    }
    final position = widget.controller.position;
    if (position.isScrollingNotifier.value) {
      position.jumpTo(position.pixels);
    }
  }
}
