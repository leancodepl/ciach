/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

part of 'entry_points.dart';

/// A rule that selects a class by one of its supertypes, and keeps the class
/// and its public methods.
final class SubtypeEntryPoint extends EntryPoint {
  /// [reason] says who calls the public methods.
  SubtypeEntryPoint(
    this.supertype, {
    this.package,
    required String reason,
    super.files = const [],
  }) : members = .new(.publicMethods, reason),
       super._();

  /// The supertype.
  final String supertype;

  /// The package that declares [supertype], or `null` for any package.
  final String? package;

  @override
  final KeptMembers members;

  @override
  String get reason =>
      'has `$supertype` among its supertypes, so its public methods are entry points';

  @override
  Set<ServerLookup> get lookups => const {.supertypes};

  @override
  bool _selects(ResolvedDeclaration declaration) => declaration.supertypes.any(
    (type) => type.isNamed(supertype, package: package),
  );

  @override
  SubtypeEntryPoint _withFiles(List<String> files) =>
      .new(supertype, package: package, reason: members.reason, files: files);

  @override
  String get label => 'public methods of `$supertype` subclasses';
}
