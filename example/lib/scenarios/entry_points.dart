// Entry points. Expected findings: everything, by default; with `entry-points`
// rules for `integrationMain`, `Plugin.registerWith` and `bootstrap`, only
// `testExecutable` — right name, wrong file.

import 'dart:async';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  await testMain();
}

Object integrationMain() => Plugin;

class Plugin {
  static void registerWith() {}
}

void bootstrap() {}
