// The `flutter test` hook: the runner's generated bootstrap calls it, nothing
// on disk does. Expected findings: none.

import 'dart:async';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  await testMain();
}
