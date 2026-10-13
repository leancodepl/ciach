import 'package:sample_pkg/scenarios/xref_collision.dart';

String describe(CollisionState state) => switch (state) {
  LiveState(status: true) => 'live',
  // Uses the class but not its `status` getter.
  DeadState() => 'dead',
  _ => 'other',
};
