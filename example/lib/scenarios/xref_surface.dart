// Recovery fixture: members used only through an override. Expected findings
// are asserted by test/finder_test.dart; keep in sync.

abstract class XrefSurface {
  // Used only through `XrefGlossy` from a file that doesn't import this one
  // -> confirmed used, NOT flagged.
  bool get glossy;

  // Only overridden, never used -> flagged.
  bool get matte;
}
