import 'package:ciach/src/lsp/semantic_tokens.dart';

/// Returns whether [metadata] contains `@JSExport`. On a class, `@JSExport`
/// exports all of the public instance members of the class. The annotation is
/// matched by its name, so both the annotation from `dart:js_interop` and the
/// older one from `package:js` (added in version 0.6.6) are recognized.
bool isJsExported(Iterable<SemanticToken> metadata) =>
    metadata.any((t) => t.isAnnotationNamed('JSExport'));
