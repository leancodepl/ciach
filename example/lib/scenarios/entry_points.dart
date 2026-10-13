// Entry points. Expected findings: everything, by default; with `entry-points`
// rules for `integrationMain`, `Plugin.registerWith` and `bootstrap`, only
// `testExecutable` (in the wrong file), `Plugin.other`, and the `Parked*`
// classes (no rule). The `Plugin.registerWith` rule also keeps the unused
// `Plugin` class.
// Type parameters are not part of a name: `Plugin<T>` is still `Plugin`.
// A rule that names a class (`ParkedCard`, `ParkedSlot`) keeps the class and
// its unnamed constructor. It does not keep the named constructors or other
// members, such as `ParkedCard.blank` and `ParkedCard.flip`.

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

class ParkedCard {
  const ParkedCard();

  const ParkedCard.blank();

  void flip() {}
}

class ParkedSlot {
  factory ParkedSlot() => ParkedSlot._();

  ParkedSlot._();
}
