import 'dart:io';

import 'package:bdo_craft_planner_flutter/app/update/beta_update.dart';
import 'package:bdo_craft_planner_flutter/app/update/beta_update_process_service.dart';
import 'package:bdo_craft_planner_flutter/app_identity.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'isolated service checks, downloads a delta, and arms apply by PID',
    () async {
      final helper = _RecordingHelperClient();
      final service = ProcessBetaUpdateService(
        source: r'C:\private-beta-feed',
        currentVersion: '0.1.0-beta.5',
        plannerProcessId: 4242,
        helperClient: helper,
      );
      final events = <BetaUpdateSnapshot>[];
      final subscription = service.snapshots.listen(events.add);

      expect((await service.currentStatus()).phase, BetaUpdatePhase.idle);
      final available = await service.checkForUpdates(r'C:\private-beta-feed');
      expect(available.phase, BetaUpdatePhase.available);
      expect(available.usesDelta, isTrue);
      expect(available.sizeBytes, 2610822);
      expect(available.fullSizeBytes, 66854193);

      expect((await service.downloadUpdate()).phase, BetaUpdatePhase.ready);
      expect((await service.restartAndApply()).phase, BetaUpdatePhase.applying);

      expect(
        helper.requests.map((request) => request.operation),
        <BetaUpdaterHelperOperation>[
          BetaUpdaterHelperOperation.status,
          BetaUpdaterHelperOperation.check,
          BetaUpdaterHelperOperation.download,
          BetaUpdaterHelperOperation.prepareApply,
        ],
      );
      expect(helper.requests[2].targetVersion, '0.1.0-beta.6');
      expect(helper.requests[2].plannerProcessId, 0);
      expect(helper.requests[3].targetVersion, '0.1.0-beta.6');
      expect(helper.requests[3].plannerProcessId, 4242);
      expect(events.any((snapshot) => snapshot.progress == .5), isTrue);

      await subscription.cancel();
      await service.dispose();
      await helper.dispose();
    },
  );

  test('service rejects a source change before starting the helper', () async {
    final helper = _RecordingHelperClient();
    final service = ProcessBetaUpdateService(
      source: r'C:\private-beta-feed',
      helperClient: helper,
    );

    expect(() => service.checkForUpdates(r'C:\other-feed'), throwsStateError);
    expect(helper.requests, isEmpty);

    await service.dispose();
    await helper.dispose();
  });

  test(
    'a fresh check forgets an obsolete target selected before retry',
    () async {
      final helper = _AdvancingHelperClient();
      final service = ProcessBetaUpdateService(
        source: r'C:\private-beta-feed',
        currentVersion: '0.1.0-beta.5',
        helperClient: helper,
      );

      expect(
        (await service.checkForUpdates(r'C:\private-beta-feed')).targetVersion,
        '0.1.0-beta.6',
      );
      expect(
        (await service.checkForUpdates(r'C:\private-beta-feed')).targetVersion,
        '0.1.0-beta.7',
      );
      expect(helper.requests[0].targetVersion, isEmpty);
      expect(helper.requests[1].targetVersion, isEmpty);
      await service.downloadUpdate();
      expect(helper.requests.last.targetVersion, '0.1.0-beta.7');

      await service.dispose();
      await helper.dispose();
    },
  );

  test('identity keeps in-process updates off and helper updates on', () {
    expect(AppIdentity.inProcessBetaUpdatesEnabled, isFalse);
    expect(AppIdentity.outOfProcessBetaUpdatesEnabled, isTrue);
    expect(AppIdentity.windowsUpdaterHelperName, 'BlackSpiritLifeUpdater.exe');
  });

  test(
    'fresh Release helper rejects a portable bundle without crashing',
    () async {
      final helper = WindowsBetaUpdaterHelperClient(
        helperPath:
            'build${Platform.pathSeparator}windows${Platform.pathSeparator}'
            'x64${Platform.pathSeparator}runner${Platform.pathSeparator}'
            'Release${Platform.pathSeparator}'
            '${AppIdentity.windowsUpdaterHelperName}',
      );

      final snapshot = await helper.run(
        const BetaUpdaterHelperRequest(
          operation: BetaUpdaterHelperOperation.status,
          source: r'C:\private-beta-feed',
          currentVersion: AppIdentity.applicationVersion,
        ),
        onSnapshot: (_) {},
      );

      expect(snapshot.phase, BetaUpdatePhase.unsupported);
      expect(snapshot.portable, isTrue);
      await helper.dispose();
    },
    skip: !File(
      'build${Platform.pathSeparator}windows${Platform.pathSeparator}'
      'x64${Platform.pathSeparator}runner${Platform.pathSeparator}'
      'Release${Platform.pathSeparator}'
      '${AppIdentity.windowsUpdaterHelperName}',
    ).existsSync(),
  );
}

