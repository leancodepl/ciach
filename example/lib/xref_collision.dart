// Recovery fixture. Expected findings are asserted by test/finder_test.dart;
// keep in sync.

sealed class CollisionState {}

final class LiveState extends CollisionState {
  // Used only from another file -> confirmed used, NOT flagged.
  bool get status => true;
}

final class DeadState extends CollisionState {
  // Never used -> flagged.
  bool get status => false;
}
