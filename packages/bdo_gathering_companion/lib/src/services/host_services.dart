import 'package:flutter/widgets.dart';

typedef GatheringExternalLinkOpener = Future<bool> Function(Uri uri);
typedef GatheringMinigameHelperOpener = Future<bool> Function();

@immutable
class GatheringHostServices {
  const GatheringHostServices({
    required this.openExternal,
    this.openMinigameHelper,
  });

  final GatheringExternalLinkOpener openExternal;
  final GatheringMinigameHelperOpener? openMinigameHelper;
}

class GatheringHostServicesScope extends InheritedWidget {
  const GatheringHostServicesScope({
    super.key,
    required this.services,
    required super.child,
  });

  final GatheringHostServices services;

  static GatheringHostServices of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<GatheringHostServicesScope>();
    assert(scope != null, 'GatheringHostServicesScope is missing.');
    return scope!.services;
  }

  @override
  bool updateShouldNotify(GatheringHostServicesScope oldWidget) =>
      services != oldWidget.services;
}

Future<bool> openGatheringExternalLink(
  BuildContext context,
  String value,
) async {
  final uri = Uri.tryParse(value);
  if (uri == null ||
      !const {'https', 'http'}.contains(uri.scheme) ||
      uri.host.isEmpty) {
    return false;
  }
  return GatheringHostServicesScope.of(context).openExternal(uri);
}
