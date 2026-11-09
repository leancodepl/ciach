import 'package:ciach/src/analysis/public_api.dart';
import 'package:ciach/src/analysis/resolved_file.dart';
import 'package:ciach/src/analysis/resolved_files.dart';
import 'package:ciach/src/collect/candidates.dart';
import 'package:ciach/src/collect/kept_declarations.dart';
import 'package:ciach/src/collect/problems.dart';
import 'package:ciach/src/conventions/conditional_imports.dart';
import 'package:ciach/src/conventions/entry_points.dart';
import 'package:ciach/src/conventions/freezed.dart';
import 'package:ciach/src/conventions/gen_l10n.dart';
import 'package:ciach/src/conventions/resolved_declaration.dart';
import 'package:ciach/src/model/finder_options.dart';
import 'package:ciach/src/source/ignore_markers.dart';
import 'package:ciach/src/source/outline.dart';
import 'package:ciach/src/source/symbols.dart';
import 'package:ciach/src/util/log.dart';
import 'package:ciach/src/util/paths.dart';
import 'package:collection/collection.dart';

final _log = Logger('ciach.finder');

const _uncollectedFile = 'Could not list declarations; file skipped.';

const _compileErrors =
    'Has compile errors; the declarations that it uses may be reported.';

/// Which declarations get their references checked: every declaration of a
/// scanned file, except the kinds, visibilities, entry points and
/// conventions that the options leave out.
final class CandidateCollector {
  CandidateCollector({
    required this.options,
    required FreezedUnions freezed,
    PublicApi? publicApi,
    ConditionalImports? conditionalImports,
  }) : _freezed = freezed,
       _publicApi = publicApi,
       _conditionalImports = conditionalImports ?? .empty;

  final FinderOptions options;

  /// Freezed-union tracking, fed as candidates are collected.
  final FreezedUnions _freezed;

  /// What other packages can import, when exported declarations are left out.
  final PublicApi? _publicApi;

  final ConditionalImports _conditionalImports;

  /// What this run leaves unchecked on purpose, and why.
  late final _entryPoints = EntryPoints(options.entryPoints);

  late final _kept = KeptDeclarations(_entryPoints);

  /// The pairing names in each conditional-import variant that was read,
  /// candidates or not; see [ConditionalImports.share].
  final declaredInVariants = <String, Set<String>>{};

  /// One line per declaration kept as an entry point or by a marker, for
  /// `--verbose`.
  void reportSkipped() => _kept.report();

  /// The declarations of the file at [path] worth checking. [files]
  /// resolves the file.
  Future<List<Candidate>> collect(
    ResolvedFiles files,
    String path,
    String rootPath,
  ) async {
    final file = await files.of(path);
    if (file == null) {
      if (!recordIfUnreadable(path)) {
        recordProblem(_uncollectedFile, unresolvedFile, path: path);
      }
      return const [];
    }
    if (file.firstError case (:final position, :final message)) {
      recordProblem(_compileErrors, message, path: path, position: position);
    }
    final relativePath = relativePosix(path, rootPath);
    if (_conditionalImports.contains(path)) {
      declaredInVariants[path] = ConditionalImports.pairingNames(
        file.outline.children,
      );
    }
    final scanned = (
      path: path,
      relativePath: relativePath,
      resolved: file,
      markers: _Markers(file.markers),
    );
    // The whole walk has to run before the filter: it records the entry-point
    // containers the filter drops, and a container comes before its members.
    final candidates = _collect(scanned, file.outline.children, (
      container: null,
      keptMembers: const [],
    )).toList();
    scanned.markers.warnAbout(relativePath);
    return _kept.withoutContainers(candidates, relativePath).toList();
  }

  /// Recursively walks the declarations in [outlines], keeping only those
  /// worth checking. [parent] is the type that declares them, or `null` at
  /// the top level, and the members that the rules keep in it.
  Iterable<Candidate> _collect(
    _ScannedFile file,
    List<Outline> outlines,
    ({Outline? container, List<KeptMembers> keptMembers}) parent,
  ) sync* {
    final statement = _Statement();
    for (final outline in _declarations(outlines)) {
      final start = statement.startOf(outline);
      final candidate = Candidate(
        path: file.path,
        outline: outline,
        containerOutline: parent.container,
      );
      final declaration = _kept.declarationOf(
        file.relativePath,
        candidate,
        file.resolved,
      );
      _freezed.noteIfAnnotated(file.path, outline, declaration.annotations);
      if (_isCandidate(
        candidate,
        declaration,
        containerMembers: parent.keptMembers,
        markers: file.markers,
        start: start,
      )) {
        yield candidate;
      }
      yield* _collect(
        file,
        outline.children,
        outline.element.declaresMembers
            ? (
                container: outline,
                keptMembers:
                    _kept.keptMembersOf(declaration) ?? parent.keptMembers,
              )
            : parent,
      );
    }
  }

