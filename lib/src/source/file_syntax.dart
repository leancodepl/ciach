/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

import 'package:ciach/src/source/locations.dart';

/// A `with` or `implements` clause.
///
/// `range` covers the clause, keyword included, and `entries` the type of
/// each entry, in source order: `B` and `C<int>` for `implements B, C<int>`.
/// `whole` is what `--remove` deletes when every entry goes: the clause and
/// the whitespace before it, so that `class A with M {}` becomes
/// `class A {}`. When a `//` comment ends the line before the clause, `whole`
/// starts on the clause's own line instead, so that the code after the clause
/// doesn't end up inside the comment. `keepsOne` is true for the `with`
/// clause of a mixin application class, like `class A = B with M;`, which
/// must keep at least one mixin.
typedef Clause = ({
  Range range,
  List<Range> entries,
  Range whole,
  bool keepsOne,
});

/// A statement that declares fields or top-level variables.
///
/// `range` covers the statement, with its doc comment, annotations and `;`,
/// and `declarators` each variable, in source order: `a = 1` and `b = 2` for
/// `int a = 1, b = 2;`.
typedef VariableStatement = ({Range range, List<Range> declarators});

/// Answers about the code at a position in the files that a run reads.
abstract interface class FileSyntax {
  /// Whether the reference at [location] is in a doc comment, like `Foo` in
  /// `/// See [Foo].`
  bool isDocReference(Location location);

  /// Whether the reference at [location] is the type of the pattern of a
  /// `case`, an if-case or a switch-expression arm, like `Circle` in
  /// `case Circle():` and in `Circle c => …`. A pattern nested in another
  /// one, or in a pattern variable declaration, is not.
  bool isTypePattern(Location location);

  /// Whether the reference at [location] is an enum that `.values` follows,
  /// like `Color` in `Color.values` and in `prefix.Color.values`.
  bool isEnumValuesAccess(Location location);

  /// Whether the reference at [location] is the only type argument of
  /// `State` in an `extends` clause, like `Foo` in
  /// `class _FooState extends State<Foo>`.
  bool isStateTypeArgument(Location location);

  /// Returns the `with` or `implements` clause in which the reference at
  /// [location], to a type named [name], is an entry, with the range of that
  /// entry: `M` in `class A with M {}` or `M<int>` in
  /// `class A with M<int> {}`. Returns `null` for any other reference, such
  /// as a type annotation, an `extends` or `on` clause, `prefix.M`, or a type
  /// argument like the `M` in `implements List<M>`.
  ({Clause clause, Range entry})? clauseAt(Location location, String name);

  /// Returns the statement that declares the field or top-level variable
  /// whose name starts at [name] in the file at [path], with the range of
  /// that variable, or `null` when no variable's name starts there.
  ({VariableStatement statement, Range declarator})? declaratorAt(
    String path,
    int name,
  );

  /// Whether [offset] in the file at [path] is in the body of the function,
  /// method or constructor whose code is [declaration].
  bool isInBody(String path, int offset, Range declaration);
}