class _RecordingHelperClient implements BetaUpdaterHelperClient {
  final List<BetaUpdaterHelperRequest> requests = <BetaUpdaterHelperRequest>[];
  bool disposed = false;

  @override
  Future<BetaUpdateSnapshot> run(
    BetaUpdaterHelperRequest request, {
    required ValueChanged<BetaUpdateSnapshot> onSnapshot,
  }) async {
    requests.add(request);
    return switch (request.operation) {
      BetaUpdaterHelperOperation.status => const BetaUpdateSnapshot(
        phase: BetaUpdatePhase.idle,
        installed: true,
        portable: false,
        currentVersion: '0.1.0-beta.5',
        appId: 'BlackSpiritLife.App',
      ),
      BetaUpdaterHelperOperation.check => const BetaUpdateSnapshot(
        phase: BetaUpdatePhase.available,
        installed: true,
        portable: false,
        currentVersion: '0.1.0-beta.5',
        appId: 'BlackSpiritLife.App',
        targetVersion: '0.1.0-beta.6',
        sizeBytes: 2610822,
        fullSizeBytes: 66854193,
        deltaCount: 1,
      ),
      BetaUpdaterHelperOperation.download => () {
        onSnapshot(
          const BetaUpdateSnapshot(
            phase: BetaUpdatePhase.downloading,
            targetVersion: '0.1.0-beta.6',
            sizeBytes: 2610822,
            fullSizeBytes: 66854193,
            deltaCount: 1,
            progress: .5,
          ),
        );
        return const BetaUpdateSnapshot(
          phase: BetaUpdatePhase.ready,
          targetVersion: '0.1.0-beta.6',
          sizeBytes: 2610822,
          fullSizeBytes: 66854193,
          deltaCount: 1,
          progress: 1,
        );
      }(),
      BetaUpdaterHelperOperation.prepareApply => const BetaUpdateSnapshot(
        phase: BetaUpdatePhase.applying,
        targetVersion: '0.1.0-beta.6',
        progress: 1,
      ),
    };
  }

  @override
  Future<void> dispose() async {
    disposed = true;
  }
}

class _AdvancingHelperClient implements BetaUpdaterHelperClient {
  final List<BetaUpdaterHelperRequest> requests = <BetaUpdaterHelperRequest>[];
  var _checks = 0;

  @override
  Future<BetaUpdateSnapshot> run(
    BetaUpdaterHelperRequest request, {
    required ValueChanged<BetaUpdateSnapshot> onSnapshot,
  }) async {
    requests.add(request);
    if (request.operation == BetaUpdaterHelperOperation.check) {
      _checks += 1;
      return BetaUpdateSnapshot(
        phase: BetaUpdatePhase.available,
        targetVersion: _checks == 1 ? '0.1.0-beta.6' : '0.1.0-beta.7',
      );
    }
    return BetaUpdateSnapshot(
      phase: BetaUpdatePhase.ready,
      targetVersion: request.targetVersion,
      progress: 1,
    );
  }

  @override
  Future<void> dispose() async {}
}
