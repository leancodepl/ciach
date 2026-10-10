import 'package:ciach/src/lsp/semantic_tokens.dart';

/// `@JSExport` on a class exports its public instance members. `package:js`
/// 0.6.6 and `dart:js_interop`.
bool isJsExported(Iterable<SemanticToken> metadata) =>
    metadata.any((t) => t.isAnnotationNamed('JSExport'));
