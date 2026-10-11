import 'dart:io';

import 'package:ciach/src/candidates.dart';
import 'package:ciach/src/comment_stripping.dart';
import 'package:ciach/src/packages.dart';
import 'package:ciach/src/reference_classifier.dart';
import 'package:ciach/src/symbols.dart';
import 'package:collection/collection.dart';
import 'package:pro_lsp/pro_lsp.dart' show DocumentSymbol, Location;

/// The files that conditional imports and exports choose between, such as
/// `io.dart` and `web.dart` in
/// `import 'io.dart' if (dart.library.js_interop) 'web.dart';`.
///
/// The analysis server resolves every use to the default file, so a
/// declaration in another variant has no references even when another platform
/// uses it. Declarations with the same name in the variants of one directive
/// are therefore checked together: they share their references, so they are
/// either all used or all unused, and `--remove` deletes them together.
final class ConditionalImports {
  ConditionalImports._(this._groupOf);

  /// Reads the conditional imports and exports in every Dart file under
  /// [rootPath].
  factory ConditionalImports.scan(String rootPath) {
    final packages = PackageResolver();
    final groups = _Groups();
    for (final path in scanPackageTree(rootPath).dartFiles) {
      _directivesIn(path, packages).forEach(groups.join);
    }
    return ._(groups.groupOf());
  }

  static final empty = ConditionalImports._(const {});

  /// The files of each directive's variants, by the group they belong to. A
  /// file that two directives name joins their groups.
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

  /// Returns the name that pairs a public declaration with its counterparts in
  /// the other variants: `Type.member`, or the top-level name. Returns `null`
  /// for a private declaration, or for a member of a private type, because no
  /// other library can use it.
  static String? pairingName(DocumentSymbol symbol, String? container) {
    if (isPrivateName(symbol.name) ||
        (container != null && isPrivateName(container))) {
      return null;
    }
    final name = symbol.declarationName(container);
    return container == null ? name : '$container.$name';
  }

  /// Returns the candidates that cannot be checked, because a counterpart of
  /// theirs is declared but is not checked itself, or because the file of a
  /// counterpart was not read. [declared] holds the pairing names declared in
  /// each variant file that was read.
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

  /// Returns [refsByCandidate] with the references of each candidate's
  /// counterparts added to its own. A counterpart's references inside its own
  /// declaration are left out, because they do not use the name.
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

/// The variants that each conditional import or export in [path] chooses
/// between: its default file first, then the file of each `if` clause.
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

/// The default URI of a conditional [directive], then the URI after each of
/// its `if (…)` clauses. A string compared in a condition is not a URI.
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

/// Files joined into groups, so that every file of a directive, and every
/// directive that shares a file with it, ends up in one group.
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

  /// Every file in a group with another file, mapped to the group's number.
  Map<String, int> groupOf() {
    final byRoot = groupBy(_parent.keys, _root);
    return {
      for (final (i, files) in byRoot.values.indexed)
        if (files.length > 1)
          for (final file in files) file: i,
    };
  }
}
