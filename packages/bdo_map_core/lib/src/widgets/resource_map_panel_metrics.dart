import 'package:flutter/widgets.dart';

/// Compact reading sizes shared by map panels and their navigation.
///
/// Panels adapt to their content and available viewport. They do not reduce
/// these sizes to make a fixed-height or fixed-width container fit.
abstract final class ResourceMapPanelMetrics {
  // Match the normal-scale Gathering map controls, not enlarged-text captures.
  static const double primary = 14;
  static const double secondary = 12.5;
  static const double heading = 16;
  static const double artwork = 30;
  static const double navigationArtwork = 28;

  /// Secondary acquisition indicators must not dominate the item artwork.
  static const double gatheringToolArtwork = 27;
  static const double rowHeight = 40;
  static const double menuWidth = 266;

  // Gathering's main spot names use 16/w700, distinct from utility labels.
  static const double optionLabel = 16;
  static const double optionArtwork = 36;
  static const double optionHeight = 50;
  static const double optionGap = 7;

  static const double controlGlyph = 19;
  static const double controlTarget = 32;

  static double searchHeight(BuildContext context) =>
      (MediaQuery.textScalerOf(context).scale(primary) * 1.2 + 18).clamp(
        rowHeight,
        double.infinity,
      );
}
