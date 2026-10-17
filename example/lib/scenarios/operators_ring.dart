// An override of `Ring.~` in scenarios/operators.dart, and its only use. No
// test scans this file, so ciach opens it only to rename the override.

import 'package:sample_pkg/scenarios/operators.dart';

class GoldRing extends Ring {
  const GoldRing();

  @override
  Ring operator ~() => this;
}

void main() {
  print(~const GoldRing());
}
