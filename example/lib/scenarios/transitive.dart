// Declarations referenced only from dead code. Scanned by its own test, with
// and without `transitive`. Doc comments name declarations in backticks, since
// a `[link]` would count as a reference.

/// Never referenced -> UNUSED either way. Links [_docLinkedFromDead].
void _deadRoot() {
  _onlyFromDeadRoot();
  _sharedByDeadRoots();
  print(_DeadHolder.make());
  print(Odometer()._deadReading());
}

/// Called only by `_deadRoot` -> USED without transitive, UNUSED with it.
void _onlyFromDeadRoot() => _deeper();

/// Two steps from dead code -> UNUSED with transitive.
void _deeper() {}

/// Never referenced -> UNUSED either way.
void _secondDeadRoot() => _sharedByDeadRoots();

/// Called only by `_deadRoot` and `_secondDeadRoot` -> UNUSED with transitive,
/// naming both.
void _sharedByDeadRoots() {}

/// Linked only from `_deadRoot`'s doc -> DOC-ONLY without transitive, UNUSED
/// with it.
void _docLinkedFromDead() {}

/// Used only by `_deadRoot` -> UNUSED with transitive, reported as the class
/// without its members.
class _DeadHolder {
  _DeadHolder._(this.value);

  static int make() => _DeadHolder._(_seed()).value;

  final int value;

  static int _seed() => 42;
}

/// Called from bin/app.dart -> USED.
void transitiveAnchor() {
  _usedByLive();
  _liveCycle();
}

/// Called only by live `transitiveAnchor` -> USED either way.
void _usedByLive() {}

/// Constructed from bin/app.dart -> USED.
class Odometer {
  /// Called only by `_deadRoot` -> UNUSED with transitive.
  int _deadReading() => _scale * 2;

  /// Read only by `_deadReading` -> UNUSED with transitive; its class stays.
  static const int _scale = 3;

  /// Called from bin/app.dart -> USED.
  int live() => 1;
}

/// A cycle with `_pong` -> USED even with transitive, UNUSED with
/// reachability.
void _ping() => _pong();

void _pong() => _ping();

/// A cycle with `_liveCycleBack`, entered from live `transitiveAnchor` ->
/// USED either way.
void _liveCycle() => _liveCycleBack();

void _liveCycleBack() => _liveCycle();

/// Two classes that only reference each other -> USED even with transitive,
/// UNUSED with reachability, each reported without its members.
class _Chicken {
  _Egg lay() => _Egg()..hatch();
}

class _Egg {
  _Chicken hatch() => _Chicken()..lay();
}

/// Referenced as a type from bin/app.dart -> USED. Its only value is dead but
/// report-only, so it stays, and so does what it references.
enum Lone {
  only(_loneArg);

  const Lone(this.arg);

  /// Read from bin/app.dart -> USED.
  final int arg;
}

/// Referenced only by report-only `Lone.only` -> USED either way.
const int _loneArg = 7;

/// Referenced as a type from bin/app.dart -> USED; it keeps its final field, so
/// its last constructor can't be removed.
class Token {
  /// Called only by `Token.fromJson` -> UNUSED with transitive, but it is the
  /// last constructor, so report-only.
  Token(this.value);

  /// Never called -> UNUSED either way, and removable: `Token.new` stays.
  Token.fromJson(Object json) : this(json as String);

  final String value;
}
