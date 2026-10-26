/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

// Uses for the type alias fixture: each used alias in
// scenarios/type_aliases.dart is named here in one form.

import 'package:sample_pkg/scenarios/type_aliases.dart';

void main() {
  const AsType list = [];
  void callback(int value) {}
  final AsCallback asCallback = callback;
  int compare(int a, int b) => a - b;
  final AsCompare asCompare = compare;
  final pairs = <AsPair<int>>[(1, 2)];
  final Object point = Constructed();
  print([list, asCallback, asCompare, pairs, point]);
  print(NamedConstructed.named());
  print(StaticAccess.create());
  print(point is IsTest);
  print(point is! IsNotTest);
  print(TornOff.new);
}
