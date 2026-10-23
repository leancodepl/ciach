// An override of `OverriddenElsewhere.~`, and its only use. No test scans
// this file.

import 'package:sample_pkg/scenarios/operators.dart';

class UnscannedOverride extends OverriddenElsewhere {
  const UnscannedOverride();

  @override
  OverriddenElsewhere operator ~() => this;
}

void main() {
  print(~const UnscannedOverride());
}
