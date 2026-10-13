// Entry points. Expected findings: everything, by default; with `entry-points`
// rules for `integrationMain`, `Plugin.registerWith` and `bootstrap`, only
// `testExecutable` (in the wrong file), `Parked` (no rule) and `Plugin.other`.
// The `Plugin.registerWith` rule also keeps the unused `Plugin` class.
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

// The report prints the unnamed constructor as `Parked.new`. A rule for
// `Parked.new` keeps that constructor and the `Parked` class, but not
// `Parked.make`.
class Parked {
  Parked();
  Parked.make();
}
