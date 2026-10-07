import 'dart:io';

import 'package:ciach/src/candidates.dart';
import 'package:ciach/src/lsp/lsp_client.dart';
import 'package:ciach/src/lsp/outline.dart';
import 'package:ciach/src/public_api.dart';
import 'package:ciach/src/reachability.dart';
import 'package:ciach/src/reference_fetch.dart';
import 'package:ciach/src/reference_kinds.dart';
import 'package:ciach/src/source_index.dart';
import 'package:ciach/src/symbols.dart';
import 'package:pro_lsp/pro_lsp.dart' show Location, Position;

/// Unexported types another package may still hold an instance of.
///
/// A type is reachable when it is named outside a function body in an
/// importable file: in a signature, a field initializer, a supertype or a
/// typedef. A mention inside another type counts only if that type is
/// reachable too. An omitted return type is `dynamic`, so a body never hands
/// a type out.
final class ReachableTypes {
  ReachableTypes._(this._filesOf);

  static Future<ReachableTypes> find({
    required LspClient client,
    required SourceIndex sources,
    required ReferenceFetch fetch,
    required PublicApi api,
    required List<Candidate> candidates,
    required List<List<Location>> refs,
  }) async {
    final types = <DeclKey, _Type>{
      for (final (i, candidate) in candidates.indexed)
        if (_isType(candidate))
          candidate.key: (candidate: candidate, refs: refs[i]),
    };
    final positionsIn = _importableRefs(types.values, sources, api);
    final outlines = await _outlines(client, positionsIn.keys);
    await fetch.fetchSelectionRanges(client, positionsIn);

    final carriersOf = _Carriers(client, sources, api, outlines);
    final reachable = <DeclKey>{};
    final carriedBy = <DeclKey, Set<DeclKey>>{};
    await Future.wait(
      types.entries.map((entry) async {
        final MapEntry(:key, value: type) = entry;
        final carriers = await carriersOf(type);
        // A carrier that is not a type here, such as [_root], hands it out.
        if (api.exposes(key.path, key.name) ||
            carriers.any((carrier) => !types.containsKey(carrier))) {
          reachable.add(key);
        }
        carriedBy[key] = carriers.where(types.containsKey).toSet();
      }),
    );
    return ._({
      for (final key in _unreached(types.keys, reachable, carriedBy))
        key: {
          key.path,
          for (final loc in types[key]!.refs) SourceIndex.pathOf(loc.uri),
        },
    });
  }

  /// The positions of [types]' references in scanned, importable files.
  static Map<String, Set<Position>> _importableRefs(
    Iterable<_Type> types,
    SourceIndex sources,
    PublicApi api,
  ) {
    final positionsIn = <String, Set<Position>>{};
    for (final type in types) {
      for (final loc in type.refs) {
        final path = SourceIndex.pathOf(loc.uri);
        if (sources.scannedPaths.contains(path) && api.isImportable(path)) {
          (positionsIn[path] ??= {}).add(loc.range.start);
        }
      }
    }
    return positionsIn;
  }

  static Future<Map<String, Outline>> _outlines(
    LspClient client,
    Iterable<String> paths,
  ) async {
    final outlines = <String, Outline>{};
    await Future.wait(
      paths.map((path) async {
        try {
          outlines[path] = await client.outline(File(path).uri);
        } on LspRequestException {
          // A file without an outline hands out every type it names.
        }
      }),
    );
    return outlines;
  }

  /// The types neither [reachable] nor carried by a reachable type.
  static Iterable<DeclKey> _unreached(
    Iterable<DeclKey> types,
    Set<DeclKey> reachable,
    Map<DeclKey, Set<DeclKey>> carriersOf,
  ) {
    final keys = types.toList();
    final indexOf = {for (final (i, key) in keys.indexed) key: i};
    return unreached(
      {for (var i = 0; i < keys.length; i++) i},
      [
        for (final key in reachable)
          (target: indexOf[key]!, containers: const []),
        for (final MapEntry(:key, value: carriers) in carriersOf.entries)
          for (final carrier in carriers)
            (target: indexOf[key]!, containers: [indexOf[carrier]!]),
      ],
    ).map((i) => keys[i]);
  }

  /// For each internal type, the files naming it, where its members are most
  /// likely used.
  final Map<DeclKey, Set<String>> _filesOf;

  /// Whether no other package can hold an instance of [member]'s type.
  bool isInternal(Candidate member) =>
      _filesOf.containsKey(member.containerKey);

  /// The files where [member] of an internal type is most likely used.
  Set<String> filesFor(Candidate member) => _filesOf[member.containerKey]!;

  /// Whether [member] is reachable only if its type is. Members of
  /// extensions are reached only by importing them.
  static bool isGated(Candidate member) =>
      member.container != null &&
      member.containerOutline?.element.kind != .extension &&
      !isPrivateName(member.symbol.name);

