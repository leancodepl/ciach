## Unreleased

- Add `--generated-suffix` (repeatable) to treat extra filename suffixes as
  generated, on top of the built-in set (`*.g.dart`, `*.freezed.dart`, …).
- Open generated files during analysis so a declaration referenced only from
  generated code is no longer misreported as unused.
- Fix `--remove` corrupting compact single-line enums (`enum E { a, b, c }`)
  when removing one or more values.
- Fix `--remove` deleting the leading doc/annotation comment and header when
  removing a value from a compact single-line enum.
- Report a whole dead class as unused, not just its constructor, so `--remove`
  deletes the class instead of stranding it. Detection is conservative: any
  reference from outside the class keeps it alive.
- Remove a dead `StatefulWidget` together with its paired private `State`
  subclass, so `State<DeletedWidget>` never dangles.
- Add remove-safety guards: `--remove` skips (but still reports) any removal
  that wouldn't compile — emptying a still-referenced enum, dropping a sole
  constructor with `final` fields, or dropping a super-forwarding constructor.
- Add opt-in `--unused-union-members` to report sealed types that are only
  pattern-matched and never constructed. Report-only: `--remove` never deletes
  them.
- Skip `call` methods by default; implicit-call references (`obj(...)`) aren't
  resolvable, so they were always misreported as unused.
- Report an unused private constructor like any other dead declaration (and
  remove it with `--remove`); a sole zero-parameter `ClassName._()` also gets a
  hint suggesting `abstract final class` to keep a static-only class
  non-instantiable.

## 0.2.0+2

- Update the README.

## 0.2.0+1

- Add pub.dev `topics` and `issue_tracker` metadata for discoverability. No
  code changes.

## 0.2.0

- Add `--remove` to delete unused declarations from source after reporting
  them, with a confirmation prompt; `--remove --force` skips the prompt.
- Skip operator overloads (`operator +`, `operator ==`, …) by default — the
  analysis server can't resolve infix operator syntax back to the
  declaration, so a used operator was always reported as unused. Pass
  `--operators` to include them anyway.
- Report declarations referenced only from a dartdoc `[Xxx]` comment link as
  a separate, informational "doc-only" category (in `text`, `json`, and
  `github` output) instead of hiding them entirely. Doc-only findings are
  never deleted by `--remove`.
- Clarify installation instructions: global activation vs. adding `ciach` as
  a dev dependency.

## 0.1.0

Initial implementation.
