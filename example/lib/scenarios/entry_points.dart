// Entry points: declarations a framework or tool calls by convention, with no
// reference in the source. A built-in convention exempts only a declaration
// meeting its whole contract; a project lists its own with `--entry-point`.
//
// Expected findings, by default: everything here. `testExecutable` has the name
// and shape `flutter test` wants but sits in the wrong file, so it is dead like
// any other function. With `--entry-point` specs for `integrationMain`,
// `Plugin.registerWith` and `bootstrap`, only `testExecutable` remains.

import 'dart:async';

/// Right name, right signature, wrong file: the `flutter test` bootstrap only
/// ever imports a `flutter_test_config.dart`.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  await testMain();
}

/// A project-specific entry point some driver script calls by convention.
Object integrationMain() => Plugin;

/// A member entry point, listed as `Plugin.registerWith`.
class Plugin {
  static void registerWith() {}
}

/// Listed by bare name, so matched in any file.
void bootstrap() {}