  static bool _isType(Candidate candidate) =>
      candidate.container == null &&
      typeLikeKinds.contains(candidate.symbol.kind) &&
      !candidate.isExtension;
}

/// A carrier no type matches, so whatever it carries is reachable.
const _root = DeclKey('', '');

typedef _Type = ({Candidate candidate, List<Location> refs});

/// What hands a type out, read from the outlines of the files naming it.
final class _Carriers {
  _Carriers(this._client, this._sources, this._api, this._outlines);

  final LspClient _client;
  final SourceIndex _sources;
  final PublicApi _api;
  final Map<String, Outline> _outlines;
  final _signatures = <(String, Position), Future<String?>>{};

  /// The types holding a reference to [type], and [_root] for a reference
  /// that hands it to everyone.
  Future<Set<DeclKey>> call(_Type type) async => {
    for (final loc in type.refs)
      if (_canHandOut(type, loc))
        ?await _carrierAt(SourceIndex.pathOf(loc.uri), loc.range.start),
  };

  /// Whether [loc] can hand [type] to another package: in an importable
  /// file, outside [type] itself, not a doc comment.
  bool _canHandOut(_Type type, Location loc) {
    final path = SourceIndex.pathOf(loc.uri);
    return _api.isImportable(path) &&
        !(path == type.candidate.path &&
            type.candidate.outline.range.contains(loc.range.start)) &&
        !_sources.isDocReference(loc);
  }

  /// The type the reference at [pos] hands its type to, [_root] when it
  /// hands it to everyone, or `null` when it sits in a body, a directive or
  /// an extension no other package can import.
  Future<DeclKey?> _carrierAt(String path, Position pos) async {
    final unit = _outlines[path];
    if (unit == null) {
      return _root;
    }
    final top = unit.childAt(pos);
    if (top == null) {
      return null;
    }
    final kind = top.element.kind;
    if (kind case .class$ || .mixin || .enum$ || .extension || .extensionType) {
      final member = top.childAt(pos);
      if (member != null && await _hidesIn(member, top, path, pos)) {
        return null;
      }
      if (kind != .extension) {
        return DeclKey(path, top.element.name);
      }
      return !top.element.isUnnamedExtension &&
              _api.exposes(path, top.element.name)
          ? _root
          : null;
    }
    return await _hidesIn(top, null, path, pos) ? null : _root;
  }

  /// Whether a mention at [pos] in the function-like [node] stays inside it:
  /// it sits in the body, and nothing the signature hands out is `dynamic`.
  Future<bool> _hidesIn(
    Outline node,
    Outline? owner,
    String path,
    Position pos,
  ) async {
    final element = node.element;
    if (element.kind
        case .field ||
            .topLevelVariable ||
            .enumConstant ||
            .typeAlias ||
            .functionTypeAlias) {
      return false;
    }
    if (_bodyStart(node, path, pos) == null ||
        (element.typeParameters ?? '').isNotEmpty ||
        (owner?.element.typeParameters ?? '').isNotEmpty) {
      return false;
    }
    final signature = await _signature(path, node);
    return signature != null && !_dynamic.hasMatch(signature);
  }

  /// Where the body of [node] that holds [pos] starts: the syntax node that
  /// ends the declaration and opens with `{`, `=>`, `async` or `sync`.
  int? _bodyStart(Outline node, String path, Position pos) {
    final code = _sources.code(path);
    for (
      var range = _sources.selectionRangeAt(path, pos);
      range != null && node.codeRange.contains(range.range.start);
      range = range.parent
    ) {
      final start = _sources.offsetOf(path, range.range.start);
      if (start != null &&
          range.range.end == node.codeRange.end &&
          range.range.start != node.codeRange.start &&
          _bodyOpener.matchAsPrefix(code, start) != null) {
        return start;
      }
    }
    return null;
  }

  /// [node]'s signature as the analyzer resolved it, e.g.
  /// `void f(dynamic cb)` for `void f(cb)`, from its hover.
  Future<String?> _signature(String path, Outline node) {
    final at = node.element.range?.start ?? node.codeRange.start;
    return _signatures[(path, at)] ??= () async {
      try {
        final hover = await _client.hover(File(path).uri, at);
        return hover == null ? null : _fencedCode.firstMatch(hover)?.group(1);
      } on LspRequestException {
        return null;
      }
    }();
  }
}

/// Types through which a caller can invoke any member: `dynamic`, and a
/// bare `Function`.
final _dynamic = RegExp(r'\bdynamic\b|\bFunction\b(?!\s*[(<])');

final _bodyOpener = RegExp(r'\{|=>|async\b|sync\b');

/// The first fenced code block of a hover: the signature.
final _fencedCode = RegExp(r'```dart\n([^`]*?)\n```');
