// Fixtures for Dart 3.13 primary constructors: a constructor (and, for the
// parameters marked `var`/`final`, the instance variables it initializes)
// declared in the type's *header* instead of its body, the `this : …` body part
// that completes it, and the abbreviated `new`/`factory` constructor headers
// that ship with the same feature. Scanned only by the dedicated
// primary-constructor tests; see test/finder_test.dart.
//
// The rule this file pins down: anything declared in the header is reported
// when dead, but never auto-removed. Deleting the constructor alone would leave
// a `class ;` fragment, and deleting a declaring parameter would silently
// change the constructor's signature at every call site. Declarations in the
// *body* of the same class — including the abbreviated constructors — stay
// removable like any other dead code.

// --- Live: nothing here may be reported ---

/// Header form with a `;` body, constructed below, both declaring parameters
/// read.
class Point(var int x, var int y);

/// A `const`, named primary constructor. Invoked below, so neither the class
/// nor the constructor is dead.
class const Money.cents(final int amount);

/// A primary constructor with a plain (non-declaring) parameter, an instance
/// variable initialized from it, and a body part carrying the initializer list.
/// The body part is the tail of the header's constructor, not a declaration of
/// its own: it must never surface as a `Delta.this` finding.
class Delta(final int from, int step) {
  this : assert(step > 0);

  final int to = from + step;
}

/// A super parameter forwarded through a primary constructor.
class Origin(final int at);

class Shifted(super.at) extends Origin;

/// An enum with a primary constructor; `hearts` is named below.
enum Suit(final String glyph) {
  hearts('♥'),
  spades('♠');
}

/// An empty body written as `;`.
mixin Marker;

class Marked with Marker;

// --- Dead, and removable: the class body is ordinary ground ---

/// Never referenced at all. Reported as the whole CLASS — its declaring
/// parameters go with it, so they are not reported separately — and removed as
/// one node, `;` body and all.
class DeadPoint(var int x, var int y);

/// A live class (constructed below) whose *body* declarations are dead. The
/// abbreviated `new`/`factory` headers are the second half of the primary
/// constructors feature: they name no class, but they are ordinary body members
/// and stay removable.
class Registry {
  new() : tag = null;

  new tagged(this.tag);

  new deadNamed() : tag = null;

  factory deadFactory() => .new();

  factory deadRedirect() = Registry;

  final String? tag;

  /// A plain body field that is dead: still removable, unlike a declaring
  /// parameter.
  int deadCounter = 0;
}

// --- Dead, but report-only: declared in the header ---

/// A live class (constructed below) whose second declaring parameter is never
/// read. It is a real finding — nothing reads `port` — but removing it would
/// change `Endpoint`'s signature, so it is reported and left in place.
class Endpoint(final String host, final int port);

/// Named declaring parameters, one of them dead. They sit inside the parameter
/// list's own `{…}` group, which must not be mistaken for the start of the
/// class body when placing them in the header.
class Chip({required var String label, var int badge = 0}) {
  String get short => label;
}

/// An optional positional declaring parameter, also dead.
class Ranged(var int low, [var int high = 10]);

/// A live class whose *private* primary constructor is never invoked: the class
/// is only ever used as a type. It is *not* reported — a references query at the
/// header resolves to the class, whose type use keeps it alive — but its dead
/// declaring parameter is. Were the class dead too, the constructor would
/// surface (under `-k constructor`) as report-only: the header is the class
/// declaration itself.
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

/// Keeps [Secret] alive as a type without ever invoking its constructor.
void useSecretType(Secret? secret) => print(secret);
