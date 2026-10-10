import 'package:ciach/src/lsp/semantic_tokens.dart';

/// `@JSExport` on a class exports its public instance members. Matched by
/// name, so both `dart:js_interop`'s annotation and the older one from
/// `package:js` (added in 0.6.6) count.
bool isJsExported(Iterable<SemanticToken> metadata) =>
    metadata.any((t) => t.isAnnotationNamed('JSExport'));
