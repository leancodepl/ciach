// Recovery fixture. Expected findings are asserted by test/finder_test.dart;
// keep in sync.

sealed class XrefState {}

final class XrefLoadedState extends XrefState {
  XrefLoadedState({required this.active});

  final bool active;

  // Used only from another file -> confirmed used, NOT flagged.
  bool get hasActive => active;

  // Used only from another file -> confirmed used, NOT flagged.
  final bool ready = true;

  // Used only within this file -> NOT flagged.
  bool get localFlag => active;

  // Never used -> flagged.
  bool get deadShapeGetter => active;
}

String describeLocal(XrefState state) => switch (state) {
  XrefLoadedState(localFlag: true) => 'local',
  _ => 'other',
};
