import 'package:flutter/rendering.dart';

import '../engine/map_camera.dart';
import '../model/map_geometry.dart';

/// Base delegate for retained widget overlays that follow the map camera.
///
/// Camera changes repaint the [Flow] directly, so subclasses can reposition
/// existing children while panning without rebuilding their widget trees.
abstract class BdoMapCameraFlowDelegate extends FlowDelegate {
  BdoMapCameraFlowDelegate({required this.cameraController})
    : super(repaint: cameraController);

  final BdoMapCameraController cameraController;

  /// Converts a world point into this flow's current screen coordinate space.
  Offset worldToScreen(FlowPaintingContext context, BdoMapPoint worldPoint) =>
      cameraController.worldToScreen(worldPoint, context.size);

  /// Returns a laid-out child's size, or [Size.zero] when it is unavailable.
  Size childSize(FlowPaintingContext context, int index) =>
      context.getChildSize(index) ?? Size.zero;

  /// Paints a child with its top-left corner at [topLeft].
  void paintChildAt(
    FlowPaintingContext context,
    int index, {
    required Offset topLeft,
    double opacity = 1,
  }) {
    context.paintChild(
      index,
      transform: Matrix4.translationValues(topLeft.dx, topLeft.dy, 0),
      opacity: opacity,
    );
  }

  @override
  BoxConstraints getConstraintsForChild(int i, BoxConstraints constraints) =>
      BoxConstraints.loose(constraints.biggest);

  @override
  bool shouldRelayout(covariant BdoMapCameraFlowDelegate oldDelegate) =>
      oldDelegate.cameraController != cameraController;

  @override
  bool shouldRepaint(covariant BdoMapCameraFlowDelegate oldDelegate) =>
      oldDelegate.cameraController != cameraController;
}
