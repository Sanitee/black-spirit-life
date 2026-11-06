import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Optional review capture, never a passing comparison against approved goldens.
/// With --update-goldens, write a separate external mirror so all later workflow
/// assertions and images run without replacing the checked-in reference files.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  final root = Platform.environment['MAP_GOLDEN_REVIEW_DIR'];
  if (root != null) {
    if (!autoUpdateGoldenFiles || !Directory(root).isAbsolute) {
      throw StateError(
        'MAP_GOLDEN_REVIEW_DIR requires an absolute path and --update-goldens.',
      );
    }
    final destination = Directory(root).absolute.uri;
    final source = Directory.current.absolute.uri;
    if (destination.toString().toLowerCase().startsWith(
      source.toString().toLowerCase(),
    )) {
      throw StateError('Review images must stay outside the package source.');
    }
    goldenFileComparator = LocalFileComparator(
      destination.resolve('review.dart'),
    );
  }
  await testMain();
}
