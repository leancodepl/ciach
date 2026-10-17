// Fixtures for `call` methods, which an object invoked like a function
// (`obj(1)`) or used where a function is expected (`int Function(int) f = obj`)
// uses without a reference that the server reports. Every form of use is in
// call_methods_uses.dart. Scanned only by the dedicated test (excluded from
// the default-run assertions); see test/finder/call_methods_test.dart.
// Expected findings: NeverCalled.call, OnlyCalledFromDeadCode.call,
// callFromDeadCode and UnusedStaticCall.call.

class Invoked {
  int call(int x) => x;
}

class TornOff {
  int call(int x) => x;
}

class TornOffAsFunction {
  int call(int x) => x;
}

class Generic {
  T call<T>(T x) => x;
}

class HeldInField {
  int call() => 1;
}

class Holder {
  final held = HeldInField();
}

class Base {
  int call() => 1;
}

class Derived extends Base {}

abstract interface class Handler {
  void call();
}

class HandlerImpl implements Handler {
  @override
  void call() {}
}

class Explicit {
  int call() => 1;
}

/// Invoked only in an argument of an explicit `.call(…)`.
class InExplicitArgument {
  int call() => 1;
}

class ExplicitWithArgument {
  int call(int x) => x;
}

class Wrapped {
  const Wrapped();
}

extension WrappedCall on Wrapped {
  int call() => 1;
}

/// Invoked only through `this(…)`, from a method of its own class.
class SelfInvoked {
  int call(int x) => x;

  int twice(int x) => this(x) * 2;
}

class NeverCalled {
  int call() => 1;
}

class OnlyCalledFromDeadCode {
  int call() => 1;
}

int callFromDeadCode(OnlyCalledFromDeadCode callable) => callable();

enum Level {
  low;

  int call() => index;
}

mixin Callable {
  int call() => 1;
}

class WithCallable with Callable {}

class NamedParameter {
  int call({required int x}) => x;
}

/// An object can't invoke a static `call`, so only `StaticCall.call()` uses
/// it.
class StaticCall {
  static int call() => 1;
}

class UnusedStaticCall {
  static int call() => 1;
}

/// Torn off from a conditional expression and a `??` expression, whose
/// static type is this class.
class InComposite {
  int call(int x) => x;
}
