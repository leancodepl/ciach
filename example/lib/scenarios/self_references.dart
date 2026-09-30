// Fixtures for the own-span rule: a reference from inside a declaration's own
// span doesn't keep it alive, whatever the declaration's kind. Scanned only by
// the dedicated test in test/finder_test.dart.

/// Calls itself, and bin/app.dart calls it -> USED.
int factorial(int n) => n <= 1 ? 1 : n * factorial(n - 1);

/// Calls only itself -> UNUSED (function).
int _countdown(int n) => n == 0 ? 0 : _countdown(n - 1);

/// Constructed from bin/app.dart -> USED.
class Walker {
  /// Calls itself, and [walk] calls it -> USED.
  int _step(int n) => n == 0 ? 0 : _step(n - 1);

  /// Called from bin/app.dart -> USED.
  int walk(int n) => _step(n);

  /// Calls only itself -> UNUSED (method).
  int _depth(int n) => n == 0 ? 0 : _depth(n - 1);
}

/// Named only by its own field -> UNUSED (class, and the field with it).
class Chain {
  Chain? next;
}
