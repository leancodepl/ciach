import 'package:ciach/src/lsp/semantic_tokens.dart';

bool isReflectiveTest(Iterable<SemanticToken> metadata) =>
    metadata.any((t) => t.isAnnotationNamed('reflectiveTest'));

/// Whether `defineReflectiveTests` runs a method with this [name]. It runs
/// the methods whose names start with one of these prefixes, as of
/// test_reflective_loader 0.4.0, the version that added `setUpClass`.
bool isReflectiveTestMethod(String name) => _testMethod.hasMatch(name);

final _testMethod = RegExp(
  r'^(?:(?:solo_)?test_|(?:solo_)?fail_|skip_test_)|^(?:setUp|tearDown)(?:Class)?$',
);
