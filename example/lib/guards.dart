// Fixtures for the remove-safety guards. Flutter-free and self-contained: each
// class/enum is kept *alive* only by a type reference (never constructed), so
// its constructor / values are dead while the type itself stays. Scanned only
// by the dedicated guard tests (excluded from the default-run assertions); see
// test/finder_test.dart.

// --- Guard 2 (no `.values`): an all-dead enum kept alive only by a type ref ---
//
// No value is named individually and `.values` is never iterated, but the enum
// TYPE stays referenced (as a return type below). Removing all the values would
// leave `enum SilentSignal {}` (a compile error), so the empty-enum guard
// reports every value as removal-blocked, keeping `--remove` safe. This is the
// non-`.values` path: `.values`-iterated enums are instead treated as used and
// never reported (see example/lib/enum_values.dart).

/// Every value is dead: none is named directly, and `.values` is never
/// iterated. The enum TYPE is kept alive by the return-type reference below.
enum SilentSignal { ping, pong }

/// Uses the enum TYPE as a return type (keeping it alive) without naming either
/// value or iterating `.values`.
SilentSignal? firstSignal(List<SilentSignal> signals) =>
    signals.isEmpty ? null : signals.first;

// --- Guard 2: emptying a still-referenced enum ---

/// Neither value is referenced, but the enum TYPE is (as a parameter type
/// below), so removing both would leave `enum EmptyableStatus {}` — a compile
/// error. Both value findings must therefore be report-only (removalBlocked).
enum EmptyableStatus { pending, settled }

/// Uses the enum TYPE (keeping it alive) without naming either value.
String describeStatus(EmptyableStatus status) => status.name;

// --- Guard 3: sole constructor with final fields ---

/// A live class (referenced as a type below) whose SOLE constructor is never
/// invoked. It has a `final` instance field, so auto-removing the constructor
/// would strand `final label` (`final_not_initialized`) — the constructor
/// finding must be report-only.
class LabeledBox {
  const LabeledBox(this.label);

  final String label;
}

/// References [LabeledBox] as a TYPE only (never constructs it), keeping the
/// class alive while its constructor is dead.
void useLabeledBoxType(LabeledBox? box) => print(box);

// --- Guard 4: super-forwarding constructor ---

/// A base class with NO zero-arg unnamed constructor: its only constructor
/// requires an argument.
class RequiresArg {
  RequiresArg(this.value);

  final int value;
}

/// A live subclass whose SOLE constructor forwards to the argument-taking super
/// constructor. Removing it would synthesize an implicit `ForwardingChild()`
/// calling `super()`, but [RequiresArg] has no zero-arg unnamed constructor
/// (`no_default_super_constructor`) — the finding must be report-only. The
/// subclass has no `final` field of its own, isolating guard 4 from guard 3.
class ForwardingChild extends RequiresArg {
  ForwardingChild(super.value);
}

/// References [ForwardingChild] as a TYPE only, keeping it alive while its
/// constructor is dead.
void useForwardingChildType(ForwardingChild? child) => print(child);

// --- Control: a safe sole-constructor removal (NOT blocked) ---

/// A live class whose sole constructor is dead but SAFE to remove: no `final`
/// fields and no super-constructor forwarding, so removing it just yields the
/// equivalent implicit default constructor. Its constructor is reported but
/// NOT blocked.
class MutableBag {
  MutableBag();

  int count = 0;
}

/// References [MutableBag] as a TYPE only, keeping it alive while its
/// constructor is dead.
void useMutableBagType(MutableBag? bag) => print(bag);
