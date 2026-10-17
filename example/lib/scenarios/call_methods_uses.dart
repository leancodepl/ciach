// Uses for the `call` method fixture: each `call` in
// scenarios/call_methods.dart is used here in one form, except
// `NeverCalled.call`, `UnusedStaticCall.call` and
// `OnlyCalledFromDeadCode.call`, which only dead code calls.

import 'package:sample_pkg/scenarios/call_methods.dart';

void main() {
  print(Invoked()(1));
  final int Function(int) tornOff = TornOff();
  final Function tornOffAsFunction = TornOffAsFunction();
  print([tornOff, tornOffAsFunction]);
  print(Generic()<int>(1));
  print(Holder().held());
  print(Derived()());
  final Handler handler = HandlerImpl();
  handler();
  print(Explicit().call());
  print(ExplicitWithArgument().call(InExplicitArgument()()));
  print(const Wrapped()());
  print(SelfInvoked().twice(1));
  final maybe = DateTime.now().isUtc ? null : InComposite();
  final int Function(int) branch = DateTime.now().isUtc
      ? InComposite()
      : maybe ?? InComposite();
  print(branch);
  print(Level.low());
  print(WithCallable()());
  print(NamedParameter()(x: 1));
  print(StaticCall.call());
  print([NeverCalled(), OnlyCalledFromDeadCode(), UnusedStaticCall]);
}
