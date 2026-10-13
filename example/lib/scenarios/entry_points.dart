// Entry points. Expected findings: everything, by default; with `entry-points`
// rules for `integrationMain`, `Plugin.registerWith` and `bootstrap`, only
// `testExecutable` (wrong file), `Parked` (no rule) and `Plugin.other`: the
// member rule keeps `Plugin`, which nothing names, but not its other members.
// Type parameters are not part of a name: `Plugin<T>` is still `Plugin`.

import 'dart:async';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  await testMain();
}

void integrationMain() {}

class Plugin<T extends Object> {
  static R registerWith<R>() => throw UnimplementedError();

  T? other() => null;
}

void bootstrap<T>() {}

// A constructor rule names it as the report does: `Parked.new` keeps the
// unnamed constructor and, like any member rule, `Parked` itself, but not
// `Parked.make`.
class Parked {
  Parked();
  Parked.make();
}
