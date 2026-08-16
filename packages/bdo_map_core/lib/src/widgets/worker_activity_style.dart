import 'package:flutter/material.dart';

import '../model/resource_map_data.dart';

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
