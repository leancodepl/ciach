import 'package:ciach/src/analysis/resolved_files.dart';
import 'package:ciach/src/collect/candidates.dart';
import 'package:ciach/src/source/locations.dart';
import 'package:ciach/src/source/outline.dart';
import 'package:ciach/src/source/reference_kinds.dart';
import 'package:ciach/src/source/source_index.dart';
import 'package:ciach/src/source/symbols.dart';
import 'package:ciach/src/util/reachability.dart';
import 'package:ciach/src/workspace/public_api.dart';

/// Unexported types another package may still hold an instance of.
///
/// A type is reachable when it is named outside a function body in an
/// importable file: in a signature, a field initializer, a supertype or a
/// typedef. A mention inside another type counts only if that type is
/// reachable too. An omitted return type is `dynamic`, so a body never hands
/// a type out.
final class ReachableTypes {
  ReachableTypes._(this._internal);

  static Future<ReachableTypes> find({
    required ResolvedFiles files,
    required SourceIndex sources,
    required PublicApi api,
    required List<Candidate> candidates,
    required List<List<Location>> refs,
  }) async {
    final types = <DeclKey, _Type>{
      for (final (i, candidate) in candidates.indexed)
        if (candidate.isType)
          candidate.key: (candidate: candidate, refs: refs[i]),
    };
    final positionsIn = _importableRefs(types.values, sources, api);
    final outlines = await _outlines(files, positionsIn.keys);

    final carriersOf = _Carriers(files, sources, api, outlines);
    final reachable = <DeclKey>{};
    final carriedBy = <DeclKey, Set<DeclKey>>{};
    for (final MapEntry(:key, value: type) in types.entries) {
      final carriers = carriersOf(type);
      // A carrier that is not a type here, such as [_root], hands it out.
      if (api.exposes(key.path, key.name) ||
          !carriers.every(types.containsKey)) {
        reachable.add(key);
      }
      carriedBy[key] = carriers.where(types.containsKey).toSet();
    }
    return ._(_unreached(types.keys, reachable, carriedBy).toSet());
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

  /// The outlines of the files at [paths] that the analyzer resolves. A file
  /// without one hands out every type that it names.
  static Future<Map<String, Outline>> _outlines(
    ResolvedFiles files,
    Iterable<String> paths,
  ) async {
    final outlines = await Future.wait(
      paths.map((path) async => (path, (await files.of(path))?.outline)),
    );
    return {for (final (path, outline) in outlines) path: ?outline};
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

  /// The types that no other package can hold an instance of.
  final Set<DeclKey> _internal;

  /// Whether no other package can hold an instance of [member]'s type.
  bool isInternal(Candidate member) => _internal.contains(member.containerKey);

  /// Whether [member] is reachable only if its type is. Members of
  /// extensions are reached only by importing them.
  static bool isGated(Candidate member) =>
      member.container != null &&
      member.containerOutline?.element.kind != .extension &&
      !isPrivateName(member.symbol.name);
}

/// A carrier no type matches, so whatever it carries is reachable.
const _root = DeclKey('', '');

typedef _Type = ({Candidate candidate, List<Location> refs});

/// What hands a type out, read from the outlines of the files naming it.
final class _Carriers {
  _Carriers(this._files, this._sources, this._api, this._outlines);

  final ResolvedFiles _files;
  final SourceIndex _sources;
  final PublicApi _api;
  final Map<String, Outline> _outlines;

  /// The types holding a reference to [type], and [_root] for a reference
  /// that hands it to everyone.
  Set<DeclKey> call(_Type type) => {
    for (final loc in type.refs)
      if (_canHandOut(type, loc))
        ?_carrierAt(SourceIndex.pathOf(loc.uri), loc.range.start),
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
  DeclKey? _carrierAt(String path, Position pos) {
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
      if (member != null && _hidesIn(member, top, path, pos)) {
        return null;
      }
      if (kind != .extension) {
        return .new(path, top.element.name);
      }
      return !top.element.isUnnamedExtension &&
              _api.exposes(path, top.element.name)
          ? _root
          : null;
    }
    return _hidesIn(top, null, path, pos) ? null : _root;
  }

  /// Whether a mention at [pos] in the function-like [node] stays inside it:
  /// it sits in the body, and nothing the signature hands out is `dynamic`.
  bool _hidesIn(Outline node, Outline? owner, String path, Position pos) {
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
    return _files.hasDynamicSignature(
          path,
          element.range?.start ?? node.codeRange.start,
        ) ==
        false;
  }

  /// Where the body of [node] that holds [pos] starts: the syntax node that
  /// ends the declaration and opens with `{`, `=>`, `async` or `sync`.
  int? _bodyStart(Outline node, String path, Position pos) {
    final code = _sources.content(path);
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
}

final _bodyOpener = RegExp(r'\{|=>|async\b|sync\b');
