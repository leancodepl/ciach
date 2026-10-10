import 'package:ciach/src/lsp/semantic_tokens.dart';

bool isReflectiveTest(Iterable<SemanticToken> metadata) =>
    metadata.any((t) => t.isAnnotationNamed('reflectiveTest'));

/// Returns whether `defineReflectiveTests` runs the method called [name],
/// either as a test or as a set-up or tear-down method
/// (test_reflective_loader 0.4.0+).
bool isReflectiveTestMethod(String name) => _testMethod.hasMatch(name);

final _testMethod = RegExp(
  r'^(?:(?:solo_)?test_|(?:solo_)?fail_|skip_test_)|^(?:setUp|tearDown)(?:Class)?$',
);
