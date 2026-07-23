## 0.3.0

- Lower the minimum Dart SDK constraint from `^3.12.2` to `^3.10.0`.
  ([#20](https://github.com/leancodepl/ciach/pull/20))
- Never report a `toJson()` as unused; `jsonEncode(obj)` calls it by dynamic
  dispatch, with no source-level reference for the search to see. Opt back in
  with `--report-tojson`. ([#17](https://github.com/leancodepl/ciach/pull/17))
- Add `--generated-suffix` (repeatable) to treat extra filename suffixes as
  generated, on top of the built-in set (`*.g.dart`, `*.freezed.dart`, …).
  ([#13](https://github.com/leancodepl/ciach/pull/13))
- Open generated files during analysis so a declaration referenced only from
  generated code is no longer misreported as unused.
  ([#13](https://github.com/leancodepl/ciach/pull/13))
- Fix `--remove` corrupting compact single-line enums (`enum E { a, b, c }`)
  when removing one or more values.
  ([#11](https://github.com/leancodepl/ciach/pull/11))
- Fix `--remove` deleting the leading doc/annotation comment and header when
  removing a value from a compact single-line enum.
  ([#11](https://github.com/leancodepl/ciach/pull/11))
- Report a whole dead class as unused, not just its constructor, so `--remove`
  deletes the class instead of stranding it. Detection is conservative: any
  reference from outside the class keeps it alive.
  ([#10](https://github.com/leancodepl/ciach/pull/10))
- Remove a dead `StatefulWidget` together with its paired private `State`
  subclass, so `State<DeletedWidget>` never dangles.
  ([#10](https://github.com/leancodepl/ciach/pull/10))
- Add remove-safety guards: `--remove` skips (but still reports) any removal
  that wouldn't compile — emptying a still-referenced enum, dropping a sole
  constructor with `final` fields, or dropping a super-forwarding constructor.
  ([#10](https://github.com/leancodepl/ciach/pull/10))
- Add opt-in `--unused-union-members` to report sealed types that are only
  pattern-matched and never constructed. Report-only: `--remove` never deletes
  them. ([#10](https://github.com/leancodepl/ciach/pull/10))
- Skip `call` methods by default; implicit-call references (`obj(...)`) aren't
  resolvable, so they were always misreported as unused.
  ([#14](https://github.com/leancodepl/ciach/pull/14))
- Report an unused private constructor like any other dead declaration (and
  remove it with `--remove`); a sole zero-parameter `ClassName._()` also gets a
  hint suggesting `abstract final class` to keep a static-only class
  non-instantiable. ([#14](https://github.com/leancodepl/ciach/pull/14))
- Fix enum values reached only through `.values` iteration being reported as
  unused. ([#15](https://github.com/leancodepl/ciach/pull/15))
- Fix unused enum values being reported under the `enum` kind instead of
  `enum-value`. ([#12](https://github.com/leancodepl/ciach/pull/12))
- Don't report deserialized freezed union variants as unused; the generated
  `fromJson` builds the concrete subclass directly, bypassing the redirecting
  factory. ([#16](https://github.com/leancodepl/ciach/pull/16))

## 0.2.0+2

- Update the README. ([#6](https://github.com/leancodepl/ciach/pull/6))

## 0.2.0+1

- Add pub.dev `topics` and `issue_tracker` metadata for discoverability. No
  code changes. ([#5](https://github.com/leancodepl/ciach/pull/5))

## 0.2.0

- Add `--remove` to delete unused declarations from source after reporting
  them, with a confirmation prompt; `--remove --force` skips the prompt.
  ([#4](https://github.com/leancodepl/ciach/pull/4))
- Skip operator overloads (`operator +`, `operator ==`, …) by default — the
  analysis server can't resolve infix operator syntax back to the
  declaration, so a used operator was always reported as unused. Pass
  `--operators` to include them anyway.
  ([#4](https://github.com/leancodepl/ciach/pull/4))
- Report declarations referenced only from a dartdoc `[Xxx]` comment link as
  a separate, informational "doc-only" category (in `text`, `json`, and
  `github` output) instead of hiding them entirely. Doc-only findings are
  never deleted by `--remove`.
  ([#4](https://github.com/leancodepl/ciach/pull/4))
- Clarify installation instructions: global activation vs. adding `ciach` as
  a dev dependency. ([#4](https://github.com/leancodepl/ciach/pull/4))

## 0.1.0

Initial implementation. ([#1](https://github.com/leancodepl/ciach/pull/1))
