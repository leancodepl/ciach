// The `flutter test` configuration hook. The test runner finds this file by
// name, walking up from each test file, and generates a bootstrap that calls
// `testExecutable(testMain)` — so nothing in the package references it, yet it
// is live. Expected findings: none.

import 'dart:async';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  await testMain();
}
