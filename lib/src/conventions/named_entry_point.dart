/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

part of 'entry_points.dart';

/// A rule that selects a declaration by its name.
final class NamedEntryPoint extends EntryPoint {
  NamedEntryPoint({
    required this.name,
    required this.reason,
    super.files = const [],
  }) : super._();

  @override
  final String reason;

  /// The name of the declaration. A top-level declaration is `name` and a
  /// member is `Container.member`. The unnamed constructor is `Class.new`.
  /// Type parameters are not part of the name.
  final String name;

  /// A rule that names a class or an extension type also selects the type's
  /// unnamed constructor, because code that uses the type calls `Type()`.
  /// Only an enum's own values call its constructor, so the rule does not
  /// select it in an enum.
  @override
  bool _selects(ResolvedDeclaration declaration) {
    final ResolvedDeclaration(:symbol, :container) = declaration;
    return declaration.qualifiedName == name ||
        (container == name &&
            !declaration.inEnum &&
            symbol.kind == .constructor &&
            symbol.declarationName(container) == 'new');
  }

  @override
  String reasonFor(ResolvedDeclaration declaration) =>
      declaration.container == name
      ? 'the unnamed constructor of the entry point $name'
      : reason;

  @override
  String containerReason(String qualified) => 'declares the entry point $name';

  @override
  NamedEntryPoint _withFiles(List<String> files) =>
      .new(name: name, reason: reason, files: files);

  @override
  String get label => name;
}
