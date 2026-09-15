import 'dart:io';

import 'package:bdo_gathering_companion/bdo_gathering_companion.dart';
import 'package:flutter/widgets.dart';

class GatheringWorkspace extends StatelessWidget {
  const GatheringWorkspace({
    required this.dataDirectory,
    this.durabilityController,
    this.sharedMarketLoader,
    this.sharedMarketUpdates,
    this.marketFreshFor = const Duration(minutes: 2),
    super.key,
  });

  final Directory dataDirectory;
  final GatheringDurabilityController? durabilityController;
  final GatheringSharedMarketLoader? sharedMarketLoader;
  final Stream<GatheringMarketReceipt>? sharedMarketUpdates;
  final Duration marketFreshFor;

  @override
  Widget build(BuildContext context) => GatheringCompanionFeature(
    dataDirectory: dataDirectory,
    durabilityController: durabilityController,
    sharedMarketLoader: sharedMarketLoader,
    sharedMarketUpdates: sharedMarketUpdates,
    marketFreshFor: marketFreshFor,
    prepareDataDirectory: (directory) =>
        migrateLegacyGatheringSessions(destinationDirectory: directory),
  );
}

@visibleForTesting
Future<void> migrateLegacyGatheringSessions({
  required Directory destinationDirectory,
  Directory? legacyDirectory,
}) async {
  final roamingPath = Platform.environment['APPDATA']?.trim();
  final sourceDirectory =
      legacyDirectory ??
      (roamingPath == null || roamingPath.isEmpty
          ? null
          : Directory(
              '$roamingPath${Platform.pathSeparator}BDO Gathering Companion',
            ));
  if (sourceDirectory == null ||
      sourceDirectory.absolute.path.toLowerCase() ==
          destinationDirectory.absolute.path.toLowerCase()) {
    return;
  }

  final source = File(
    '${sourceDirectory.path}${Platform.pathSeparator}sessions.json',
  );
  final destination = File(
    '${destinationDirectory.path}${Platform.pathSeparator}sessions.json',
  );
  if (!await source.exists() || await destination.exists()) return;

  await destinationDirectory.create(recursive: true);
  await _copyGatheringFileWithoutOverwrite(source, destination);

  final sourceBackup = File('${source.path}.bak');
  final destinationBackup = File('${destination.path}.bak');
  if (await sourceBackup.exists() && !await destinationBackup.exists()) {
    await _copyGatheringFileWithoutOverwrite(sourceBackup, destinationBackup);
  }
}

Future<void> _copyGatheringFileWithoutOverwrite(
  File source,
  File destination,
) async {
  if (await destination.exists()) return;
  final temporary = File('${destination.path}.legacy-import');
  try {
    await source.copy(temporary.path);
    if (await destination.exists()) return;
    await temporary.rename(destination.path);
  } finally {
    if (await temporary.exists()) await temporary.delete();
  }
}
