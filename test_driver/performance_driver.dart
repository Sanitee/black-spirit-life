import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver(
  responseDataCallback: (data) async {
    await writeResponseData(
      data ?? <String, dynamic>{},
      testOutputFilename: 'bdo_profile_performance',
    );
  },
);
