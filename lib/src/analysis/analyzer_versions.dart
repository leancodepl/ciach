/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

/// Reads the members of the analyzer API that the supported analyzer
/// versions spell differently.
///
/// Every dynamic call in ciach is in this file. Each one reads a member that
/// some supported versions have and others replace with a member of another
/// name for the same thing. Which of the two this analyzer has is found out
/// once, by reading the newer one, since a process loads one analyzer
/// version, and the result is cast to its static type right away.
library;

import 'package:analyzer/dart/ast/ast.dart';

/// Returns the part of the extension type [node] that holds its name, its
/// type parameters and its primary constructor.
///
/// Analyzer 14.0.0 added `ExtensionTypeDeclaration.namePart` and deprecated
/// `primaryConstructor`, which analyzer 10.x to 13.x have instead. Both
/// return the same node.
// TODO: Read `namePart` directly once the analyzer floor is 14.0.0.
ClassNamePart extensionTypeNamePart(ExtensionTypeDeclaration node) =>
    (_hasNamePart ??= _readsNamePart(node))
    // Dynamic, since `namePart` doesn't exist before analyzer 14.0.0.
    ? (node as dynamic).namePart as ClassNamePart
    // Dynamic, since `primaryConstructor` is deprecated from 14.0.0 on.
    : (node as dynamic).primaryConstructor as ClassNamePart;

bool? _hasNamePart;

/// Whether [node] has `namePart`, which analyzer 14.0.0 added.
bool _readsNamePart(ExtensionTypeDeclaration node) {
  try {
    return switch ((node as dynamic).namePart) {
      ClassNamePart() => true,
      _ => false,
    };
    // The error tells that the member is missing.
    // ignore: avoid_catching_errors
  } on NoSuchMethodError {
    return false;
  }
}
