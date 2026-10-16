// Fixtures for `call` methods, which an object invoked like a function
// (`obj(1)`) or used where a function is expected (`int Function(int) f = obj`)
// uses without a reference that the server reports. Every form of use is in
// call_methods_uses.dart. Scanned only by the dedicated test (excluded from
// the default-run assertions); see test/finder/call_methods_test.dart.
// Expected findings: NeverCalled.call, OnlyCalledFromDeadCode.call and
// callFromDeadCode.

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
