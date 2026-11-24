/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

part of 'entry_points.dart';

/// A rule that selects what Pigeon reads from its input files, with every
/// member: the classes and enums, the top-level constants, and the
/// declaration that `@ConfigurePigeon` annotates.
///
/// Pigeon reads a class without `abstract` as a data class, and an abstract
/// class only with an API annotation. It skips the other declarations, such
/// as functions, mixins and typedefs, without an error, so the rule leaves
/// them to the search.
final class PigeonInputEntryPoint extends EntryPoint {
  /// [files] match the input files.
  PigeonInputEntryPoint({required super.files}) : super._();

  /// The annotations that make an abstract class a Pigeon API.
  ///
  /// Pigeon matches them by the name after the `@` without resolving it, so
  /// the rule does too.
  static const _apiAnnotations = [
    'HostApi',
    'FlutterApi',
    'EventChannelApi',
    'ProxyApi',
  ];

  static const _reason = 'read by Pigeon from its input file';

  @override
  String get reason => _reason;

  @override
  KeptMembers get members => const .new(.allMembers, _reason);

  @override
  bool _selects(ResolvedDeclaration declaration) =>
      declaration.container == null &&
      (_isAnnotatedWith(declaration, 'ConfigurePigeon') ||
          switch (declaration.outlineKind) {
            .class$ =>
              !declaration.keywords.contains('abstract') ||
                  _apiAnnotations.any(
                    (annotation) => _isAnnotatedWith(declaration, annotation),
                  ),
            .enum$ => true,
            .topLevelVariable => declaration.keywords.contains('const'),
            _ => false,
          });

  static bool _isAnnotatedWith(
    ResolvedDeclaration declaration,
    String annotation,
  ) => declaration.leadingMetadata.any(
    (token) => token.isAnnotationNamed(annotation),
  );

  @override
  PigeonInputEntryPoint _withFiles(List<String> files) => .new(files: files);

  @override
  String get label => 'declarations that Pigeon reads';
}
