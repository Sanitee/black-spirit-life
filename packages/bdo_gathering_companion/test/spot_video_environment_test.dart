import 'package:bdo_gathering_companion/src/widgets/spot_video_player.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('spot video WebView environment fallback', () {
    test('recognizes only the shared-environment platform error', () {
      expect(
        canReuseExistingSpotVideoEnvironment(
          PlatformException(code: 'environment_already_initialized'),
        ),
        isTrue,
      );
      expect(
        canReuseExistingSpotVideoEnvironment(
          PlatformException(code: 'environment_creation_failed'),
        ),
        isFalse,
      );
      expect(
        canReuseExistingSpotVideoEnvironment(
          StateError('not a platform error'),
        ),
        isFalse,
      );
    });

    test(
      'reuses the shared environment without clearing its browser data',
      () async {
        final ownership = await initializeSpotVideoEnvironment(() async {
          throw PlatformException(code: 'environment_already_initialized');
        });

        expect(ownership, SpotVideoEnvironmentOwnership.shared);
        expect(ownership.clearsBrowserDataOnClose, isFalse);
      },
    );

    test(
      'keeps isolated-profile cleanup when initialization succeeds',
      () async {
        var initialized = false;
        final ownership = await initializeSpotVideoEnvironment(() async {
          initialized = true;
        });

        expect(initialized, isTrue);
        expect(ownership, SpotVideoEnvironmentOwnership.isolated);
        expect(ownership.clearsBrowserDataOnClose, isTrue);
      },
    );

    test('does not hide unrelated environment failures', () async {
      await expectLater(
        initializeSpotVideoEnvironment(() async {
          throw PlatformException(code: 'environment_creation_failed');
        }),
        throwsA(
          isA<PlatformException>().having(
            (error) => error.code,
            'code',
            'environment_creation_failed',
          ),
        ),
      );
    });
  });
}
