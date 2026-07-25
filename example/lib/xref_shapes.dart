// Cross-library reference-recovery fixture (object patterns). Expected findings
// are asserted by test/finder_test.dart; keep in sync.

sealed class XrefState {}

final class XrefLoadedState extends XrefState {
  XrefLoadedState({required this.active});

  final bool active;

  // Used only by a cross-file object pattern -> recovered, NOT flagged.
  bool get hasActive => active;

  // Stored field with no constructor formal, used only by that pattern.
  final bool ready = true;

  // Used only by a same-file object pattern (indexed normally).
  bool get localFlag => active;

  // Never referenced -> still flagged.
  bool get deadShapeGetter => active;
}

String describeLocal(XrefState state) => switch (state) {
  XrefLoadedState(localFlag: true) => 'local',
  _ => 'other',
};
