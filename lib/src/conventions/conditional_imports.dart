import 'package:ciach/src/candidates.dart';
import 'package:ciach/src/directives.dart';
import 'package:ciach/src/packages.dart';
import 'package:ciach/src/reference_classifier.dart';
import 'package:ciach/src/symbols.dart';
import 'package:collection/collection.dart';
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
  ///
  /// Each variant's files get the files of the directive's other variants as
  /// counterparts. For
  /// `import 'stub.dart' if (dart.library.io) 'io.dart' if (dart.library.js_interop) 'web.dart';`
  /// the files of `io.dart` get those of `stub.dart` and `web.dart`, and so
  /// on. A file that several directives name collects the counterparts of each.
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
    for (final symbol in symbols) ..._pairingNames(symbol, null),
  };

  static Iterable<String> _pairingNames(
    DocumentSymbol symbol,
    String? container,
  ) sync* {
    if (pairingName(symbol, container) case final name?) {
      yield name;
      if (container == null && typeLikeKinds.contains(symbol.kind)) {
        for (final child in symbol.children ?? const <DocumentSymbol>[]) {
          yield* _pairingNames(child, symbol.name);
        }
      }
    }
  }

  /// The name that pairs [symbol] with its namesakes; see [pairingNames].
  static String? pairingName(DocumentSymbol symbol, String? container) {
    final type = container ?? symbol.name;
    if (isPrivateName(symbol.name) ||
        isPrivateName(type) ||
        type.startsWith('extension on ')) {
      return null;
    }
    final name = symbol.declarationName(container);
    return container == null ? name : '$container.$name';
  }

  /// [candidates] and [refsByCandidate] with the references of each
  /// candidate's namesakes added, less the ones inside the namesake itself.
  ///
  /// A candidate is dropped when a namesake is declared but not checked, or
  /// when another variant was not read; [onDropped] hears of it. [declared]
  /// holds the [pairingNames] of each variant that was read.
  ({List<Candidate> candidates, List<List<Location>> refsByCandidate}) share(
    List<Candidate> candidates,
    List<List<Location>> refsByCandidate,
    Map<String, Set<String>> declared,
    ReferenceClassifier classifier, {
    required void Function(Candidate) onDropped,
  }) {
    final names = candidates.map(_pairingNameOf).toList();
    final kept = _checkable(candidates, names, declared);
    for (final (i, candidate) in candidates.indexed) {
      if (!kept.contains(i)) {
        onDropped(candidate);
      }
    }
    final byName = groupBy(
      kept.where((i) => names[i] != null),
      (i) => names[i]!,
    );
    return (
      candidates: [for (final i in kept) candidates[i]],
      refsByCandidate: [
        for (final i in kept)
          [
            ...refsByCandidate[i],
            for (final j in byName[names[i]] ?? const <int>[])
              if (counterpartFilesOf(
                candidates[i].path,
              ).contains(candidates[j].path))
                ...classifier.externalRefs(candidates[j], refsByCandidate[j]),
          ],
      ],
    );
  }

  /// The indices of the [candidates] whose namesakes are all checked, in
  /// order. A dropped candidate can leave its own namesakes unchecked, so this
  /// runs until nothing more drops.
  Set<int> _checkable(
    List<Candidate> candidates,
    List<String?> names,
    Map<String, Set<String>> declared,
  ) {
    final kept = {for (final (i, _) in candidates.indexed) i};
    while (true) {
      final checked = {
        for (final i in kept)
          if (names[i] case final name?) (candidates[i].path, name),
      };
      final dropped = kept.where((i) {
        final name = names[i];
        return name != null &&
            counterpartFilesOf(candidates[i].path).any(
              (file) => switch (declared[file]) {
                null => true,
                final inFile =>
                  inFile.contains(name) && !checked.contains((file, name)),
              },
            );
      }).toSet();
      if (dropped.isEmpty) {
        return kept;
      }
      kept.removeAll(dropped);
    }
  }

  String? _pairingNameOf(Candidate candidate) => contains(candidate.path)
      ? pairingName(candidate.symbol, candidate.container)
      : null;
}

/// The directives of the Dart files under a root, each file read once.
///
/// Every path is absolute and normalized, as [scanPackageTree] and
/// [Directive.pathsFrom] give them.
final class _DirectiveIndex {
  _DirectiveIndex(String root) : _files = scanPackageTree(root).dartFiles;

  final Set<String> _files;
  final _packages = PackageResolver();
  final _directives = <String, List<Directive>>{};

  /// The variants of each conditional directive, as their [libraryFiles]:
  /// `[libraryFiles('io.dart'), libraryFiles('web.dart')]` for the directive
  /// in [ConditionalImports].
  Iterable<List<Set<String>>> conditionalVariants() sync* {
    for (final path in _files) {
      // Only a file that may hold one is parsed: stripping comments is slow.
      final content = readSource(path);
      if (content == null || !_maybeConditional.hasMatch(content)) {
        continue;
      }
      for (final directive in _directivesOf(path, content)) {
        if (directive.isConditional) {
          yield directive.pathsFrom(path, _packages).map(libraryFiles).toList();
        }
      }
    }
  }

  /// The files whose declarations importing [library] gives: [library], its
  /// parts and the files it exports, through further exports. Files outside
  /// the root are left out.
  Set<String> libraryFiles(String library) {
    final files = <String>{};
    final pending = [library];
    while (pending.isNotEmpty) {
      final path = pending.removeLast();
      if (!files.add(path)) {
        continue;
      }
      for (final directive in _directivesOf(path)) {
        if (directive.keyword != 'import' && !directive.isPartOf) {
          pending.addAll(
            directive.pathsFrom(path, _packages).where(_files.contains),
          );
        }
      }
    }
    return files;
  }

  List<Directive> _directivesOf(String path, [String? content]) =>
      _directives.putIfAbsent(
        path,
        () => [...Directive.allIn(content ?? readSource(path) ?? '')],
      );
}

/// What may start a conditional `import` or `export`.
final _maybeConditional = RegExp(
  r'^[ \t]*(?:import|export)\b[^;]*\bif\s*\(',
  multiLine: true,
);
