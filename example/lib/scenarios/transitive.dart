// Declarations reachable only from dead code. Scanned by its own test, with
// and without `transitive`. Doc comments use backticks: a `[link]` is a
// reference.

/// Never referenced -> UNUSED either way. Links [_docLinkedFromDead].
void _deadRoot() {
  _onlyFromDeadRoot();
  _sharedByDeadRoots();
  print(_DeadHolder.make());
  print(Odometer()._deadReading());
}

/// Called only by `_deadRoot` -> USED plain, UNUSED with transitive.
void _onlyFromDeadRoot() => _deeper();

/// Two steps from dead code -> UNUSED with transitive.
void _deeper() {}

/// Never referenced -> UNUSED either way.
void _secondDeadRoot() => _sharedByDeadRoots();

/// Called only by `_deadRoot` and `_secondDeadRoot` -> UNUSED with transitive,
/// naming both.
void _sharedByDeadRoots() {}

/// Linked only from `_deadRoot`'s doc -> DOC-ONLY plain, UNUSED with
/// transitive.
void _docLinkedFromDead() {}

/// Used only by `_deadRoot` -> UNUSED with transitive, as the class; members
/// unreported.
class _DeadHolder {
  _DeadHolder._(this.value);

  static int make() => _DeadHolder._(_seed()).value;

  final int value;

  static int _seed() => 42;
}

/// Called from bin/app.dart -> USED.
void transitiveAnchor() => _usedByLive();

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

/// A cycle with `_pong` -> USED even with transitive (#65).
void _ping() => _pong();

void _pong() => _ping();

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
