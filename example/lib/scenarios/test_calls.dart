// Fixtures for test and test-group calls. The analysis server lists a call to
// a function annotated `@isTest` or `@isTestGroup` (as `test`, `group`,
// `testWidgets` and `patrolTest` are) in the outline, and as a method in the
// document symbols, though it declares nothing. Scanned only by the dedicated
// test (excluded from the default-run assertions); see test/finder_test.dart.
// Expected findings: deadNextToTests only.

import 'package:meta/meta.dart';

@isTestGroup
void suite(String description, void Function() body) => body();

@isTest
void spec(String description, void Function() body) => body();

void main() {
  suite('outer', () {
    spec('inner', () {});
  });
  spec('top-level', () {});
}

void deadNextToTests() {}