  /// The declarations in [outlines].
  ///
  /// A `test(...)` or `group(...)` call is not a declaration, and removing it
  /// would delete the test, so it is replaced by the declarations inside its
  /// closure.
  static Iterable<Outline> _declarations(List<Outline> outlines) sync* {
    for (final outline in outlines) {
      if (outline.element.isDeclaration) {
        yield outline;
      } else {
        yield* _declarations(outline.children);
      }
    }
  }

  /// Whether [candidate] is public and left out: by `--no-public`, or as part
  /// of an API that `exported-packages` leaves out. An unnamed extension and
  /// its members are private, since no other library can use them.
  bool _skipsPublic(Candidate candidate) {
    if (isPrivateName(candidate.name) || candidate.belongsToUnnamedExtension) {
      return false;
    }
    return !options.includePublic ||
        (_publicApi?.exposes(
              candidate.path,
              candidate.container ?? candidate.name,
            ) ??
            false);
  }

  /// Returns whether [candidate], which the rules read as [declaration] and
  /// whose doc comment and annotations start on line [start], is checked:
  /// neither kept by one of [markers] nor left out.
  bool _isCandidate(
    Candidate candidate,
    ResolvedDeclaration declaration, {
    required List<KeptMembers> containerMembers,
    required _Markers markers,
    required int start,
  }) {
    if (markers.keeping(
          start: start,
          nameLine: candidate.outline.nameRange.start.line,
        )
        case final kept?) {
      _kept.byMarker(declaration.relativePath, candidate, kept);
      return false;
    }
    return _shouldConsider(
      candidate,
      declaration,
      containerMembers: containerMembers,
    );
  }

  /// Returns whether the references to [candidate] should be checked.
  bool _shouldConsider(
    Candidate candidate,
    ResolvedDeclaration declaration, {
    required List<KeptMembers> containerMembers,
  }) {
    if (!options.kinds.contains(candidate.reportedKind)) {
      return false;
    }
    // Only the messages of a gen-l10n file are checked: removing one from the
    // ARB file leaves the code around them.
    if (translationsOf(candidate, options.translations, options.rootPath) !=
            null &&
        !isTranslationMessage(candidate)) {
      return false;
    }
    if (_kept.isEntryPoint(declaration, containerMembers)) {
      return false;
    }
    if (_skipsPublic(candidate)) {
      return false;
    }
    // The primary constructor in the type's header is the candidate.
    if (candidate.outline.element.isPrimaryConstructorBody) {
      return false;
    }

    if (options.skipOverrides &&
        declaration.annotations.any(
          (annotation) => annotation.name == 'override',
        )) {
      return false;
    }
    return true;
  }
}

/// The file whose declarations are being collected: its path, the path
/// relative to the package root, the file as the analyzer resolves it, and
/// its `// ciach:` markers.
typedef _ScannedFile = ({
  String path,
  String relativePath,
  ResolvedFile resolved,
  _Markers markers,
});

/// The statement that the declarations being collected belong to. A marker
/// above a variable statement keeps every declarator, also the later ones,
/// such as `b` in `final int a, b;`, whose range starts at its name.
final class _Statement {
  var _start = 0;

  /// The line that the statement of the declaration [outline] starts on.
  int startOf(Outline outline) {
    final isVariable = const <OutlineKind>{
      .field,
      .topLevelVariable,
    }.contains(outline.element.kind);
    if (isVariable && outline.range.start == outline.codeRange.start) {
      return _start;
    }
    return _start = outline.range.start.line;
  }
}

/// The markers of one file, and which of them kept a declaration.
final class _Markers {
  _Markers(this._markers);

  final IgnoreMarkers _markers;
  final _used = <MarkerAt>{};

  /// The marker keeping the declaration that starts on [start] and is named
  /// on [nameLine]; see [IgnoreMarkers.keeping].
  MarkerAt? keeping({required int start, required int nameLine}) {
    if (_markers.isEmpty) {
      return null;
    }
    final keepers = _markers.keepers(start: start, nameLine: nameLine);
    _used.addAll(keepers);
    return keepers.firstOrNull;
  }

  /// Warns about the malformed markers in the file at [relativePath], and
  /// those that kept nothing.
  void warnAbout(String relativePath) {
    final warnings = [
      ..._markers.issues,
      for (final marker in _markers.all)
        if (!_used.contains(marker))
          (
            line: marker.line,
            message: switch (marker.marker) {
              ignoreMarker =>
                '`// $ignoreMarker` keeps no declaration: on a line of its own it applies to the declaration on the next line, after code to the one named on its line',
              _ => 'the `// ${marker.marker}` range keeps no declaration',
            },
          ),
    ]..sort((a, b) => a.line.compareTo(b.line));
    for (final (:line, :message) in warnings) {
      _log.warning('$relativePath:${line + 1}: $message.');
    }
  }
}
