// The Flutter test runner's per-directory hook. `flutter test` finds this file
// by name and calls `testExecutable` around every test file in the directory,
// so nothing in the package ever references it — yet it is an entry point,
// never unused. This is not a Flutter package; the hook's shape is all that
// matters here, and test/finder_test.dart asserts it is never reported.

import 'dart:async';

/// Called by `flutter test`, never from code -> skipped, like `main`.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  await testMain();
}
