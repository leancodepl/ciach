import 'package:sample_pkg/scenarios/xref_collision.dart';

String describe(CollisionState state) => switch (state) {
  LiveState(status: true) => 'live',
  // Names `DeadState`, so the class is used and its unused `status` getter
  // is still reported on its own, not folded into an unused class.
  DeadState() => 'dead',
  _ => 'other',
};
