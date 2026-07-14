# Example

This directory is a small, self-contained Dart package (`sample_pkg`) with a
deliberate mix of **used** and **unused** declarations, spread across several
files so the report's per-file grouping actually has something to group. It
doubles as the integration-test fixture, so it is a real, runnable
demonstration of the tool.

| File | Declarations it demonstrates |
| --- | --- |
| `lib/greeting.dart` | top-level functions, constants, and a mutable variable |
| `lib/user.dart` | constructors, fields, methods, and a getter/setter pair |
| `lib/shapes.dart` | an enum, a mixin, and an abstract class with an `@override` |
| `lib/extensions.dart` | an extension method and operator overloading |
| `lib/orphans.dart` | a class that is never referenced at all |
| `lib/callables.dart` | a callable class (`call` method) and a utility class with a private constructor |

Run the finder against it from the repository root:

```console
$ dart run ciach example
```

Expected output:

```text
lib/extensions.dart
  13:7   method  tripled  (public)
  27:20  method  Vector2.+  (public)
  30:20  method  Vector2.-  (public)

lib/greeting.dart
  15:6  function  danglingFunction  (public)
  18:6  function  _danglingPrivate  (private)
  24:7  variable  unusedConstant  (public)
  30:5  variable  staleCounter  (public)

lib/orphans.dart
  7:7   class        UnusedClass  (public)
  9:8   method       UnusedClass.orphanMethod  (public)
  16:3  constructor  Unconstructed.new  (public)

lib/shapes.dart
  12:3   enum    Direction.south  (public)
  18:3   enum    Direction.west  (public)
  27:10  method  Loud.whisper  (public)
  33:10  method  Animal.sound  (public)

lib/user.dart
  12:13  constructor  UsedClass.named  (public)
  27:14  property     UsedClass.shout  (public)
  36:8   method       UsedClass.unusedMethod  (public)
  39:13  field        UsedClass._unusedField  (private)

Found 18 unused declarations in 5 files (scanned 6 files, 44 declarations, ...s).
```

Things worth noticing:

- Findings are **grouped by file**, one section per file, in the order the
  files sort by path — that's what spreading the fixture across five files
  buys you here.
- Declarations that *are* referenced (e.g. `UsedClass`, `registerHandlers`,
  `Direction.north`, the mixin `Loud`) are not reported, no matter which file
  references them from.
- Constructors are reported as `Class.named` or `Class.new`.
- `Dog.sound` (an `@override`) is skipped by default; add `--overrides` to
  include it — which also reveals `Animal.sound`, the abstract method it
  implements.
- `Vector2.+` and `Vector2.-` are reported even though `+` is called in
  `bin/app.dart`: the analysis server's reference search does not resolve
  infix operator syntax back to the operator's declaration. See the main
  README's Limitations section.
- Try `--no-public` to see only the highest-confidence, private dead code
  (`_danglingPrivate` and `UsedClass._unusedField` here).
