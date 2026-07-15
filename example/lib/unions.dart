// A sealed union whose members are reached only through pattern matching, to
// exercise the opt-in --unused-union-members detection across the three
// removable/blocked contexts. The finder keys off the textual pattern shapes,
// so no Flutter or other dependency is needed here.
//
// Scanned only by the dedicated union tests (excluded from the default-run
// assertions); see test/finder_test.dart.

/// Sealed base. USED as a parameter / scrutinee type below, so never flagged.
sealed class Signal {}

/// Constructed in bin/app.dart (and matched below), so it has a real,
/// non-pattern reference and is never flagged, flag on or off.
class LiveSignal extends Signal {}

/// Matched only by a `case` arm in a switch STATEMENT, never constructed.
/// Dead under --unused-union-members; its arm is a clean whole-node removal.
class StatementOnlySignal extends Signal {}

/// Matched only by a switch-EXPRESSION arm, never constructed. Dead under the
/// flag; the whole `Pattern => value,` arm is removed with it.
class ExpressionOnlySignal extends Signal {}

/// Matched only by an `if (x case …)`, never constructed. Dead under the flag,
/// but its removal is BLOCKED (deleting the branch would rewrite control flow),
/// so it is reported without a coupled removal.
class IfCaseOnlySignal extends Signal {}

/// A switch STATEMENT over [Signal]. The `default` keeps it non-exhaustive, so
/// removing one member's arm leaves it valid.
String describeStatement(Signal signal) {
  switch (signal) {
    case LiveSignal():
      return 'live';
    case StatementOnlySignal():
      return 'statement';
    default:
      return 'other';
  }
}

/// A switch EXPRESSION over [Signal], with a wildcard so it stays valid when an
/// arm is removed.
String describeExpression(Signal signal) => switch (signal) {
  ExpressionOnlySignal() => 'expression',
  _ => 'other',
};

/// An `if`-case over [Signal]: the dead member matched here cannot be removed
/// without rewriting the branch, so the finder reports it but blocks removal.
bool isIfCaseSignal(Signal signal) {
  if (signal case IfCaseOnlySignal()) {
    return true;
  }
  return false;
}
