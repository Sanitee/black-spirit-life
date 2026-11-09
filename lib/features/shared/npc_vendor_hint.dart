import '../../app/state/planner_application_controller.dart';

/// Display-only vendor information. A known source does not imply a known
/// silver price (some shops use another currency).
String? npcVendorHint(ModeFeatureController controller, String name) {
  final acquisition = controller.resolveItemAcquisition(name);
  if (const {'removed', 'temporarily_archived'}.contains(acquisition?.status)) {
    return null;
  }
  final source = controller.resolveItemSource(name);
  final vendor = source.vendor?.trim() ?? '';
  final role = source.role?.trim() ?? '';
  final location = source.location?.trim() ?? '';
  if (vendor.isNotEmpty) {
    return [
      role.isNotEmpty && role.toLowerCase() != vendor.toLowerCase()
          ? '$vendor · $role'
          : vendor,
      if (location.isNotEmpty) location,
    ].join(' · ');
  }
  final routes = acquisition?.routes ?? const [];
  final purchases = routes.where(
    (route) => route.isDisplayable && route.kind == 'npc_purchase',
  );
  if (purchases.isNotEmpty) {
    return purchases
        .map(
          (route) => route.summary
              .trim()
              .replaceFirst(
                RegExp(
                  r'^(Buy|Purchase) from (a |an |the )?',
                  caseSensitive: false,
                ),
                '',
              )
              .replaceFirst(RegExp(r'\.$'), '')
              .replaceAll(RegExp(r'\s*\n\s*'), ', '),
        )
        .toSet()
        .join('\n');
  }
  return source.npcPrice > 0 ? 'NPC vendor' : null;
}
