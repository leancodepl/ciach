/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

part of 'entry_points.dart';

/// A rule that selects a class by the class that it extends, and keeps the
/// class and its public methods.
final class SubtypeEntryPoint extends EntryPoint {
  /// [reason] says who calls the public methods.
  SubtypeEntryPoint(
    this.supertype, {
    required String reason,
    super.files = const [],
  }) : members = .new(.publicMethods, reason),
       super._();

  /// The class that a selected class extends.
  final String supertype;

  @override
  final KeptMembers members;

  @override
  String get reason =>
      'extends `$supertype`, so its public methods are entry points';

  @override
  bool _selects(ResolvedDeclaration declaration) =>
      declaration.superclass == supertype;

  @override
  SubtypeEntryPoint _withFiles(List<String> files) =>
      .new(supertype, reason: members.reason, files: files);

  @override
  String get label => 'public methods of `$supertype` subclasses';
}
