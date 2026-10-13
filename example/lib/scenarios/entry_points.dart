// Entry points. Expected findings: everything, by default; with `entry-points`
// rules for `integrationMain`, `Plugin.registerWith` and `bootstrap`, only
// `testExecutable` — right name, wrong file — and `Plugin.other`: the member
// rule keeps `Plugin` itself, which nothing names, but not its other members.
// Type parameters are not part of a name: `Plugin<T>` is still `Plugin`.
// A rule for a class (`ParkedCard`, `ParkedSlot`) keeps it and its unnamed
// constructor, which whoever reaches the class calls, but not its named
// constructors or other members: `ParkedCard.blank` and `ParkedCard.flip`.

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

class ParkedCard {
  const ParkedCard();

  const ParkedCard.blank();

  void flip() {}
}

class ParkedSlot {
  factory ParkedSlot() => ParkedSlot._();

  ParkedSlot._();
}
