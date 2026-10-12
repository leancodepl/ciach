import 'package:ciach/src/cached_map.dart';
import 'package:ciach/src/candidates.dart';
import 'package:ciach/src/directives.dart';
import 'package:ciach/src/extensions.dart';
import 'package:ciach/src/packages.dart';
import 'package:ciach/src/reachability.dart';
import 'package:ciach/src/reference_classifier.dart';
import 'package:ciach/src/symbols.dart';
import 'package:pro_lsp/pro_lsp.dart' show DocumentSymbol, Location;

/// The variants of conditional imports and exports: the libraries one
/// chooses between, such as `io.dart` and `web.dart` in
/// `import 'io.dart' if (dart.library.js_interop) 'web.dart';`.
///
/// The analysis server resolves every use to the default file, so namesakes in
/// the variants share their references: they are used, or reported and
/// removed, together.
final class ConditionalImports {
  ConditionalImports._(this._counterparts);

  /// Reads the conditional directives in every Dart file under [rootPath].
  /// The files of each variant get the files of the other variants of the
  /// same directive as counterparts.
  factory ConditionalImports.scan(String rootPath) {
    final counterparts = <String, Set<String>>{};
    for (final variants in _DirectiveIndex(rootPath).conditionalVariants()) {
      for (final (i, files) in variants.indexed) {
        final otherFiles = {
          for (final (j, other) in variants.indexed)
            if (j != i) ...other,
        };
        for (final file in files) {
          counterparts.putIfAbsent(file, () => {}).addAll(otherFiles);
        }
      }
    }
    // A file that two variants both export is not its own counterpart.
    return ._({
      for (final MapEntry(key: file, value: others) in counterparts.entries)
        file: others.difference({file}),
    });
  }

  static final empty = ConditionalImports._(const {});

  /// The files of the other variants, by file of a variant; see
  /// [_DirectiveIndex.libraryFiles].
  final Map<String, Set<String>> _counterparts;

  /// Whether [path] belongs to a variant of a conditional directive.
  bool contains(String path) => _counterparts.containsKey(path);

  /// The files of the other variants of the directives that name [path].
  Set<String> counterpartFilesOf(String path) =>
      _counterparts[path] ?? const {};

  /// The pairing names in [symbols], a file's outline, and their members:
  /// `Type.member`, or the top-level name. Private names and members of
  /// unnamed extensions are left out, since no other library can use them.
  static Set<String> pairingNames(List<DocumentSymbol> symbols) => {
    for (final symbol in symbols)
      if (pairingName(symbol, null) case final name?) ...[
        name,
        if (symbol.children case final children?
            when typeLikeKinds.contains(symbol.kind))
          for (final child in children) ?pairingName(child, symbol.name),
      ],
  };

  /// The name that pairs [symbol] with its namesakes; see [pairingNames].
  static String? pairingName(DocumentSymbol symbol, String? container) {
    final type = container ?? symbol.name;
    if (isPrivateName(symbol.name) ||
        isPrivateName(type) ||
        type.startsWith('extension on ')) {
      return null;
    }
    final name = symbol.declarationName(container);
    return container?.let((it) => '$it.$name') ?? name;
  }

  /// [candidates] and [refsByCandidate], with each candidate's references
  /// extended by those of its namesakes. References inside a namesake itself
  /// are not added.
  ///
  /// Candidates left out by [_dropped] go to [onDropped]. [declared]
  /// holds the [pairingNames] of each variant that was read.
  ({List<Candidate> candidates, List<List<Location>> refsByCandidate}) share(
    List<Candidate> candidates,
    List<List<Location>> refsByCandidate,
    Map<String, Set<String>> declared,
    ReferenceClassifier classifier, {
    required void Function(Candidate) onDropped,
  }) {
    final names = candidates.map(_pairingNameOf).toList();
    final namesakes = _namesakes(candidates, names);
    final dropped = _dropped(candidates, names, namesakes, declared);
    final kept = <Candidate>[];
    final keptRefs = <List<Location>>[];
    for (final (i, candidate) in candidates.indexed) {
      if (dropped.contains(i)) {
        onDropped(candidate);
        continue;
      }
      kept.add(candidate);
      keptRefs.add([
        ...refsByCandidate[i],
        for (final j in namesakes[i])
          ...classifier.externalRefs(candidates[j], refsByCandidate[j]),
      ]);
    }
    return (candidates: kept, refsByCandidate: keptRefs);
  }

  /// The indices of each candidate's namesakes: the [candidates] with the same
  /// pairing name in one of its [counterpartFilesOf].
  List<List<int>> _namesakes(List<Candidate> candidates, List<String?> names) {
    final byName = <String, List<int>>{};
    for (final (i, name) in names.indexed) {
      if (name != null) {
        byName.putIfAbsent(name, () => []).add(i);
      }
    }
    return [
      for (final (i, candidate) in candidates.indexed)
        [
          if (byName[names[i]] case final sameName?)
            for (final j in sameName)
              if (counterpartFilesOf(
                candidate.path,
              ).contains(candidates[j].path))
                j,
        ],
    ];
  }

  /// The indices of the [candidates] with a namesake that is not a candidate,
  /// or in a file that was not read, and of their namesakes in turn.
  Set<int> _dropped(
    List<Candidate> candidates,
    List<String?> names,
    List<List<int>> namesakes,
    Map<String, Set<String>> declared,
  ) {
    bool lacksNamesake(int i, String name, String file) =>
        declared[file]?.let(
          (inFile) =>
              inFile.contains(name) &&
              !namesakes[i].any((j) => candidates[j].path == file),
        ) ??
        true;

    return reachableFrom([
      for (final (i, candidate) in candidates.indexed)
        if (names[i] case final name?)
          if (counterpartFilesOf(
            candidate.path,
          ).any((file) => lacksNamesake(i, name, file)))
            i,
    ], (i) => namesakes[i]);
  }

  String? _pairingNameOf(Candidate candidate) => contains(candidate.path)
      ? pairingName(candidate.symbol, candidate.container)
      : null;
}

/// The directives of the Dart files under a root, each file parsed once. Paths
/// are absolute and normalized.
final class _DirectiveIndex {
  _DirectiveIndex(String root) : _files = scanPackageTree(root).dartFiles;

  final Set<String> _files;
  final _packages = PackageResolver();
  final _directives = CachedMap<String, List<Directive>>(
    (path) => [...Directive.allIn(readSource(path) ?? '')],
  );

  /// The [libraryFiles] of each variant, for every conditional directive.
  Iterable<List<Set<String>>> conditionalVariants() sync* {
    for (final path in _files) {
      // Only a file that may hold one is parsed: stripping comments is slow.
      final content = readSource(path);
      if (content == null || !_maybeConditional.hasMatch(content)) {
        continue;
      }
      for (final directive in _directives[path]) {
        if (directive.isConditional) {
          yield directive.pathsFrom(path, _packages).map(libraryFiles).toList();
        }
      }
    }
  }

  /// The files whose declarations importing [library] gives: [library], its
  /// parts and the files it exports, through further exports. Files outside
  /// the root are left out.
  Set<String> libraryFiles(String library) => reachableFrom(
    [library],
    (path) => [
      for (final directive in _directives[path])
        if (directive.keyword != 'import' && !directive.isPartOf)
          ...directive.pathsFrom(path, _packages).where(_files.contains),
    ],
  );
}

/// What may start a conditional `import` or `export`.
final _maybeConditional = RegExp(
  r'^[ \t]*(?:import|export)\b[^;]*\bif\s*\(',
  multiLine: true,
);
