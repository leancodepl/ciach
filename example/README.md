# Example

This directory is a small, self-contained Dart package (`sample_pkg`) with a
deliberate mix of **used** and **unused** declarations, spread across several
files so the report's per-file grouping actually has something to group. It
doubles as the integration-test fixture, so it is a real, runnable
demonstration of the tool.

It comes in two tiers. The files directly under `lib/` are the **demo**: the
everyday declaration kinds, referenced (or not) from `bin/app.dart`.

| File | Declarations it demonstrates |
| --- | --- |
| `lib/greeting.dart` | top-level functions, constants, and a mutable variable |
| `lib/user.dart` | constructors, fields, methods, and a getter/setter pair |
| `lib/shapes.dart` | an enum, a mixin, and an abstract class with an `@override` |
| `lib/extensions.dart` | an extension method and operator overloading |
| `lib/orphans.dart` | classes never referenced at all, and one referenced only as a type |
| `lib/callables.dart` | a callable class whose `call` method is used only by invoking an instance |
| `lib/private_ctors.dart` | private constructors reported like any dead code, with a prevent-instantiation hint on the sole zero-parameter `Foo._()` |
| `test/flutter_test_config.dart` | the `flutter test` hook `testExecutable`, called by nothing on disk yet never reported |

`lib/scenarios/` holds the **scenario fixtures**: one file (or a small cluster
of them) per detection rule, each pinning down one behavior that is easy to
regress. Every file says up front what it covers and which findings are
expected; each is scanned only by its own test, never by the demo run above.

| Fixture | Rule it pins down |
| --- | --- |
| `widgets.dart` | the `StatefulWidget`/`State` pairing, so a dead widget is reported as a class and its `State` is removed with it |
| `unions.dart` | the opt-in `--also union-members` detection, across the three pattern-matching contexts |
| `guards.dart` | the remove-safety guards: findings that must be report-only because removing them would not compile |
| `enum_values.dart` | enum values reached only through `.values` iteration count as used |
| `freezed_unions.dart` | `@freezed` union arms built only by a generated `fromJson` |
| `serialization.dart` | the `toJson`/`fromJson` conventions, and `--also tojson` |
| `comment_annotations.dart` | a comment mentioning `@override` or `vm:entry-point` does not skip the declaration below it |
| `entry_points.dart`, `entry_points/flutter_test_config.dart` | an entry point is exempt by file and name, whatever its shape, and `entry-points` in `ciach.yaml` adds a project's own |
| `dot_shorthands.dart`, `dot_shorthand_uses.dart` | every context a `.name` dot shorthand is allowed in, including nested constructor shorthands |
| `primary_constructors.dart` | primary constructors: a dead declaration in the class header is report-only, while the class body stays removable |
| `extensions_emptied.dart`, `extensions_emptied_uses.dart` | an extension whose every member is dead is reported (and removed) as the whole extension, unless a `show` names it; an extension type is dead when nothing names it |
| `call_methods.dart`, `call_methods_uses.dart` | every form of use that keeps a `call` method alive: an invoked object, a tear-off and an explicit `.call` |
| `operators.dart`, `operators_uses.dart`, `operators_ring.dart` | every form of use that keeps an operator alive: an expression, an index, a compound assignment and a relational pattern, also through an override in another file |
| `xref_*.dart` | the cross-library reference recovery, and telling same-named members apart |

Run the finder against the demo tier from the repository root:

```console
$ dart run ciach example --exclude 'lib/scenarios/**'
```

Expected output:

```text
lib/extensions.dart
  13:7   method  IntExtras.tripled  (public)
  27:20  method  Vector2.-  (public)

lib/greeting.dart
  15:6  function  danglingFunction  (public)
  18:6  function  _danglingPrivate  (private)
  24:7  variable  unusedConstant  (public)
  30:5  variable  staleCounter  (public)
  35:6  function  _referencesOnlyInDocs  (private)
  41:6  function  _docOnlyMentioned  (private)  (only referenced from dead _referencesOnlyInDocs (lib/greeting.dart:35))

lib/orphans.dart
  8:7   class        UnusedClass  (public)
  22:7  class        FullyDeadClass  (public)
  31:3  constructor  ReferencedAsTypeOnly.new  (public)

lib/private_ctors.dart
  12:14  constructor  SoleMarker._  (private)  (looks like a prevent-instantiation constructor — for a non-instantiable static-only class, prefer `abstract final class`)
  25:13  constructor  MultiCtor._unused  (private)
  35:13  constructor  ParamCtor._  (private)

lib/shapes.dart
  12:3   enum value  Direction.south  (public)
  18:3   enum value  Direction.west  (public)
  22:7   mixin       Loud  (public)  (only `with` or `implements` clauses use it; `--remove` also removes it from them)
  33:10  method      Animal.sound  (public)

lib/user.dart
  12:13  constructor  UsedClass.named  (public)
  27:14  property     UsedClass.shout  (public)
  36:8   method       UsedClass.unusedMethod  (public)
  39:13  field        UsedClass._unusedField  (private)

Found 22 unused declarations in 6 files (scanned 9 files, 63 declarations, ...s).
```

Things worth noticing:

- Findings are **grouped by file**, one section per file, in the order the
  files sort by path — that's what spreading the fixture across several files
  buys you here.
- Declarations that *are* referenced (e.g. `UsedClass`, `registerHandlers`,
  `Direction.north`) are not reported, no matter which file references them
  from. The mixin `Loud` is reported because only a `with` clause names it.
- Constructors are reported as `Class.named` or `Class.new`; extension members
  as `Extension.member`. `IntExtras` itself is not reported: an extension is
  used through its members, and `doubled` is called.
- `FullyDeadClass` is reported as the whole class, not as its constructor:
  removing the class takes the constructor with it.
- `_docOnlyMentioned` is reached only by a `[link]` in the doc comment of
  `_referencesOnlyInDocs`, which is unused, so it is reported as used only by
  that function.
- `testExecutable` in `test/flutter_test_config.dart` is not reported: nothing
  on disk calls it, but `flutter test` does, and ciach knows that contract.
- `Dog.sound` (an `@override`) is skipped by default; add `--also overrides` to
  include it — which also reveals `Animal.sound`, the abstract method it
  implements.
- `Vector2.-` is reported, and `Vector2.+` is not, because `bin/app.dart`
  adds two vectors with `+`.
- Try `--no-public` to see only the highest-confidence, private dead code.
- Drop the `--exclude` to scan the scenario fixtures too: they are deliberately
  full of dead declarations, so the report gets much longer.
