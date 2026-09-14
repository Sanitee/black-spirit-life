import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver(
  responseDataCallback: (data) async {
    final path = Platform.environment['BSL_PROFILE_REPORT'];
    if (path == null || path.isEmpty) {
      throw StateError('Set BSL_PROFILE_REPORT.');
    }
    final file = File(path);
    if (await file.exists()) {
      throw StateError('Profile evidence already exists: $path');
    }
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(data));
  },
);
