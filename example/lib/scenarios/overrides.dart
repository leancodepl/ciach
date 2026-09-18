// Dead interface members whose overrides are not candidates: removing such a
// member on its own leaves every override overriding nothing, which the
// analyzer reports as `override_on_non_overriding_member`. The overrides are
// coupled to the member's removal instead, or the member is left in place when
// one of them cannot be deleted.
//
// Doc comments here deliberately avoid `[…]` links to the dead members: a link
// is a reference, which would make them doc-only findings instead.
//
// Scanned only by the dedicated override tests (excluded from the default-run
// assertions); see test/finder_test.dart.

/// Kept alive as a type from bin/app.dart, so only its members are reported.
abstract class Pump {
  /// Never called through any of these types -> UNUSED. The overrides in
  /// `Piston` and `Turbine` are coupled to its removal.
  void prime();

  /// Called from bin/app.dart -> USED, and so is the override in `Piston`.
  void start();
}

class Piston implements Pump {
  @override
  void prime() {}

  @override
  void start() {}
}

class Turbine extends Piston {
  /// An override two levels down from `Pump.prime`, coupled to it just the
  /// same: `textDocument/implementation` answers transitively.
  @override
  void prime() {}
}

/// Kept alive as the supertype of `Dial`.
abstract class Gauge {
  /// Never read -> UNUSED, but `Dial.reading` implements it as a field, which
  /// `--remove` will not delete: report-only.
  num get reading;
}

class Dial implements Gauge {
  @override
  final num reading = 0;
}

/// Kept alive as the supertype of `Spigot` in overrides_impl.dart.
abstract class Valve {
  /// Never called -> UNUSED. `Spigot.close` overrides it, so the finding is
  /// coupled to that override when overrides_impl.dart is scanned too, and
  /// report-only when it is not.
  void close();
}
