import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import '../flutter_test_config.dart' as review;
import '../support/native_preview_fonts.dart';

/// Desktop visual regressions must exercise real text metrics, not Ahem blocks.
/// Keep the external review mirror: captures are inspected before acceptance.
Future<void> testExecutable(FutureOr<void> Function() testMain) =>
    review.testExecutable(() async {
      setUpAll(loadNativePreviewFonts);
      await testMain();
    });
