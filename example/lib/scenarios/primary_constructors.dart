// Fixture for Dart 3.13 primary constructors. The rule it pins down: a dead
// declaration in a class HEADER is reported but never auto-removed, while the
// BODY of the same class stays ordinary ground. Scanned only by the dedicated
// primary-constructor tests; see test/finder_test.dart.

// --- Live: nothing here may be reported ---

class Point(var int x, var int y);

class const Money.cents(final int amount);

/// The body part must never surface as a `Delta.this` finding.
class Delta(final int from, int step) {
  this : assert(step > 0);

  final int to = from + step;
}

class Origin(final int at);

class Shifted(super.at) extends Origin;

enum Suit(final String glyph) {
  hearts('♥'),
  spades('♠'),
}

mixin Marker;

class Marked with Marker;

// --- Dead, and removable: declared in the body ---

/// Reported as the whole class, its declaring parameters included.
class DeadPoint(var int x, var int y);

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

class Endpoint(final String host, final int port);

/// `badge` sits inside the parameter list's own `{…}`, which must not be taken
/// for the start of the class body.
class Chip({required var String label, var int badge = 0}) {
  String get short => label;
}

class Ranged(var int low, [var int high = 10]);

/// Not reported: a query at the header resolves to the class, which is used as
/// a type below. Only its dead declaring parameter is.
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
