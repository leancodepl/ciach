// Fixture for Dart 3.13 primary constructors: a constructor, and the instance
// variables its `var`/`final` parameters induce, declared in the type's header;
// the `this : …` body part completing it; and the abbreviated `new`/`factory`
// headers that ship with the same feature. Scanned only by the dedicated
// primary-constructor tests; see test/finder_test.dart.
//
// The rule it pins down: a dead declaration in the HEADER is reported but never
// auto-removed, while the BODY of the same class stays ordinary ground.

// --- Live: nothing here may be reported ---

/// Header form with a `;` body.
class Point(var int x, var int y);

/// A `const`, named primary constructor.
class const Money.cents(final int amount);

/// A plain (non-declaring) parameter, an instance variable initialized from it,
/// and a body part carrying the initializer list. The body part must never
/// surface as a `Delta.this` finding.
class Delta(final int from, int step) {
  this : assert(step > 0);

  final int to = from + step;
}

/// A super parameter forwarded through a primary constructor.
class Origin(final int at);

class Shifted(super.at) extends Origin;

enum Suit(final String glyph) {
  hearts('♥'),
  spades('♠');
}

/// Empty bodies written as `;`.
mixin Marker;

class Marked with Marker;

// --- Dead, and removable: declared in the body ---

/// Reported as the whole CLASS — its declaring parameters go with it — and
/// removed as one node, `;` body and all.
class DeadPoint(var int x, var int y);

/// A live class whose dead *body* members stay removable, the abbreviated
/// `new`/`factory` headers included.
class Registry {
  new() : tag = null;

  new tagged(this.tag);

  new deadNamed() : tag = null;

  factory deadFactory() => .new();

  factory deadRedirect() = Registry;

  final String? tag;

  int deadCounter = 0;
}

// --- Dead, but report-only: declared in the header ---

/// Nothing reads `port`, but removing it would change `Endpoint`'s signature.
class Endpoint(final String host, final int port);

/// Named declaring parameters, one of them dead. They sit inside the parameter
/// list's own `{…}`, which must not be taken for the start of the class body.
class Chip({required var String label, var int badge = 0}) {
  String get short => label;
}

/// An optional positional declaring parameter, also dead.
class Ranged(var int low, [var int high = 10]);

/// A private primary constructor that is never invoked. It is *not* reported —
/// a query at the header resolves to the class, which is used as a type below —
/// but its dead declaring parameter is. Were the class dead too, the
/// constructor would surface (under `-k constructor`) as report-only.
class const Secret._(final int seed);

// --- Uses ---

void usePrimaryConstructors() {
  final p = Point(1, 2);
  print(p.x + p.y);
  print(const Money.cents(500).amount);
  print(Delta(1, 2).to);
  print(Shifted(3).at);
  print(Suit.hearts.glyph);
  print(Marked());
  print(Registry().tag);
  print(Registry.tagged('t'));
  print(Endpoint('localhost', 8080).host);
  print(Chip(label: 'draft').short);
  print(Ranged(1).low);
}

void useSecretType(Secret? secret) => print(secret);
