/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

/// Reads what the analysis server writes in a hover.
library;

import 'package:ciach/src/util/extensions.dart';

/// Returns the package of the library that declares the element that [hover]
/// describes: `js` for `package:js/js.dart`, and the library itself for an
/// SDK library, such as `dart:core`. Returns `null` when [hover] names no
/// such library.
String? declaringPackageIn(String hover) => switch (_declaredIn
    .firstMatch(hover)
    ?.namedGroup('library')
    ?.let(Uri.tryParse)) {
  Uri(scheme: 'package', pathSegments: [final package, _, ...]) => package,
  Uri(scheme: 'dart') && final library => '$library',
  _ => null,
};

/// The line of a hover that names the library that declares the element,
/// such as "Declared in `pragma` in *dart:core*." for a constructor and
/// "Declared in *dart:core*." for a class. Dart 3.10 writes `_dart:core_`.
final _declaredIn = RegExp(
  r'^Declared in (?:`[^`]*` in )?[*_](?<library>\S+?)[*_]\.$',
  multiLine: true,
);
