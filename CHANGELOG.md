## Unreleased

- Fix unused enum values being reported under the `enum` kind instead of
  `enum-value`. The analysis server tags enum values with the same symbol kind
  as the enum type itself, so a detected unused value was labelled `enum` and
  `--kinds enum-value` never listed it (it showed up under `--kinds enum`).
  Enum values are now remapped to the `enum-value` kind for both reporting and
  kind filtering, while unused enum types keep the `enum` kind.
- Add `--generated-suffix` (repeatable) to configure extra filename suffixes
  treated as generated, on top of the built-in set (`*.g.dart`,
  `*.freezed.dart`, …). Some code generators emit files with a custom suffix
  (e.g. `.gc.dart`) and without the conventional `GENERATED CODE` banner, so
  their declarations were scanned and misreported as unused. Configured
  suffixes are excluded from the scan but still opened for reference
  resolution, exactly like the built-in generated files.
- Skip `call` methods by default. A `call` method makes its object callable
  via implicit-call syntax (`obj(...)`), which the analysis server's reference
  search doesn't resolve back to the declaration — the same limitation as for
  infix operators — so a used `call` method was reported as unused every time.
  Always skipped; there's no flag for this one.
- Skip private constructors (`ClassName._`, `ClassName._named`) by default.
  They are the standard pattern for preventing instantiation of a
  utility/constants class, so they are deliberately never referenced; reporting
  them was a false positive, and `--remove` deleting one would re-add the
  implicit default constructor and silently make the class instantiable.
- Fix `--remove` corrupting compact, single-line enums (`enum E { a, b, c }`):
  removing a value now starts the deletion at the value's own token instead of
  column 0 of its line, so the `enum E {` prefix and sibling values survive.
  Removing several values from the same line in one pass is now safe too — any
  subset (adjacent or not, including the first or last value) leaves the header
  and every surviving value intact, with no doubled spaces or dangling
  separator comma. Multi-line (formatted) enums are unaffected.
- Fix `--remove` corrupting a compact, single-line enum that has a leading doc
  or annotation comment (`/// …` / `//` / `@…` above `enum E { a, b, c }`).
  Removing a value used to walk upward into the enum type's own leading
  comment and collapse the whole declaration to ` }`, deleting the comment,
  the `enum E {` header, and any surviving values. A value's removal span now
  never crosses above its own line when the value shares that line with the
  header, so the leading comment, the header, and the kept values all survive.
- Open generated files (`*.g.dart`, …) while analyzing, even when they are
  excluded from the scan, so a declaration referenced *only* from generated
  code (e.g. a `toJson` called from a `.g.dart` part) is no longer misreported
  as unused. Their own declarations are still not reported.

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
