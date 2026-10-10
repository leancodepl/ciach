import 'package:ciach/src/lsp/semantic_tokens.dart';

bool isReflectiveTest(Iterable<SemanticToken> metadata) =>
    metadata.any((t) => t.isAnnotationNamed('reflectiveTest'));

/// The prefixes `defineReflectiveTests` runs, up to test_reflective_loader
/// 0.4.0, which added `setUpClass`.
bool isReflectiveTestMethod(String name) => _testMethod.hasMatch(name);

final _testMethod = RegExp(
  r'^(?:(?:solo_)?test_|(?:solo_)?fail_|skip_test_)|^(?:setUp|tearDown)(?:Class)?$',
);
