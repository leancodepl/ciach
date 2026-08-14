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
| `lib/callables.dart` | a callable class (`call` method), whose implicit-call use is skipped |
| `lib/private_ctors.dart` | private constructors reported like any dead code, with a prevent-instantiation hint on the sole zero-parameter `Foo._()` |

`lib/scenarios/` holds the **scenario fixtures**: one file (or a small cluster
of them) per detection rule, each pinning down one behavior that is easy to
regress. Every file says up front what it covers and which findings are
expected; each is scanned only by its own test, never by the demo run above.

| Fixture | Rule it pins down |
| --- | --- |
| `widgets.dart` | the `StatefulWidget`/`State` pairing, so a dead widget is reported as a class and its `State` is removed with it |
| `unions.dart` | the opt-in `--unused-union-members` detection, across the three pattern-matching contexts |
| `guards.dart` | the remove-safety guards: findings that must be report-only because removing them would not compile |
| `enum_values.dart` | enum values reached only through `.values` iteration count as used |
| `freezed_unions.dart` | `@freezed` union arms built only by a generated `fromJson` |
| `serialization.dart` | the `toJson`/`fromJson` conventions, and `--report-tojson` |
| `comment_annotations.dart` | a comment mentioning `@override` or `vm:entry-point` does not skip the declaration below it |
| `dot_shorthands.dart`, `dot_shorthand_uses.dart` | every context a `.name` dot shorthand is allowed in, including nested constructor shorthands |
| `primary_constructors.dart` | primary constructors: a dead declaration in the class header is report-only, while the class body stays removable |
| `xref_*.dart` | the cross-library reference recovery, and telling same-named members apart |

Run the finder against the demo tier from the repository root:

```console
$ dart run ciach example --exclude 'lib/scenarios/**'
```

Expected output:

```text
lib/extensions.dart
  13:7  method  tripled  (public)

lib/greeting.dart
  15:6  function  danglingFunction  (public)
  18:6  function  _danglingPrivate  (private)
  24:7  variable  unusedConstant  (public)
  30:5  variable  staleCounter  (public)
  35:6  function  _referencesOnlyInDocs  (private)

lib/orphans.dart
  8:7   class        UnusedClass  (public)
  10:8  method       UnusedClass.orphanMethod  (public)
  22:7  class        FullyDeadClass  (public)
  31:3  constructor  ReferencedAsTypeOnly.new  (public)

lib/private_ctors.dart
  11:14  constructor  SoleMarker._  (private)  (looks like a prevent-instantiation constructor — for a non-instantiable static-only class, prefer `abstract final class`)
  24:13  constructor  MultiCtor._unused  (private)
  34:13  constructor  ParamCtor._  (private)

lib/shapes.dart
  12:3   enum value  Direction.south  (public)
  18:3   enum value  Direction.west  (public)
  27:10  method      Loud.whisper  (public)
  33:10  method      Animal.sound  (public)

lib/user.dart
  12:13  constructor  UsedClass.named  (public)
  27:14  property     UsedClass.shout  (public)
  36:8   method       UsedClass.unusedMethod  (public)
  39:13  field        UsedClass._unusedField  (private)

Referenced only from doc comments — not counted as unused, never removed:
lib/greeting.dart
  41:6  function  _docOnlyMentioned  (private)

Found 21 unused declarations in 6 files (scanned 8 files, 59 declarations, ...s).
1 more referenced only from doc comments.
```

Things worth noticing:

- Findings are **grouped by file**, one section per file, in the order the
  files sort by path — that's what spreading the fixture across several files
  buys you here.
- Declarations that *are* referenced (e.g. `UsedClass`, `registerHandlers`,
  `Direction.north`, the mixin `Loud`) are not reported, no matter which file
  references them from.
- Constructors are reported as `Class.named` or `Class.new`.
- `FullyDeadClass` is reported as the whole class, not as its constructor:
  removing the class takes the constructor with it.
- `_docOnlyMentioned` is reached only by a `[link]` in another declaration's doc
  comment, so it is listed separately and never removed.
- `Dog.sound` (an `@override`) is skipped by default; add `--overrides` to
  include it — which also reveals `Animal.sound`, the abstract method it
  implements.
- `Vector2.+` and `Vector2.-` are skipped by default; add `--operators` to
  report them. They surface even though `+` is called in `bin/app.dart`,
  because the analysis server's reference search does not resolve infix
  operator syntax back to the operator's declaration. See the main README's
  Limitations section.
- Try `--no-public` to see only the highest-confidence, private dead code.
- Drop the `--exclude` to scan the scenario fixtures too: they are deliberately
  full of dead declarations, so the report gets much longer.
