// Uses for the `call` method fixture: each `call` in
// scenarios/call_methods.dart is used here in one form, and only
// `NeverCalled.call` and `OnlyCalledFromDeadCode.call` never are.

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
  print(const Wrapped()());
  print(SelfInvoked().twice(1));
  print([NeverCalled(), OnlyCalledFromDeadCode()]);
}
