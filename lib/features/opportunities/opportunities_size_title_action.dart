import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../appearance/content_size_popover.dart';
import '../appearance/content_size_title_action.dart';
import 'opportunities_controller.dart';

class OpportunitiesSizeTitleAction extends StatelessWidget {
  const OpportunitiesSizeTitleAction({
    required this.controller,
    required this.maximum,
    super.key,
  });
  final OpportunitiesController controller;
  final ValueListenable<double> maximum;
  static const triggerKey = ValueKey<String>('opportunities-size-title-action');
  static const popoverKeys = ContentSizePopoverKeys('opportunities-appearance');

  @override
  Widget build(BuildContext context) => ContentSizeTitleAction(
    label: 'Opportunities size',
    heading: 'Size',
    overlayId: 'opportunities-size',
    triggerKey: triggerKey,
    popoverKeys: popoverKeys,
    scale: controller.contentScale,
    maximum: maximum,
    onPreview: controller.previewContentScale,
    onCommit: controller.commitContentScale,
    onReset: () => controller.commitContentScale(1),
  );
}
