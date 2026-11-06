import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Review capture only: this is not comparison against approved goldens.
/// Normal runs retain the standard comparator; the explicit review mode writes
/// an external mirror so later assertions can run before any fixtures change.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  final root = Platform.environment['APP_GOLDEN_REVIEW_DIR'];
  if (root != null) {
    if (!autoUpdateGoldenFiles || !Directory(root).isAbsolute) {
      throw StateError(
        'APP_GOLDEN_REVIEW_DIR needs an absolute path and --update-goldens.',
      );
    }
    final destination = Directory(root).absolute.uri;
    if (destination.toString().toLowerCase().startsWith(
      Directory.current.absolute.uri.toString().toLowerCase(),
    )) {
      throw StateError('Review images must remain outside application source.');
    }
    goldenFileComparator = LocalFileComparator(
      destination.resolve('review.dart'),
    );
  }
  await testMain();
}
