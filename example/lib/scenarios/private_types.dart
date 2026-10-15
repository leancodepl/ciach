/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

// Members of a private type or an unnamed extension are private, whatever
// their own names, unless a public class inherits them. Only the private-type
// tests in test/finder/finder_test.dart scan this file.

/// Entry point -> USED.
void main() {
  print(_Settings.defaults().used);
  _Painted().paint();
  1.doubled();
  2.tripled();
  print(_Level.low);
  print(_Id(1).value);
  print(Circle<_Settings>());
}

/// Constructed by `main` -> USED.
class _Settings {
  /// Never called -> UNUSED, private through its class.
  _Settings();

  _Settings.defaults();

  int used = 0;

  /// Never called -> UNUSED, private through its class.
  void reset() {}
}

mixin _Painter {
  void paint() {}

  /// Never called -> UNUSED, private through its mixin.
  void repaint() {}
}

class _Painted with _Painter {}

extension _Doubling on int {
  int doubled() => this * 2;

  /// Never called -> UNUSED, private through its extension.
  int quadrupled() => this * 4;
}

extension on int {
  int tripled() => this * 3;

  /// Never called -> UNUSED: no other library can use an unnamed extension.
  int sextupled() => this * 6;
}

enum _Level {
  low;

  /// Never read -> UNUSED, private through its enum.
  bool get isLow => this == low;
}

extension type _Id(int value) {
  /// Never read -> UNUSED, private through its extension type.
  int get next => value + 1;
}

class _Root {
  /// Never called -> UNUSED, but public: `Circle` inherits it.
  void deep() {}
}

class _Mid extends _Root {}

/// The bound names `_Settings`, which `Circle` doesn't inherit from.
class Circle<T extends _Settings> extends _Mid {}
