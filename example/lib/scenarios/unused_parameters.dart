// Parameters that the body of a function, method or constructor never reads.
// They are reported when only calls use the function; a signature that an
// override, a subtype or a tear-off fixes stays. Scanned only by
// test/finder/unused_parameters_test.dart.

// The fixture holds unused parameters for ciach to find.
// ignore_for_file: avoid_unused_constructor_parameters

// --- Reported ---

/// `level` -> UNUSED; `message` is read.
void log(String message, int level) => print(message);

/// `unused` -> UNUSED in a private function.
int _sum(int a, int b, int unused) => a + b;

/// `strict` -> UNUSED, an optional positional parameter.
bool parse(String text, [bool strict = false]) => text.isNotEmpty;

/// `label` -> UNUSED: the call inside passes a named argument of that name,
/// which doesn't read it.
void forward(int label) => _labeled(label: 1);

void _labeled({required int label}) => print(label);

/// `index` -> UNUSED in an empty body.
void onTap(int index) {}

/// `unused` -> UNUSED: this doc comment's link to [docLinked] doesn't tear it
/// off.
void docLinked(int unused) => print('linked');

class Printer {
  /// `prefix` -> UNUSED, a named parameter of a method.
  void write(String text, {String prefix = ''}) => print(text);

  /// `count` -> UNUSED in a static method that a generic call uses.
  static List<T> repeat<T>(T value, int count) => [value];
}

class Account {
  /// `currency` -> UNUSED; `this.balance` and the initializer's `owner` are
  /// read.
  Account(this.balance, String owner, String currency) : name = owner;

  final int balance;
  final String name;
}

extension Shouting on String {
  /// `times` -> UNUSED in an extension method.
  String shout(int times) => toUpperCase();
}

enum Level {
  low(1),
  high(2);

  /// `weight` -> UNUSED in the constructor of an enhanced enum.
  const Level(int weight);
}

// --- Not reported ---

/// Named `_`: unused on purpose.
void ignoreFirst(int _, int second) => print(second);

/// Torn off below, so a function type fixes its signature.
void onEach(int value) {}

/// Torn off with type arguments.
void onEachTyped<T>(T value) => print('typed');

/// `value` is read only by a closure: the closure's own `value` shadows it.
int shadowed(int value) => [1].map((value) => value + 1).length;

/// The closure's and the function type's parameters aren't this function's.
void apply(void Function(int item) callback) {
  print([1].map((unusedByClosure) => 0));
  callback(1);
}

abstract class Shape {
  /// Abstract: no body reads its parameters.
  double area(double scale);

  /// Overridden below, so a subtype shares its signature.
  void draw(Object canvas) {}
}

class Square extends Shape {
  @override
  double area(double scale) => 1;

  @override
  void draw(Object canvas) => print(canvas);

  /// Torn off as `square.resize`.
  void resize(int factor) {}
}

class Base {
  Base(this.id);

  final int id;
}

class Derived extends Base {
  /// `super.id` passes the value on.
  Derived(super.id);

  /// A redirecting factory passes its parameters on.
  factory Derived.from(int id) = Derived;
}

/// Declaring parameters are fields; `step` is read by the field initializer.
class Range(final int start, int step) {
  final int end = start + step;
}

/// External: no body here.
external void native(int handle);

/// Kept by a marker, with its parameters.
// ciach:ignore
void keptByMarker(int unused) => print('kept');

/// Unused itself: reported as a function, not for its parameter.
void deadFunction(int unused) {}

/// An entry point, so the runtime fixes its signature.
void main(List<String> args) => print('main');

// --- Uses ---

/// An entry point -> skipped; keeps the rest of the fixture live.
@pragma('vm:entry-point')
void useParameters() {
  log('a', 1);
  print(_sum(1, 2, 3));
  print(parse('a', true));
  forward(1);
  onTap(1);
  Printer().write('a', prefix: '>');
  print(Printer.repeat<int>(1, 2));
  print(Account(1, 'a', 'PLN').name);
  ignoreFirst(1, 2);
  [1].forEach(onEach);
  [1].forEach(onEachTyped<int>);
  print(shadowed(1));
  apply(print);
  docLinked(1);
  final Shape square = Square()..draw(1);
  print(square.area(1));
  [1].forEach(Square().resize);
  print(Derived.from(1).id);
  print(Range(1, 2).end);
  keptByMarker(1);
  native(1);
  print('a'.shout(2));
  print(Level.values);
}
