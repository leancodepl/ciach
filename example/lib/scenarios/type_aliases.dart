/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

// Type aliases in every syntax, reported under the `typedef` kind. Each used
// alias is used in one form in type_aliases_uses.dart. Only
// test/finder/type_aliases_test.dart scans these files. Doc comments name
// declarations in backticks, since a `[link]` would count as a reference.

/// Named only by the dead `DeadAlias` -> UNUSED, transitively.
class OnlyAliased {}

/// Never named -> UNUSED.
typedef DeadAlias = OnlyAliased;

/// Never named -> UNUSED.
typedef DeadCallback = void Function(int value);

/// Never named, in the older function type alias syntax -> UNUSED.
// The older syntax is the case under test.
// ignore: prefer_generic_function_type_aliases
typedef int DeadCompare(int a, int b);

/// Never named, generic -> UNUSED.
typedef DeadPair<T> = (T, T);

/// Never named, private -> UNUSED.
typedef _DeadPrivate = int;

/// Reached only through the aliases below, which are all used.
class Point {
  Point();

  Point.named();

  static Point create() => Point();
}

/// Used as a type -> USED.
typedef AsType = List<int>;

/// Used as a parameter type -> USED.
typedef AsCallback = void Function(int value);

/// Used in the older syntax -> USED.
// The older syntax is the case under test.
// ignore: prefer_generic_function_type_aliases
typedef int AsCompare(int a, int b);

/// Used with a type argument -> USED.
typedef AsPair<T> = (T, T);

/// Constructed through -> USED.
typedef Constructed = Point;

/// Constructed through a named constructor -> USED.
typedef NamedConstructed = Point;

/// A static method called through it -> USED.
typedef StaticAccess = Point;

/// Named in an `is` test -> USED.
typedef IsTest = Point;

/// Named in an `is!` test -> USED.
typedef IsNotTest = Point;

/// Its constructor torn off with `.new` -> USED.
typedef TornOff = Point;

/// Applied only by the dead `DeadMixed` -> UNUSED, transitively.
mixin Trait {}

/// Never named. A mixin application class is a class, not a typedef ->
/// UNUSED.
class DeadMixed = Object with Trait;
