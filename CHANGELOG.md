## Unreleased

- `--transitive` also reports dead cycles: declarations that only reference
  each other.
  ([#87](https://github.com/leancodepl/ciach/pull/87))
- A dead `StatefulWidget` whose `State` is used elsewhere (say, by a
  `GlobalKey`) is report-only: `--remove` deleted the widget and left
  `State<Widget>` naming a missing type. A `State` in another file is now
  removed with its widget, instead of being left behind the same way.
  ([#87](https://github.com/leancodepl/ciach/pull/87))
- Add `--no-exported` (`exported: false`): skip only declarations other
  packages can import. ([#85](https://github.com/leancodepl/ciach/pull/85))
- Resolve `package:` URIs through `.dart_tool/package_config.json`, as Dart
  does, instead of the pubspecs under the root. `--remove` no longer keeps an
  emptied file because a path dependency outside the root has a file at the
  same `lib/` path. ([#92](https://github.com/leancodepl/ciach/pull/92))
- Read entry points and generated files from `pubspec.yaml`, `build.yaml`
  and `l10n.yaml` — of every package under the scanned path, `build.<name>.yaml`
  included; `--no-project-config` turns it off.
  ([#86](https://github.com/leancodepl/ciach/pull/86))
- Add `--unused-translations`: report unused gen-l10n messages, report-only.
  ([#86](https://github.com/leancodepl/ciach/pull/86))
- Skip `@JSExport` and `@reflectiveTest` test methods.
  ([#86](https://github.com/leancodepl/ciach/pull/86))
- Recognize more generated-code banners (protoc, Serverpod, Pigeon, …).
  ([#86](https://github.com/leancodepl/ciach/pull/86))

## 0.6.0

- **Breaking:** `FinderOptions.onProgress` is removed; ciach logs through
  `package:logging`.
  ([#78](https://github.com/leancodepl/ciach/pull/78))
- Recommend `dart install ciach` over `dart pub global activate` in the README
  and on the website. ([#83](https://github.com/leancodepl/ciach/pull/83))
- A failed analysis server request no longer stops the run: the affected code
  is kept and listed under "Not analyzed". The result goes to stdout, the log
  to stderr, with more color.
  ([#78](https://github.com/leancodepl/ciach/pull/78))
- Require `glob` 2.2.0. On 2.1.x, `**/flutter_test_config.dart` did not match
  a `flutter_test_config.dart` at the package root, so its `testExecutable`
  was reported as unused.
  ([#75](https://github.com/leancodepl/ciach/pull/75))
- Add `--generated-glob <glob>` (and `generated-glob:` in `ciach.yaml`): treat
  matching files as generated, so their references count but nothing in them
  is reported or removed. For output a suffix can't pick out, like
  `flutter gen-l10n`'s `lib/l10n/**`, which has neither a suffix nor the
  banner. Unlike `--exclude`, the files are still opened.
  ([#76](https://github.com/leancodepl/ciach/pull/76))
- A member used only through an override, from a file that doesn't import the
  member's library, is no longer reported (nor deleted with `--remove`).
  ([#79](https://github.com/leancodepl/ciach/pull/79))
- Checking a dead member's overrides is much faster: they share its
  references, so they are no longer queried one by one.
  ([#77](https://github.com/leancodepl/ciach/pull/77))
- Add `--transitive` (and `transitive:` in `ciach.yaml`): also report
  declarations referenced only from other findings, which used to take another
  run after `--remove`. Each one names the findings that reference it
  (`onlyReferencedFrom` in `-f json`). Off by default.
  ([#72](https://github.com/leancodepl/ciach/pull/72))
- A reference from inside a declaration's own span no longer keeps it alive,
  for every kind: a function or method called only by itself is now reported.
  Classes already worked this way.
  ([#67](https://github.com/leancodepl/ciach/pull/67))
- `FinderOptions` normalizes `rootPath` and `analysisRootPath`, and a run throws
  an `ArgumentError` when the analysis root doesn't contain the scanned one, so
  a library caller gets the check the CLI already had. The constructor is no
  longer `const`.
  ([#64](https://github.com/leancodepl/ciach/pull/64))
- `--remove` deletes a dead member's overrides along with it, so no `@override`
  is left overriding nothing. A member is reported but not removed when one of
  its overrides can't be deleted: a declaring parameter of a primary
  constructor, or one in a file the run didn't scan.
  ([#63](https://github.com/leancodepl/ciach/pull/63))
- Read a field declarator's doc comment and annotations from the statement it
  belongs to. `b` in `@override final int a, b;` reported none of its own, so
  it was checked where an `@override` member is skipped.
  ([#63](https://github.com/leancodepl/ciach/pull/63))
- Add `--analysis-root <path>` (and `analysis-root:` in `ciach.yaml`): count
  references from a directory wider than the scanned package, so a sibling
  package that depends on it by `path:` keeps what it calls alive. What is
  scanned, reported and removed is unchanged. A pub workspace needs no setting.
  ([#61](https://github.com/leancodepl/ciach/pull/61))

## 0.5.0

- Read declarations from the analysis server's outline instead of the source
  text. `--remove` deletes a declaration's doc comment and annotations as the
  analyzer delimits them: a multi-line annotation goes with it, a `//` comment
  above it stays. `UnusedDeclaration` gains `fullRange`.
  ([#53](https://github.com/leancodepl/ciach/pull/53))
- Read comments and annotations from the analysis server's semantic tokens.
  Dartdoc links in `/** */` comments count as doc-only references, and
  `@override` and `vm:entry-point` are detected by annotation, not by text.
  ([#54](https://github.com/leancodepl/ciach/pull/54))
- Read the syntax around a reference from the analysis server's selection
  ranges instead of a built-in lexer.
  ([#55](https://github.com/leancodepl/ciach/pull/55))
- Ask the analysis server about a class's superclass before blocking the
  removal of its last constructor: a `StatelessWidget` subclass is no longer
  blocked on `super.key`. The built-in Dart lexer is gone.
  ([#56](https://github.com/leancodepl/ciach/pull/56))

## 0.4.5

- Stop reporting (and removing) `testExecutable` in a `flutter_test_config.dart`,
  which only the `flutter test` bootstrap calls.
  ([#51](https://github.com/leancodepl/ciach/pull/51))
- Add `entry-points` to `ciach.yaml`: `{name, glob}` rules for a project's own
  tool-called declarations. A member rule keeps its type; `--verbose` names each
  skipped entry point.
- Check `extension`s and `extension type`s, which were invisible before: a dead
  one is removed whole rather than having its members stripped and the shell
  left behind. `-k extension` and `-k extension-type` select them, and members
  report as `Extension.member`.
  ([#50](https://github.com/leancodepl/ciach/pull/50))
- `--remove` deletes a file it leaves with only `library`/`import`/`part of`
  lines and drops the directives naming it; `removeDeclarations` returns a
  `RemovalResult`. ([#50](https://github.com/leancodepl/ciach/pull/50))

## 0.4.4

- Fix a compiled `ciach` (`dart install`) spawning itself as the analysis
  server and failing every run. ([#44](https://github.com/leancodepl/ciach/pull/44))
- Show the analysis server's exit code and stderr when it dies.

## 0.4.3

- Add `--version`, and show the version in the `--help` header. The analysis
  server now sees the real version instead of `1.0.0`.

## 0.4.2

- Support Dart 3.13 primary constructors: a dead constructor or declaring
  parameter in a class header is report-only, since `--remove` cannot delete
  part of a header.
- Stop reporting a primary constructor's `this : …` body part as a `Class.this`
  finding, and a dead class's declaring parameters separately from the class.
- Count only what `--remove` actually deletes in its summary.

## 0.4.1

- Fix a constructor reached only through a dot shorthand (`.new(…)`), from a
  file that never names its class, being reported as unused.

## 0.4.0

- Add config file support: any option can be set in a `ciach.yaml` in the
  package root, and the command line overrides it. `--config <path>` reads one
  from elsewhere, `--no-config` ignores it.
- Add `-v`, `--verbose` to narrate a run on stderr: config used, every setting
  and the layer it came from, scan phases, what `--remove` touches. Supersedes
  `--progress`.
- Fix a comment mentioning `@override` or `vm:entry-point` skipping the declaration below it. ([#29](https://github.com/leancodepl/ciach/pull/29))
- Add a secondary `textDocument/definition` check for zero-reference
  declarations, so valid uses the reference search misses no longer produce
  false 'unused' reports. ([#26](https://github.com/leancodepl/ciach/pull/26))
- Add `--[no-]fail-public` (default on): `--no-fail-public` still reports unused
  public declarations but excludes them from `--set-exit-if-changed`, so CI fails
  only on unused private ones. ([#23](https://github.com/leancodepl/ciach/pull/23))
- Document the `--unused-union-members`, `--report-tojson`,
  `--generated-suffix`, and `--help` options in the README, which existed in
  the CLI but were missing from the options table.
  ([#22](https://github.com/leancodepl/ciach/pull/22))

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
