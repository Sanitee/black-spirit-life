import 'package:flutter/widgets.dart';

abstract final class PlannerActionKeys {
  static const p01 = ValueKey<String>('P01');
  static const p02 = ValueKey<String>('P02');
  static const p03 = ValueKey<String>('P03');
  static const p04 = ValueKey<String>('P04');
  static const p05 = ValueKey<String>('P05');
  static const p06 = ValueKey<String>('P06');
  static const p07 = ValueKey<String>('P07');
  static const p08 = ValueKey<String>('P08');
  static const p09 = ValueKey<String>('P09');
  static const p10 = ValueKey<String>('P10');
  static const p11 = ValueKey<String>('P11');
  static const p12 = ValueKey<String>('P12');
  static const p13 = ValueKey<String>('P13');
  static const p14 = ValueKey<String>('P14');
  static const p15 = ValueKey<String>('P15');
  static const p16 = ValueKey<String>('P16');
  static const p17 = ValueKey<String>('P17');
  static const p18 = ValueKey<String>('P18');
  static const p19 = ValueKey<String>('P19');
  static const p20 = ValueKey<String>('P20');
  static const p21 = ValueKey<String>('P21');
  static const p22 = ValueKey<String>('P22');

  static Key row(String actionId, String stableId) =>
      ValueKey<String>('$actionId:$stableId');

  static Key mapLookupRegion(String stableId) =>
      ValueKey<String>('planner-map-lookup-region:$stableId');

  static Key mapLookupAction(String stableId, String source) =>
      ValueKey<String>('planner-map-lookup-action:$stableId:$source');
}

abstract final class BonusActionKeys {
  static const b01 = ValueKey<String>('B01');
  static const b02 = ValueKey<String>('B02');
  static const b03 = ValueKey<String>('B03');
  static const b04 = ValueKey<String>('B04');
  static const b05 = ValueKey<String>('B05');
  static const b06 = ValueKey<String>('B06');
  static const b07 = ValueKey<String>('B07');
}
