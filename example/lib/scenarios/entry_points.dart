// Entry points. Expected findings: everything, by default; with `entry-points`
// rules for `integrationMain`, `Plugin.registerWith` and `bootstrap`, only
// `testExecutable` — right name, wrong file — and `Plugin.other`: the member
// rule keeps `Plugin` itself, which nothing names, but not its other members.

import 'dart:async';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  await testMain();
}

void integrationMain() {}

class Plugin {
  static void registerWith() {}

  void other() {}
}

void bootstrap() {}
