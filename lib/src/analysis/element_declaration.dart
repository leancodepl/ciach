/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

import 'package:analyzer/dart/element/element.dart';
import 'package:ciach/src/util/extensions.dart';

/// A declaration as every analysis context names it: the path of the file
/// that declares it, the offset of its first fragment, its kind, which tells
/// a field from its getter and setter, and its name, which tells apart the
/// fields that one primary constructor declares, since their fragments share
/// an offset.
///
/// Each analysis context, one per package, builds elements of its own, so
/// the class `Foo` that another package imports is not the same object as
/// the class `Foo` that its own package declares.
final class ElementDeclaration {
  const ElementDeclaration._(this.path, this.offset, this.kind, this.name);

  /// Returns the declaration of [element], or `null` for an element that no
  /// file declares, such as `dynamic`.
  static ElementDeclaration? of(Element element) {
    final fragment = element.firstFragment;
    return fragment.libraryFragment?.source.fullName.let(
      (path) => ._(path, fragment.offset, element.kind, element.name),
    );
  }

  final String path;
  final int offset;
  final ElementKind kind;
  final String? name;

  @override
  bool operator ==(Object other) =>
      other is ElementDeclaration &&
      other.path == path &&
      other.offset == offset &&
      other.kind == kind &&
      other.name == name;

  @override
  int get hashCode => Object.hash(path, offset, kind, name);
}
