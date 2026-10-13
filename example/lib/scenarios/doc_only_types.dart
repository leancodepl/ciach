// Fixtures for types referenced only from a doc comment. Each type is doc-only
// and never removed; its unused members are reported but kept, so --remove
// cannot leave an empty type behind. Scanned only by the dedicated tests in
// test/finder_test.dart.

/// Pad the bottom yourself or use [SafeInset]; tint it with [Hue], or mix in
/// [Padded]. Called from bin/app.dart -> USED.
void linksDocOnlyTypes() {}

/// Linked only from a doc comment -> DOC-ONLY; its members are reported but
/// kept.
class SafeInset {
  SafeInset();

  SafeInset.named();

  double get height => 0;

  static void reset() {}
}

/// Linked only from a doc comment -> DOC-ONLY; its values are reported but
/// kept.
enum Hue { warm, cool }

/// Linked only from a doc comment -> DOC-ONLY; its method is reported but
/// kept.
mixin Padded {
  void pad() {}
}
