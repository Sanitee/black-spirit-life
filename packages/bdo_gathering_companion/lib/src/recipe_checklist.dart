import 'package:flutter/widgets.dart';

typedef GatheringRecipeChecklistBuilder =
    Widget Function(
      BuildContext context,
      bool Function(String item) hasMappedSpot,
      ValueChanged<String> showSpot,
      VoidCallback close,
      ValueChanged<GatheringRecipeLocations> showLocations,
    );

class GatheringRecipePoint {
  const GatheringRecipePoint({
    required this.id,
    required this.x,
    required this.z,
    required this.label,
  });
  final String id, label;
  final double x, z;
}

/// Read-only source coordinates, not a curated rotation or spawn guarantee.
class GatheringRecipeLocations {
  const GatheringRecipeLocations({
    required this.item,
    required this.points,
    required this.sourceNote,
  });
  final String item, sourceNote;
  final List<GatheringRecipePoint> points;
}

/// Retained navigation request; does not touch session or inventory records.
class GatheringRecipeChecklistController extends ChangeNotifier {
  bool pending = false;
  void open() {
    pending = true;
    notifyListeners();
  }
}
