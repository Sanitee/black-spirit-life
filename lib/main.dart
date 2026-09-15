import 'package:bdo_gathering_companion/bdo_gathering_companion.dart';

import 'app/bootstrap.dart';

void main(List<String> args) {
  if (isGatheringReferenceMode(args)) {
    runGatheringReferenceMode(args);
    return;
  }
  runBdoCraftPlanner();
}
