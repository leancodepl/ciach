/*
 * AI-Provenance:
 *   model: claude-fable-5-1
 *   harness: Claude Code
 */

import 'package:ciach/src/collect/candidates.dart';
import 'package:ciach/src/fetch/cross_library_refs.dart';
import 'package:ciach/src/lsp/lsp_client.dart';
import 'package:ciach/src/model/finder_result.dart';
import 'package:ciach/src/settle/reference_classifier.dart';
import 'package:ciach/src/source/source_index.dart';
import 'package:ciach/src/source/symbols.dart';
import 'package:ciach/src/util/log.dart';
import 'package:ciach/src/util/paths.dart';
import 'package:pro_lsp/pro_lsp.dart' show Location;

final _log = Logger('ciach.finder');

/// The secondary definition check over the rounds of a run: probes each name
/// a round leaves unreferenced, once, and words what it recovers as warnings.
final class ReferenceRecovery {
  ReferenceRecovery({
    required SourceIndex sources,
    required ReferenceClassifier classifier,
    required int concurrency,
  }) : _sources = sources,
       _classifier = classifier,
       _concurrency = concurrency;

  final SourceIndex _sources;
  final ReferenceClassifier _classifier;
  final int _concurrency;

  /// Names the cross-library recovery has already probed.
  final _probedNames = <String>{};

  /// Runs the secondary definition check for the candidates with no reference
  /// outside their own span — the potential false positives. Names probed in an
  /// earlier round are skipped.
  Future<CrossLibraryReferences> recover(
    LspClient client,
    List<Candidate> candidates,
    List<List<Location>> liveRefs,
  ) {
    final emptyRefNames = <String>{
      for (var i = 0; i < candidates.length; i++)
        if (_classifier.externalRefs(candidates[i], liveRefs[i]).isEmpty &&
            candidates[i].symbol.kind != .class$ &&
            !candidates[i].isExtension) ...[
          _simpleName(candidates[i].symbol.name),
          // An unnamed constructor is spelled by the class name at an
          // ordinary `Foo(…)` site but as `new` at a dot-shorthand one
          // (`.new(…)`), so probe for both spellings.
          candidates[i].symbol.declarationName(candidates[i].container),
        ],
    }..removeAll(_probedNames);
    if (emptyRefNames.isEmpty) {
      return .value(.empty);
    }
    _probedNames.addAll(emptyRefNames);
    _log.info('Recovering cross-library references…');
    return CrossLibraryReferences.resolve(
      client: client,
      sources: _sources,
      candidates: candidates,
      emptyRefNames: emptyRefNames,
      concurrency: _concurrency,
    );
  }

  /// One warning per declaration the secondary check kept alive: it had no
  /// reported references outside itself, yet a use resolved back to it.
  List<RecoveredReference> warnings(
    List<Candidate> candidates,
    List<List<Location>> refsByCandidate,
    CrossLibraryReferences crossLib,
    String rootPath,
    String analysisRoot,
  ) {
    final warnings = <RecoveredReference>[];
    for (var i = 0; i < candidates.length; i++) {
      final candidate = candidates[i];
      if (_classifier.externalRefs(candidate, refsByCandidate[i]).isNotEmpty ||
          candidate.symbol.kind == .class$ ||
          candidate.isExtension) {
        continue;
      }
      final usage = crossLib.recoveredUsage(candidate);
      if (usage == null) {
        continue;
      }
      final start = candidate.symbol.selectionRange.start;
      warnings.add(
        RecoveredReference(
          name: candidate.symbol.declarationName(candidate.container),
          container: candidate.container,
          filePath: relativePosix(candidate.path, rootPath),
          line: start.line + 1,
          column: start.character + 1,
          usageFilePath: relativeUsagePosix(usage.path, rootPath, analysisRoot),
          usageLine: usage.line + 1,
          usageColumn: usage.character + 1,
        ),
      );
    }
    warnings.sort((a, b) {
      final byFile = a.filePath.compareTo(b.filePath);
      if (byFile != 0) {
        return byFile;
      }
      final byLine = a.line.compareTo(b.line);
      return byLine != 0 ? byLine : a.column.compareTo(b.column);
    });
    return warnings;
  }

  /// The last-segment name — `bar` for a constructor reported as `Foo.bar` —
  /// which is the identifier a usage site spells.
  static String _simpleName(String name) =>
      name.contains('.') ? name.split('.').last : name;
}
