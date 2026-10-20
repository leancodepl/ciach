{{!
  AI-Provenance:
    model: claude-fable-5-1
    harness: Claude Code
    plugins:
      - lean-ai-provenance
    skills:
      - mark-ai-provenance
}}

## Reading the report

```console wrap=false
lib/user.dart
  12:13  constructor  UsedClass.named  (public)
  27:14  property     UsedClass.shout  (public)
  36:8   method       UsedClass.unusedMethod  (public)
  39:13  field        UsedClass._unusedField  (private)

Found 4 unused declarations in 1 file (scanned 1 file, 12 declarations, 1.2s)
```

An unused class, mixin, extension, extension type or enum is reported once, without its members. An enum that is used while none of its values are is reported once too, and never removed: an enum needs at least one value.

### Doc-only findings

A declaration that only dartdoc `[Xxx]` links mention gets a section of its own, in every format:

```console wrap=false
Referenced only from doc comments (1) · not counted, never removed
lib/greeting.dart
  40:6  function  docOnlyMentioned  (public)
```

They never count toward `--set-exit-if-changed`, `--remove` never touches them, and `-f github` gives them a `::notice` rather than a `::warning`. Drop the doc link to have one reported as unused.

A type that only doc comments mention, and whose members are unused, is reported once as a finding. `--remove` leaves it alone while doc comments still link to it.

### Empty files

A file with nothing but comments and `library`, `import` or `part of` directives gets a section too:

```console wrap=false
Empty files (2) · nothing but comments and library, import or part-of directives
lib/legacy/helpers.dart
lib/web.dart  (a conditional-import variant: remove its `if` clause and the file by hand)
```

These count toward `--set-exit-if-changed`. `--remove` deletes them with the `import`s of them, except a conditional-import variant, which is left to you.

### Transitively dead code

A declaration used only by other dead code is reported in the same run, and so are dead cycles: declarations that only reference each other.

```console wrap=false
lib/report.dart
  12:6  function  _build      (private)
  20:6  function  _formatRow  (private)  (only referenced from dead _build (lib/report.dart:12))
  40:6  function  _ping       (private)  (only referenced from dead _pong (lib/report.dart:42))
  42:6  function  _pong       (private)  (only referenced from dead _ping (lib/report.dart:40))
```

Each such finding names what it is only referenced from, so a chain can be judged by its root: `-f json` lists every finding a declaration depends on under the `onlyReferencedFrom` key, and the other formats show the first and a count. A report-only finding stays in the code, so what it references stays used. `--no-transitive` reports only what nothing references at all; the rest shows up after a removal and another run.

### Not analyzed

If the analysis server fails on a declaration or a file, the run goes on. That code is kept and listed under "Not analyzed" (`problems` in JSON); `-v` adds the stack traces.
