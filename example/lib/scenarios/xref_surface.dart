// Recovery fixture, asserted by test/finder_test.dart.

abstract class XrefSurface {
  // Used only via `XrefGlossy` in xref_uses.dart -> NOT flagged.
  bool get glossy;

  // Never used -> flagged.
  bool get matte;
}
