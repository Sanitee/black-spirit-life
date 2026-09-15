import 'package:flutter/material.dart';

import '../model/resource_map_data.dart';

/// The same original game artwork used by the corresponding map markers.
int bdoWorkerActivitySourceIconType(BdoWorkerActivity activity) =>
    switch (activity) {
      BdoWorkerActivity.mining => 7,
      BdoWorkerActivity.farming => 4,
      BdoWorkerActivity.lumbering => 8,
      BdoWorkerActivity.gathering => 6,
      BdoWorkerActivity.fishing => 11,
      BdoWorkerActivity.excavation => 15,
    };

class BdoWorkerActivityImage extends StatelessWidget {
  const BdoWorkerActivityImage({
    super.key,
    required this.activity,
    this.size = 26,
  });
  final BdoWorkerActivity activity;
  final double size;

  @override
  Widget build(BuildContext context) => BdoNodeTypeImage(
    sourceIconType: bdoWorkerActivitySourceIconType(activity),
    size: size,
  );
}

class BdoNodeTypeImage extends StatelessWidget {
  const BdoNodeTypeImage({
    super.key,
    required this.sourceIconType,
    this.size = 26,
  });
  final int sourceIconType;
  final double size;

  @override
  Widget build(BuildContext context) => Image.asset(
    bdoNodeIconAssetPath(sourceIconType, active: true),
    package: 'bdo_map_core',
    width: size,
    height: size,
    fit: BoxFit.contain,
    filterQuality: FilterQuality.medium,
    excludeFromSemantics: true,
  );
}

// Only a fallback for canvas markers whose source texture cannot be loaded.
IconData bdoWorkerActivityIcon(BdoWorkerActivity activity) {
  return switch (activity) {
    BdoWorkerActivity.mining => Icons.diamond_outlined,
    BdoWorkerActivity.farming => Icons.grass_rounded,
    BdoWorkerActivity.lumbering => Icons.forest_rounded,
    BdoWorkerActivity.gathering => Icons.spa_rounded,
    BdoWorkerActivity.fishing => Icons.set_meal_outlined,
    BdoWorkerActivity.excavation => Icons.layers_outlined,
  };
}

Color bdoWorkerActivityColor(BdoWorkerActivity activity) {
  return switch (activity) {
    BdoWorkerActivity.mining => const Color(0xFFE0B763),
    BdoWorkerActivity.farming => const Color(0xFF82C995),
    BdoWorkerActivity.lumbering => const Color(0xFF5CB89D),
    BdoWorkerActivity.gathering => const Color(0xFFB395DA),
    BdoWorkerActivity.fishing => const Color(0xFF70BCE5),
    BdoWorkerActivity.excavation => const Color(0xFFE08C68),
  };
}
