import 'package:flutter/foundation.dart';

enum BdoResourceMapFocusSource {
  manualGathering,
  workerNodes,

  /// Shows every source-recorded NPC map point that sells the requested item.
  npcVendors,

  /// Opens the worker-network material picker with this resource already
  /// selected, instead of stopping at a passive worker-node search result.
  workerNodePlanner,
}

class BdoResourceMapFocusRequest {
  const BdoResourceMapFocusRequest({
    required this.materialName,
    required this.source,
    this.resourceId,
  });

  final String materialName;
  final String? resourceId;
  final BdoResourceMapFocusSource source;
}

/// Sends material lookups to a mounted resource map.
///
/// The latest request is retained, so callers may issue [focus] immediately
/// before switching to the map workspace. Repeating the same request still
/// increments [revision] and refocuses the map.
class BdoResourceMapController extends ChangeNotifier {
  BdoResourceMapFocusRequest? get request => _request;
  BdoResourceMapFocusRequest? _request;

  int get revision => _revision;
  int _revision = 0;

  void focus(BdoResourceMapFocusRequest request) {
    _request = request;
    _revision += 1;
    notifyListeners();
  }
}
