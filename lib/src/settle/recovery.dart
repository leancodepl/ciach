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
import 'package:collection/collection.dart';
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
  ///
  /// [refsByCandidate] are every reference the server reported, live or not.
  /// Most of their sites are not looked up again: the server already said what
  /// each refers to. A site can also use a declaration that shares it, such as
  /// the constructor at `Foo()` that the server reports for the class `Foo`,
  /// or the setter at `x += 1` reported for the getter `x`, so the reported
  /// references of a declaration whose sibling has none are looked up too.
  Future<CrossLibraryReferences> recover(
    LspClient client,
    List<Candidate> candidates,
    List<List<Location>> liveRefs,
    List<List<Location>> refsByCandidate,
  ) {
    final unsure = [
      for (final (i, candidate) in candidates.indexed)
        if (_classifier.externalRefs(candidate, liveRefs[i]).isEmpty &&
            candidate.symbol.kind != .class$ &&
            !candidate.isExtension)
          candidate,
    ];
    final emptyRefNames = <String>{
      for (final candidate in unsure) ...[
        _simpleName(candidate.symbol.name),
        // An unnamed constructor is spelled by the class name at an
        // ordinary `Foo(…)` site but as `new` at a dot-shorthand one
        // (`.new(…)`), so probe for both spellings.
        candidate.symbol.declarationName(candidate.container),
      ],
    }..removeAll(_probedNames);
    if (emptyRefNames.isEmpty) {
      return .value(.empty);
    }
    _probedNames.addAll(emptyRefNames);
    final siblings = _Siblings(unsure);
    _log.info('Recovering cross-library references…');
    return CrossLibraryReferences.resolve(
      client: client,
      sources: _sources,
      candidates: candidates,
      emptyRefNames: emptyRefNames,
      reportedRefs: [
        for (final (i, candidate) in candidates.indexed)
          if (!siblings.mayShareSitesWith(candidate)) ...refsByCandidate[i],
      ],
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
    for (final (i, candidate) in candidates.indexed) {
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
        .new(
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

/// The candidates with no live reference, by the declarations that may share
/// their sites: the other members of the same container with the same name
/// (a getter and its setter), and the type they belong to (a class and its
/// constructors).
///
/// The recovery skips the sites that the server reported, because it already
/// said what each refers to. A shared site refers to both declarations,
/// though: `Foo()` uses the class `Foo` and its constructor. If the server
/// reported it only for the class, skipping it would leave the constructor
/// without its use, and `--remove` would delete a constructor that is called.
/// So the reported sites of a declaration that shares them with a candidate
/// here are looked up anyway.
final class _Siblings {
  _Siblings(Iterable<Candidate> unsure)
    : _byName = unsure.groupSetsBy(_nameIn),
      _containers = {for (final candidate in unsure) ?candidate.container};

  final Map<(String?, String), Set<Candidate>> _byName;
  final Set<String> _containers;

  static (String?, String) _nameIn(Candidate candidate) => (
    candidate.container,
    ReferenceRecovery._simpleName(candidate.symbol.name),
  );

  /// Whether a candidate other than [candidate] may use its sites.
  bool mayShareSitesWith(Candidate candidate) =>
      _containers.contains(candidate.symbol.name) ||
      (_byName[_nameIn(candidate)]?.difference({candidate}).isNotEmpty ??
          false);
}
