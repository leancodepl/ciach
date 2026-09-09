// Fixture for the entry-point rule: a function a runtime calls by name is never
// unused — but only where that runtime actually looks for it. Scanned only by
// its own test; see test/finder_test.dart. The positive case, a hook that is
// skipped, lives in test/flutter_test_config.dart.

import 'dart:async';

/// A `testExecutable` anywhere but a `flutter_test_config.dart` is a function
/// nobody calls -> UNUSED. The skip is keyed to the file name, not the name.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  await testMain();
}
