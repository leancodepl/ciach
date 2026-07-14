## Unreleased

- Add `--generated-suffix` (repeatable) to treat extra filename suffixes as
  generated, on top of the built-in set (`*.g.dart`, `*.freezed.dart`, …).
- Open generated files during analysis so a declaration referenced only from
  generated code is no longer misreported as unused.
- Fix `--remove` corrupting compact single-line enums (`enum E { a, b, c }`)
  when removing one or more values.
- Fix `--remove` deleting the leading doc/annotation comment and header when
  removing a value from a compact single-line enum.
- Detect a whole dead class instead of only its constructor. A class whose only
  references are self-references — its own explicit unnamed constructor's
  declaration (whose name range coincides with the class name), a `State<Self>`
  return type on its own `createState`, or the `State<Self>` pairing of its
  paired `State` subclass (the `StatefulWidget` pattern) — is now reported as an
  unused `class`, not as a stray unused constructor. Previously such a class
  looked "used" (the reference search was satisfied by the constructor's own
  declaration), so `--remove` deleted just the constructor and left the class
  behind, stranding `final` fields or breaking `super()` calls. The detection is
  deliberately conservative: any reference from outside the class keeps it alive,
  so it prefers missing a dead class to ever flagging a live one. The class's own
  constructor is no longer double-reported, and for a dead `StatefulWidget` the
  paired private `State` subclass is removed together with it (so
  `State<DeletedWidget>` never dangles) without being reported as a separate
  finding.

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
