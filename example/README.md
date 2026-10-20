<!--
AI-Provenance:
  model: claude-fable-5-1
  harness: Claude Code
  plugins:
    - lean-ai-provenance
  skills:
    - mark-ai-provenance
-->

# Example

`example/` is a small Dart package, `sample_pkg`, with a deliberate mix of
used and unused declarations across a few files: top-level functions and
constants, a class with constructors, fields and properties, an enum, a mixin,
an extension and an operator overload. It is also the fixture of the test
suite: `lib/scenarios/` holds one file per detection rule, each saying up front
what it covers, and the run below leaves them out.

From a clone of the repository, in its root:

```bash
dart pub get
dart run ciach example --exclude 'lib/scenarios/**'
```

```
lib/extensions.dart
  13:7  method  IntExtras.tripled  (public)

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

Found 21 unused declarations in 6 files (scanned 9 files, 61 declarations, 1.6s)
```

What the report shows:

- Findings are grouped by file, in path order, with the line and column of
  each declaration's name.
- What `bin/app.dart` references is not reported: `UsedClass`,
  `registerHandlers`, `Direction.north`, `IntExtras.doubled`.
- A constructor is reported as `Class.named` or `Class.new`, and an extension
  member as `Extension.member`. `IntExtras` itself is not reported, because
  `doubled` is called.
- `UnusedClass` and `FullyDeadClass` are reported once, as the class, without
  their members: removing the class removes them too.
- `_docOnlyMentioned` is named only by a doc comment of `_referencesOnlyInDocs`,
  which is dead itself, so the finding says what it is only referenced from.
- `Animal.sound` is never called. `Dog.sound` overrides it and is skipped by
  default, as every `@override` is; `--also overrides` reports it too.
- `Loud` is reported as the whole mixin: `whisper` is never called, and
  `emphasize` only from `Dog.sound`. Only a `with` clause names the mixin, so
  `--remove` deletes it from that clause as well.
- `Vector2.+` and `Vector2.-` are skipped by default. `--also operators`
  reports both, although `+` is used in `bin/app.dart`: the analysis server's
  reference search doesn't resolve operator syntax back to the declaration.
- `testExecutable` in `test/flutter_test_config.dart` is not reported, because
  `flutter test` calls it, and `Multiplier.call` is not reported, because an
  instance is invoked as `multiplier(21)`.
- `--no-public` narrows the report to the private declarations, and dropping
  the `--exclude` adds the scenario fixtures, which are full of dead code on
  purpose.

Each file holds a few kinds of declaration:

| File | Declarations |
| --- | --- |
| `lib/greeting.dart` | top-level functions, constants, and a mutable variable |
| `lib/user.dart` | constructors, fields, methods, and a getter/setter pair |
| `lib/shapes.dart` | an enum, a mixin, and an abstract class with an `@override` |
| `lib/extensions.dart` | an extension method and operator overloading |
| `lib/orphans.dart` | classes never referenced at all, and one referenced only as a type |
| `lib/callables.dart` | a callable class whose `call` method is used only by invoking an instance |
| `lib/private_ctors.dart` | private constructors reported like any dead code, with a prevent-instantiation hint on the sole zero-parameter `Foo._()` |
| `test/flutter_test_config.dart` | the `flutter test` hook `testExecutable`, called by nothing on disk yet never reported |

## Removing the findings

`--remove` deletes what the report lists, after asking; `--force` skips the
question:

```bash
dart run ciach example --exclude 'lib/scenarios/**' --remove --force
```

```
Found 21 unused declarations in 6 files (scanned 9 files, 61 declarations, 1.9s)
Removed 21 unused declarations from 6 files. Run `dart format` to tidy up spacing.
Left 2 declarations empty because other code still uses them:
  ReferencedAsTypeOnly (lib/orphans.dart)
  Animal (lib/shapes.dart)
Kept 1 comment that sat right above removed code. Check whether it still belongs:
  lib/shapes.dart:22
Note: SoleMarker._: looks like a prevent-instantiation constructor — for a non-instantiable static-only class, prefer `abstract final class`
Note: Loud: only `with` or `implements` clauses use it; `--remove` also removes it from them
```

`ReferencedAsTypeOnly` and `Animal` stay, because other code names them as
types, and only their members are gone.
