import 'dart:io';

import 'package:ciach/src/candidates.dart';
import 'package:ciach/src/comment_stripping.dart';
import 'package:ciach/src/packages.dart';
import 'package:ciach/src/reference_classifier.dart';
import 'package:ciach/src/symbols.dart';
import 'package:collection/collection.dart';
import 'package:pro_lsp/pro_lsp.dart' show DocumentSymbol, Location;

/// The files a conditional `import` or `export` chooses between, such as
/// `io.dart` and `web.dart` in
/// `import 'io.dart' if (dart.library.js_interop) 'web.dart';`.
///
/// The analysis server resolves every use to the default file, so namesakes in
/// the variants share their references: they are used, or reported and
/// removed, together.
final class ConditionalImports {
  ConditionalImports._(this._groupOf);

  /// Reads the conditional directives in every Dart file under [rootPath].
  factory ConditionalImports.scan(String rootPath) {
    final packages = PackageResolver();
    final groups = _Groups();
    for (final path in scanPackageTree(rootPath).dartFiles) {
      _directivesIn(path, packages).forEach(groups.join);
    }
    return ._(groups.groupOf());
  }

  static final empty = ConditionalImports._(const {});

  /// The group of each variant. Directives that name the same file share a
  /// group.
  final Map<String, int> _groupOf;

  /// Whether [path] is one of the variants of a conditional directive.
  bool contains(String path) => _groupOf.containsKey(path);

  /// The other variants of the directives that name [path].
  Iterable<String> counterpartFilesOf(String path) => switch (_groupOf[path]) {
    final group? => [
      for (final MapEntry(key: file, value: other) in _groupOf.entries)
        if (other == group && file != path) file,
    ],
    null => const [],
  };

  /// The name that pairs [symbol] with its namesakes: `Type.member`, or the
  /// top-level name. `null` when [symbol] or its type is private, since no
  /// other library can use it.
  static String? pairingName(DocumentSymbol symbol, String? container) {
    if (isPrivateName(symbol.name) ||
        (container != null && isPrivateName(container))) {
      return null;
    }
    final name = symbol.declarationName(container);
    return container == null ? name : '$container.$name';
  }

  /// The [candidates] whose namesake is declared but not checked, or whose
  /// other variant was not read. [declared] holds the pairing names in each
  /// variant that was read.
  Set<Candidate> uncheckable(
    List<Candidate> candidates,
    Map<String, Set<String>> declared,
  ) {
    final checked = {
      for (final candidate in candidates)
        if (_pairingNameOf(candidate) case final name?) (candidate.path, name),
    };
    return {
      for (final candidate in candidates)
        if (_pairingNameOf(candidate) case final name?)
          if (counterpartFilesOf(candidate.path).any(
            (file) => switch (declared[file]) {
              null => true,
              final names =>
                names.contains(name) && !checked.contains((file, name)),
            },
          ))
            candidate,
    };
  }

  /// [refsByCandidate] with the references of each candidate's namesakes
  /// added, less the ones inside the namesake itself.
  List<List<Location>> sharedReferences(
    List<Candidate> candidates,
    List<List<Location>> refsByCandidate,
    ReferenceClassifier classifier,
  ) {
    final byPairing = <(int, String), List<int>>{};
    for (final (i, candidate) in candidates.indexed) {
      if ((_groupOf[candidate.path], _pairingNameOf(candidate)) case (
        final group?,
        final name?,
      )) {
        byPairing.putIfAbsent((group, name), () => []).add(i);
      }
    }
    final shared = [...refsByCandidate];
    for (final indices in byPairing.values.where((list) => list.length > 1)) {
      for (final i in indices) {
        shared[i] = [
          ...refsByCandidate[i],
          for (final j in indices)
            if (j != i)
              ...classifier.externalRefs(candidates[j], refsByCandidate[j]),
        ];
      }
    }
    return shared;
  }

  String? _pairingNameOf(Candidate candidate) => contains(candidate.path)
      ? pairingName(candidate.symbol, candidate.container)
      : null;
}

/// The files that each conditional directive in [path] names, the default one
/// first.
Iterable<List<String>> _directivesIn(String path, PackageResolver packages) {
  final String content;
  try {
    content = File(path).readAsStringSync();
  } on FileSystemException {
    return const [];
  }
  return [
    for (final directive in _conditionalDirective.allMatches(
      stripComments(content),
    ))
      [
        for (final uri in _uris(directive[0]!))
          if (packages.resolve(uri, path) case final resolved?
              when resolved != unknownPackage)
            resolved,
      ],
  ];
}

/// The URIs in [directive], less the strings compared in its conditions.
Iterable<String> _uris(String directive) sync* {
  final conditions = _condition.allMatches(directive).toList();
  for (final uri in uriLiteral.allMatches(directive)) {
    if (!conditions.any((c) => c.start <= uri.start && uri.end <= c.end)) {
      yield uri.namedGroup('uri')!;
    }
  }
}

/// An `import` or `export` directive that has at least one `if (…)` clause.
final _conditionalDirective = RegExp(
  r'^[ \t]*(?:import|export)\b[^;]*\bif\s*\([^;]*;',
  multiLine: true,
);

/// The parenthesized condition of an `if` clause.
final _condition = RegExp(r'\bif\s*\([^)]*\)');

/// A union-find of files: each directive joins the files it names.
final class _Groups {
  final _parent = <String, String>{};

  void join(List<String> files) {
    for (final file in files) {
      _parent.putIfAbsent(file, () => file);
    }
    for (final file in files.skip(1)) {
      _parent[_root(file)] = _root(files.first);
    }
  }

  String _root(String file) {
    var root = file;
    while (_parent[root] != root) {
      root = _parent[root]!;
    }
    return root;
  }

  /// The group number of every file that shares a group with another.
  Map<String, int> groupOf() {
    final byRoot = groupBy(_parent.keys, _root);
    return {
      for (final (i, files) in byRoot.values.indexed)
        if (files.length > 1)
          for (final file in files) file: i,
    };
  }
}
