// A `flutter_test_config.dart` whose `testExecutable` the `flutter test`
// bootstrap could not call: it takes an `int`, not the test's `main`. The file
// name alone earns no exemption, so it is reported — as is the dead helper
// beside it. Expected findings: both declarations.

Future<void> testExecutable(int retries) async {}

void deadHelperNextToConfig() {}
