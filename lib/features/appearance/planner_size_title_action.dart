import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../app/state/planner_application_controller.dart';
import 'content_size_popover.dart';
import 'content_size_title_action.dart';
import 'planner_appearance_popover.dart';

/// Preserves the Planner's title action and popup contract.
class PlannerSizeTitleAction extends StatelessWidget {
  const PlannerSizeTitleAction({
    required this.controller,
    required this.maximum,
    required this.onOpen,
    super.key,
  });
  final PlannerApplicationController controller;
  final ValueListenable<double> maximum;
  final VoidCallback onOpen;
  static const triggerKey = ValueKey<String>('planner-size-title-action');
  @override
  Widget build(BuildContext context) => ContentSizeTitleAction(
    scale: controller.plannerContentScale,
    maximum: maximum,
    label: 'Planner size',
    overlayId: 'planner-size',
    triggerKey: triggerKey,
    popoverKeys: const ContentSizePopoverKeys('planner-appearance'),
    onPreview: controller.previewPlannerContentScale,
    onCommit: controller.commitPlannerContentScale,
    onReset: () => controller.commitPlannerContentScale(1),
    onOpen: onOpen,
    popoverBuilder: (value, maximum, close) => PlannerAppearancePopover(
      value: value,
      maximum: maximum,
      onChanged: controller.previewPlannerContentScale,
      onChangeEnd: controller.commitPlannerContentScale,
      onReset: () => controller.commitPlannerContentScale(1),
      onClose: close,
    ),
  );
}
