import 'package:ciach/src/lsp/semantic_tokens.dart';

/// `@JSExport` on a class exports its public instance members.
bool isJsExported(Iterable<SemanticToken> metadata) =>
    metadata.any((t) => t.isAnnotationNamed('JSExport'));
