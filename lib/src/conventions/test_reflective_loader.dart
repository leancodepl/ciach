import 'package:ciach/src/lsp/semantic_tokens.dart';

bool isReflectiveTest(Iterable<SemanticToken> metadata) =>
    metadata.any((t) => t.isAnnotationNamed('reflectiveTest'));

/// Returns whether `defineReflectiveTests` runs the method called [name].
/// It runs the methods whose names start with `test_`, `solo_test_`, `fail_`,
/// `solo_fail_` or `skip_test_`, and also `setUp`, `tearDown`, `setUpClass`
/// and `tearDownClass`. The list matches test_reflective_loader 0.4.0, which
/// is the version that added `setUpClass`.
bool isReflectiveTestMethod(String name) => _testMethod.hasMatch(name);

final _testMethod = RegExp(
  r'^(?:(?:solo_)?test_|(?:solo_)?fail_|skip_test_)|^(?:setUp|tearDown)(?:Class)?$',
);
