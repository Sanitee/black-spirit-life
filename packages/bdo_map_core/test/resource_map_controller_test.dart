import 'package:bdo_map_core/bdo_map_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('map controller retains and repeats identical focus requests', () {
    final controller = BdoResourceMapController();
    addTearDown(controller.dispose);
    var notifications = 0;
    controller.addListener(() => notifications += 1);
    const request = BdoResourceMapFocusRequest(
      materialName: 'Ash Timber',
      resourceId: 'ash-timber',
      source: BdoResourceMapFocusSource.workerNodes,
    );

    controller
      ..focus(request)
      ..focus(request);

    expect(controller.request, same(request));
    expect(controller.revision, 2);
    expect(notifications, 2);
  });
}
