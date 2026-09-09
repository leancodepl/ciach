// Fixture for emptied extensions. An extension is never reference-checked on
// its own — the implicit `x.member()` use never names it — so it is reported
// when every one of its members is, and `--remove` then deletes it whole
// instead of leaving `extension X on T {}` behind. Scanned only by its own
// tests; see test/finder_test.dart.

/// Every member is dead -> UNUSED (extension), reported alongside them.
extension DeadExtras on int {
  /// Never referenced -> UNUSED (method).
  int tripled() => this * 3;

  /// Never referenced -> UNUSED (method).
  int quadrupled() => this * 4;
}

/// Unnamed and every member dead -> UNUSED (extension), reported under the
/// server's name for it, `extension on String`.
extension on String {
  /// Never referenced -> UNUSED (method).
  String shouted() => toUpperCase();
}

/// One live member keeps the extension -> USED; only the dead member is
/// reported, and the extension is left standing.
extension MixedExtras on int {
  /// Referenced by `useMixedExtras` (no `[link]`: that would count as a
  /// reference to it) -> USED.
  int doubled() => this * 2;

  /// Never referenced -> UNUSED (method).
  int halved() => this ~/ 2;
}

/// Its one candidate member is dead, but the operator is skipped by default
/// (--operators), so the extension cannot be shown empty -> not reported.
extension OperatorExtras on int {
  /// Never referenced -> UNUSED (method).
  int negated() => -this;

  /// An operator overload, skipped by default.
  int operator [](int index) => index;
}

/// Private throughout and dead -> UNUSED (extension), with --no-public too.
extension _PrivateExtras on int {
  /// Never referenced -> UNUSED (private method).
  int _secret() => 0;
}

/// A public extension whose only member is private and dead -> UNUSED
/// (extension): with nothing left to offer it is dead even under --no-public,
/// where its public name alone would not have been reported.
extension PublicShell on int {
  /// Never referenced -> UNUSED (private method).
  int _hidden() => 1;
}

/// Keeps [MixedExtras.doubled] alive; the fixture's own entry point, which
/// nothing calls -> UNUSED (function).
int useMixedExtras() => 4.doubled();
