import 'package:integration_test/integration_test_driver.dart';

// The opt-in test writes its own uniquely named evidence and isolated cache.
Future<void> main() => integrationDriver(responseDataCallback: (_) async {});
