import 'package:ciach/src/collect/candidates.dart';
import 'package:ciach/src/fetch/reference_fetch.dart';
import 'package:ciach/src/lsp/exceptions.dart';
import 'package:ciach/src/lsp/lsp_client.dart';
import 'package:ciach/src/lsp/problems.dart';
import 'package:ciach/src/lsp/semantic_tokens.dart';
import 'package:ciach/src/model/unused_declaration.dart';
import 'package:ciach/src/source/parameters.dart';
import 'package:ciach/src/source/reference_kinds.dart';
import 'package:ciach/src/source/source_index.dart';
import 'package:ciach/src/source/symbols.dart';
import 'package:ciach/src/source/syntax_rules.dart';
import 'package:ciach/src/util/concurrency.dart';
import 'package:ciach/src/util/extensions.dart';
import 'package:ciach/src/util/paths.dart';
import 'package:collection/collection.dart';
import 'package:pro_lsp/pro_lsp.dart' show Location, Position, Range;

const _uncheckedParameters =
    'Could not check how a function is used; its parameters are not reported.';

/// Reports the parameters that the body of a function, method or constructor
/// never reads, when nothing else fixes its signature: it isn't an override,
/// nothing overrides it, and no code tears it off.
final class UnusedParameters {
  UnusedParameters({
    required SourceIndex sources,
    required ReferenceFetch fetch,
    required int concurrency,
  }) : _sources = sources,
       _fetch = fetch,
       _concurrency = concurrency;

  static const hint = 'also remove its argument at every call';

  final SourceIndex _sources;
  final ReferenceFetch _fetch;
  final int _concurrency;

  /// Returns a report-only finding for each parameter of [owners] that is
  /// never read. An owner that one of [findings] reports, or deletes with an
  /// enclosing declaration, is left out.
  Future<List<UnusedDeclaration>> findings(
    LspClient client,
    List<Candidate> owners,
    List<UnusedDeclaration> findings,
    String rootPath,
  ) async {
    final reported = _Reported(findings, rootPath);
    final live = owners.whereNot(reported.covers).toList();
    await _fetch.fetchSelectionRanges(client, {
      for (final MapEntry(key: path, value: inFile)
          in live.groupListsBy((owner) => owner.path).entries)
        path: {
          for (final owner in inFile) ...[
            owner.symbol.selectionRange.start,
            ?_sources.redirectProbePosition(owner),
            for (final parameter in _sources.parameterDeclarations(
              path,
              owner.outline,
            ))
              parameter.start,
          ],
        },
    });
    final unread = [
      for (final owner in live)
        if (_unreadParameters(owner) case final parameters
            when parameters.isNotEmpty)
          (owner: owner, parameters: parameters),
    ];
    final fixed = await mapPooled(
      unread,
      _concurrency,
      (entry) => _hasFixedSignature(client, entry.owner),
    );
    return [
      for (final (i, (:owner, :parameters)) in unread.indexed)
        if (!fixed[i])
          for (final parameter in parameters)
            _finding(owner, parameter, rootPath),
    ];
  }

  /// The own parameters of [owner] that its body never reads, or none when it
  /// has no body that could read them.
  List<SemanticToken> _unreadParameters(Candidate owner) {
    final path = owner.path;
    final outline = owner.outline;
    final own = _sources.ownParameters(path, outline);
    final list = own.firstOrNull?.let(
      (first) => _sources.parameterListOf(path, outline, first),
    );
    if (list == null) {
      return const [];
    }
    final isConstructor = owner.symbol.kind == .constructor;
    if (isConstructor
        ? _sources.isRedirectingFactory(owner)
        : !_sources.hasBody(path, outline, list)) {
      return const [];
    }
    // A primary constructor's parameters are also read in the class body: in
    // field initializers, and in its own `this` body.
    final scope = isConstructor && _sources.isDeclaredInTypeHeader(owner)
        ? owner.containerOutline?.codeRange
        : outline.codeRange;
    return [
      for (final parameter in own)
        if (!_isWildcard(parameter.text) &&
            !_sources.isRead(path, scope ?? outline.codeRange, parameter))
          parameter,
    ];
  }

  /// Whether something other than the calls of [owner] fixes its signature:
  /// a member that overrides it, or a reference that tears it off. `true` when
  /// the server can't tell.
  Future<bool> _hasFixedSignature(LspClient client, Candidate owner) async {
    final name = owner.symbol.selectionRange.start;
    try {
      if (owner.symbol.kind == .method &&
          (await client.implementations(owner.uri, name)).isNotEmpty) {
        return true;
      }
      final refs = await client.references(owner.uri, name);
      await _fetch.fetchSelectionRanges(client, {
        for (final MapEntry(key: path, value: inFile)
            in refs.groupListsBy((ref) => SourceIndex.pathOf(ref.uri)).entries)
          path: {for (final ref in inFile) ref.range.start},
      });
      return refs.any(_tearsOff);
    } on LspRequestException catch (e) {
      recordProblem(
        _uncheckedParameters,
        e,
        path: owner.path,
        position: name,
        name: owner.symbol.declarationName(owner.container),
      );
      return true;
    }
  }

  /// Whether [ref] uses the function it names other than by calling it. A
  /// doc comment link uses nothing.
  bool _tearsOff(Location ref) =>
      !_sources.isDocReference(ref) && !_sources.isCall(ref);

  UnusedDeclaration _finding(
    Candidate owner,
    SemanticToken parameter,
    String rootPath,
  ) {
    final ownerName = owner.symbol.declarationName(owner.container);
    final start = parameter.start;
    final range =
        _sources.selectionRangeAt(owner.path, start)?.range ??
        Range(
          start: start,
          end: .new(line: start.line, character: parameter.end),
        );
    return .new(
      name: parameter.text,
      kind: parameterKind,
      filePath: relativePosix(owner.path, rootPath),
      line: start.line + 1,
      column: start.character + 1,
      isPrivate:
          isPrivateName(ownerName) ||
          (owner.container?.let(isPrivateName) ?? false),
      container: owner.container?.let((c) => '$c.$ownerName') ?? ownerName,
      range: range.toDeclarationRange,
      removalBlocked: true,
      hint: hint,
    );
  }

  /// Whether [name] is `_`, `__` or longer, which marks a parameter as unused
  /// on purpose.
  static bool _isWildcard(String name) => name.split('').every((c) => c == '_');
}

/// The findings of a scan, by absolute path, to tell whether one of them
/// deletes a function, method or constructor.
final class _Reported {
  _Reported(Iterable<UnusedDeclaration> findings, String rootPath)
    : _byPath = findings.groupListsBy(
        (finding) => absoluteUnder(finding.filePath, rootPath),
      );

  final Map<String, List<UnusedDeclaration>> _byPath;

  bool covers(Candidate owner) {
    final name = owner.symbol.selectionRange.start;
    return _byPath[owner.path]?.any(
          (finding) => _contains(finding.fullRange, name),
        ) ??
        false;
  }

  static bool _contains(DeclarationRange range, Position position) =>
      Position(
        line: range.startLine,
        character: range.startColumn,
      ).atOrBefore(position) &&
      position.atOrBefore(
        Position(line: range.endLine, character: range.endColumn),
      );
}
