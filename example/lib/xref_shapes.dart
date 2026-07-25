// Fixture for cross-library reference recovery — object patterns (issue #24).
//
// The expected findings are asserted by test/finder_test.dart. Keep this in
// sync with that test when editing.

sealed class XrefState {}

final class XrefLoadedState extends XrefState {
  XrefLoadedState({required this.active});

  final bool active;

  // Referenced ONLY by a cross-file object pattern in xref_uses.dart. The
  // analysis server does not index that reference, so without the recovery
  // this getter reads as unused (#24) -> must NOT be flagged.
  bool get hasActive => active;

  // A stored field with no constructor formal, referenced ONLY by the same
  // cross-file object pattern -> also recovered, NOT flagged.
  final bool ready = true;

  // Referenced ONLY by a SAME-FILE object pattern (below). Same-file pattern
  // references ARE indexed, so this stays used independently of the recovery.
  bool get localFlag => active;

  // Never referenced anywhere -> genuinely dead, MUST still be flagged.
  bool get deadShapeGetter => active;
}

// A same-file object-pattern use of XrefLoadedState.localFlag.
String describeLocal(XrefState state) => switch (state) {
  XrefLoadedState(localFlag: true) => 'local',
  _ => 'other',
};
