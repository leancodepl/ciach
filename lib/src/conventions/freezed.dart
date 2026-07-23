/*
 * AI-Provenance:
 *   model: claude-opus-4-8
 *   harness: Claude Code
 *   plugins:
 *     - lean-ai-provenance
 *   skills:
 *     - mark-ai-provenance
 */

import 'package:ciach/src/candidates.dart';
import 'package:ciach/src/source_index.dart';
import 'package:ciach/src/symbols.dart';
import 'package:ciach/src/syntax_rules.dart';
import 'package:pro_lsp/pro_lsp.dart' show DocumentSymbol;

/// `freezed` union conventions.
///
/// A `@freezed`/`@Freezed` union's redirecting-factory arms are constructed
/// only by the generated `fromJson`, never hand-called, so a reference search
/// sees them as unused. This tracks which classes carry the annotation (fed in
/// during candidate collection) and, given a union whose `fromJson` is used,
/// treats those arms as live rather than dead.
class FreezedUnions {
  /// Keys `(path, class name)` of classes annotated `@freezed`/`@Freezed`.
  final _annotatedClasses = <DeclKey>{};

  static final _annotation = RegExp(r'@(?:freezed|Freezed)\b');

  /// Records [symbol] as freezed-annotated when it is a type whose leading
  /// metadata carries `@freezed`/`@Freezed`. Called for every symbol during
  /// candidate collection.
  void noteIfAnnotated(String path, DocumentSymbol symbol, List<String> lines) {
    if (typeLikeKinds.contains(symbol.kind) &&
        _annotation.hasMatch(symbol.leadingMetadata(lines))) {
      _annotatedClasses.add(DeclKey(path, symbol.name));
    }
  }

  /// Indices into [candidates] of redirecting-factory arms of a `@freezed`/
  /// `@Freezed` union with a referenced `fromJson` — live serialization members
  /// that read as unused. Conservative: never-dispatched arms are kept too,
  /// being statically indistinguishable from live ones.
  Set<int> deserializationOnlyArms(
    List<Candidate> candidates,
    List<RefStatus> statuses,
    SourceIndex sources,
  ) {
    final unionsWithUsedFromJson = <DeclKey>{};
    for (var i = 0; i < candidates.length; i++) {
      final c = candidates[i];
      if (c.symbol.kind == .constructor &&
          statuses[i] == .used &&
          c.symbol.declarationName(c.container) == 'fromJson') {
        if (c.containerKey case final key?) {
          unionsWithUsedFromJson.add(key);
        }
      }
    }

    final arms = <int>{};
    for (var i = 0; i < candidates.length; i++) {
      if (statuses[i] != .unused) {
        continue;
      }
      final c = candidates[i];
      if (c.symbol.kind != .constructor) {
        continue;
      }
      if (c.containerKey case final key?
          when _annotatedClasses.contains(key) &&
              unionsWithUsedFromJson.contains(key) &&
              sources.isRedirectingFactory(c)) {
        arms.add(i);
      }
    }
    return arms;
  }
}
