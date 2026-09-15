import 'package:bdo_fishing_core/bdo_fishing_core.dart';
import 'package:flutter/widgets.dart';

/// The accepted standalone Fish Companion beneath the shared application tabs.
class FishMapWorkspace extends StatelessWidget {
  const FishMapWorkspace({
    required this.runtimeHost,
    this.onPageStatusChanged,
    this.pageReadinessOverride,
    super.key,
  });

  final FishCompanionRuntimeHost runtimeHost;
  final ValueChanged<FishCompanionPageStatus>? onPageStatusChanged;
  final FishCompanionPageReadinessOverride? pageReadinessOverride;

  @override
  Widget build(BuildContext context) => FishCompanionView(
    runtimeHost: runtimeHost,
    onPageStatusChanged: onPageStatusChanged,
    pageReadinessOverride: pageReadinessOverride,
  );
}
