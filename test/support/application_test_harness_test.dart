import 'package:flutter_test/flutter_test.dart';

import 'application_test_harness.dart';

void main() {
  test('builds a complete isolated application bundle', () async {
    final harness = await ApplicationTestHarness.create();
    try {
      expect(harness.bundle.catalog.alchemy.items, isNotEmpty);
      expect(harness.bundle.controller.active.craftableNames, isNotEmpty);
    } finally {
      await harness.dispose();
    }
  });
}
