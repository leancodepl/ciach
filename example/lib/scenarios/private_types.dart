/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

// Members of a private type are private, whatever their own names, unless a
// public declaration exposes the type. Only the private-type tests in
// test/finder/finder_test.dart scan this file.

part 'private_types_part.dart';

/// Entry point -> USED.
void main() {
  print(_Settings.defaults().used);
  _Painted().paint();
  1.doubled();
  print(_Level.low);
  print(_Id(1).value);
  print(Circle<_Settings>());
  print(<Measure>[]);
  print(<Mixer>[]);
  print(<Alias>[]);
  print(<PartAlias>[]);
  print(FromPart());
  print(<Tier>[]);
  print(makeTool());
  print(items);
  print(Ruler());
  print(_Gauge());
  print(<Stock>[]);
  print(<Visit>[]);
  print(Holder<_Held>().held);
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

  /// Never called -> UNUSED, private: a subclass inherits no static members.
  static void helper() {}
}

class _Mid extends _Root {}

/// The bound names `_Settings`, which `Circle` doesn't inherit from.
class Circle<T extends _Settings> extends _Mid {}

/// Named only by the `implements` clause of `Measure` -> UNUSED as a whole.
abstract interface class _Measured {
  /// Never called, public: `Measure` passes it on.
  int size();
}

abstract class Measure implements _Measured {}

class _Host {
  /// Never called -> UNUSED, but public: `Mixer` passes it on.
  void host() {}
}

mixin Mixer on _Host {}

class _Aliased {
  /// Never called -> UNUSED, but public: `Alias()` calls it.
  _Aliased();

  /// Never called -> UNUSED, but public: `Alias.create()` calls it.
  _Aliased.create();

  /// Never called -> UNUSED, but public: `Alias` hands it out.
  void aliased() {}

  /// Never called -> UNUSED, but public: `Alias.util()` calls it.
  static void util() {}
}

typedef Alias = _Aliased;

class _PartAliased {
  /// Never called -> UNUSED, but public: `PartAlias`, in the part file,
  /// hands it out.
  void partAliased() {}
}

class _InPart {
  /// Never called -> UNUSED, but public: `FromPart`, in the part file,
  /// inherits it.
  void parted() {}
}

enum _Tier {
  top;

  /// Never read -> UNUSED, but public: `Tier.top.isTop` reads it.
  bool get isTop => this == top;
}

typedef Tier = _Tier;

/// Called by `main` -> USED. Hands out a `_Tool`.
_Tool makeTool() => _Tool();

class _Tool {
  /// Never called -> UNUSED, but public: `makeTool().use()` calls it.
  void use() {}

  /// Never called -> UNUSED, private: no other library can name `_Tool`.
  static void make() {}

  /// Never read -> UNUSED, but public: `makeTool().part` reads it.
  _Part get part => _Part();
}

class _Part {
  /// Never called -> UNUSED, but public: `makeTool().part.fit()` calls it.
  void fit() {}
}

/// Read by `main` -> USED. Its inferred type is `List<_Item>`.
final items = [_Item()];

class _Item {
  /// Never called -> UNUSED, but public: `items.first.weigh()` calls it.
  void weigh() {}
}

class _Gauge {
  /// Never called -> UNUSED, but public: removing it would also remove the
  /// override in `Ruler`.
  void calibrate() {}
}

class Ruler implements _Gauge {
  /// Never called, but an override -> removed only with `_Gauge.calibrate`.
  @override
  void calibrate() {}
}

class _Crate {
  /// Never called -> UNUSED, private: `Stock` names `_Crate` only as a type
  /// argument, so `Stock.create()` doesn't compile.
  _Crate.create();

  /// Never called -> UNUSED, but public: `Stock` holds `_Crate`s.
  void open() {}
}

typedef Stock = List<_Crate>;

class _Visited {
  /// Never called -> UNUSED, but public: a `Visit` callback receives a
  /// `_Visited`.
  void visit() {}
}

typedef Visit = void Function(_Visited);

class _Held {
  /// Never called -> UNUSED, but public: `Holder().held?.grip()` calls it.
  void grip() {}
}

/// Unlike the bound of `Circle`, this one reaches other libraries through
/// `held`.
class Holder<T extends _Held> {
  T? held;
}
