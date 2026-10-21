// An override of `OverriddenElsewhere.~` in scenarios/operators.dart, and its
// only use. No test scans this file, so ciach opens it only to rename the
// override.

import 'package:sample_pkg/scenarios/operators.dart';

class UnscannedOverride extends OverriddenElsewhere {
  const UnscannedOverride();

  @override
  OverriddenElsewhere operator ~() => this;
}

void main() {
  print(~const UnscannedOverride());
}
