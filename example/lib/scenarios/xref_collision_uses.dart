import 'package:sample_pkg/scenarios/xref_collision.dart';

String describe(CollisionState state) => switch (state) {
  LiveState(status: true) => 'live',
  // Names the class, keeping it, but not its `status`.
  DeadState() => 'dead',
  _ => 'other',
};
