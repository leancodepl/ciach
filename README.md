<!--
AI-Provenance:
  model: claude-opus-4-8
  harness: Claude Code
  plugins:
    - lean-ai-provenance
  skills:
    - mark-ai-provenance
-->

<div align="center">

[![Banner][banner-img]][leancode-landing]

</div>

# ciach 🔪

[![ciach pub.dev badge][pub-badge]][pub-badge-link]
[![Test status][test-badge]][test-badge-link]
[![License: Apache 2.0][license-badge]][license-badge-link]

**Dead code detector for Dart and Flutter.** Finds declarations that are never
referenced — classes, functions, methods, fields, constants, enum values — and
can remove them for you.

*"Ciach!"* — pronounced **/t͡ɕax/** — is Polish for the sound of a clean chop,
the noise a knife makes right before something falls off.

## Installation

Install it globally for a `ciach` command everywhere, in `~/.pub-cache/bin`:

```bash
dart pub global activate ciach
```

Or add it as a dev dependency, which pins the version for the team and CI:

```bash
dart pub add --dev ciach
dart run ciach
```

Examples below show bare `ciach …`; prefix them with `dart run` for the second.

## Usage

```bash
ciach                                  # scan the current package
ciach path/to/package                  # scan another package
ciach --no-public -f json              # private-only (highest confidence), as JSON
ciach -f github --set-exit-if-changed  # CI: annotations, non-zero if anything is found
ciach --remove                         # delete the findings, after confirming
ciach --remove --force                 # …without asking
```

### Options

| Option | Default | Description |
| --- | --- | --- |
| `[path]` | `.` | Package root to analyze. |
| `-h, --help` | — | Print usage information. |
| `--config <path>` | auto | Read settings from this YAML file instead of the auto-discovered one. See [Configuration file](#configuration-file). |
| `--no-config` | off | Ignore the config file, even if one is found. |
| `--[no-]public` | on | Report unused public declarations too. Disable to report only private (`_`-prefixed) ones. |
| `--[no-]generated` | off | Scan generated files (`*.g.dart`, `*.freezed.dart`, `*.mocks.dart`, …). |
| `--[no-]overrides` | off | Report `@override` members too. Off by default — see limitations. |
| `--[no-]operators` | off | Report operator overloads (`operator +`, `operator ==`, …) too. Off by default — see limitations. |
| `--[no-]unused-union-members` | off | Also flag a (sealed) supertype member matched only by type patterns, never constructed. Report-only — never touched by `--remove`. |
| `--[no-]report-tojson` | off | Report an otherwise-unused `toJson()` serialization hook too. Off by default — `jsonEncode` dispatches to it dynamically. |
| `--set-exit-if-changed` | off | Exit with status `1` when anything is found (for CI). Named after `dart format`. |
| `--remove` | off | Remove unused declarations after reporting them. Prompts for confirmation first. |
| `--force` | off | Skip the confirmation prompt for `--remove`. Requires `--remove`. |
| `-e, --exclude <glob>` | — | Skip files matching the glob (repeatable). |
| `-i, --include <glob>` | — | Only scan files matching the glob (repeatable). |
| `--generated-suffix <suffix>` | — | Extra filename suffix (with leading dot) to treat as generated and skip, on top of the built-in set; repeatable. Ignored when `--generated` is set. |
| `-k, --kinds <list>` | all | Restrict to kinds: `class, mixin, interface, enum, extension, function, method, constructor, field, property, getter, setter, variable, constant, enum-value`. |
| `-f, --format <fmt>` | `text` | `text`, `json`, or `github` (GitHub Actions `::warning` annotations). |
| `-j, --concurrency <n>` | `16` | Reference queries kept in flight against the analysis server. |
| `--[no-]color` | auto | Colorize text output. |
| `--[no-]progress` | auto | Show scan progress on stderr. |
| `--dart <path>` | current SDK | Path to the `dart` executable to launch the server with. |

Exit codes: `0` success, `1` unused found with `--set-exit-if-changed`, `2`
usage or analysis error.

### Configuration file

Every option above can live in a `ciach.yaml` in the package root, keyed by its
long name minus the `--`, plus `path` for the positional argument:

```yaml
public: false                     # --no-public
exclude: ['test/**', 'tool/**']   # repeatable options take a list, or a bare string
kinds: [class, function, method]
format: github
set-exit-if-changed: true
```

Command line beats config file beats default, even when the flag matches the
default (`ciach --public` overrides `public: false`), and a repeatable option on
the command line replaces the config's list rather than adding to it. Unknown
keys and wrong-typed values are usage errors naming the file and the key.

Discovery looks for that one file name in the analyzed package root, never in a
parent, so each package in a monorepo owns its config. `--config <path>` reads
one from elsewhere; `--no-config` ignores a discovered one; the two can't be
combined.

### Doc-only findings

A dartdoc `[Xxx]` link resolves to a real declaration, so the analysis server
counts it as a reference — but a comment mentioning something isn't the same as
code calling it. Declarations with no *code* references are reported separately,
in every format:

```
lib/greeting.dart
  15:6  function  danglingFunction  (public)

Referenced only from doc comments — not counted as unused, never removed:
lib/greeting.dart
  40:6  function  docOnlyMentioned  (public)
```

These never count toward `--set-exit-if-changed`, are never touched by
`--remove`, and get a `::notice` rather than a `::warning` in `-f github`. Drop
the doc link to have one reported as properly unused.

### GitHub Actions

```yaml
- run: dart pub get
- run: dart run ciach -f github --set-exit-if-changed
```

Each finding becomes a `::warning` annotation inline on the PR diff. Run it from
the repository root so paths resolve; when scanning a sub-package (`ciach -f
github app`), the scan path is prepended automatically.

### Removing declarations

`--remove` deletes every reported declaration — doc comment and annotations
included — after showing what it is about to remove and asking:

```
Found 4 unused declarations in 2 files (scanned 6 files, 44 declarations, 0.5s).
Remove 4 unused declarations? [y/N] y
Removed 4 unused declarations from 2 files.
```

`--force` skips the prompt (and is a usage error on its own); with no terminal to
confirm on and no `--force`, nothing is removed. Run `dart format` afterward:
removal is conservative about *what* it deletes — an ambiguous `int a = 1, b = 2;`
is left alone unless every declarator is unused — but not about spacing.

Removal acts on whatever the finder reports, so it inherits the same
false-positive risk, which `--overrides` and `--operators` widen considerably.
[Doc-only findings](#doc-only-findings) are never included. Review the diff, as
you would after any automated refactor.

## What it skips by default

Each of these is a known source of false positives; the flag opts back in at
that cost.

| Skipped | Why | Flag |
| --- | --- | --- |
| `main` | the entry point is never unused | — |
| `@override` members | often reached polymorphically or by a framework (`build`, `initState`, `==`, …), which a name-based search misses | `--overrides` |
| Operator overloads | the server doesn't resolve `a + b` back to the declaration, so a used operator is flagged every time | `--operators` |
| `call` methods | implicit-call syntax (`obj(…)`) is unresolvable the same way | — |
| `@pragma('vm:entry-point')` | reachable from native code or reflection | — |
| Generated files | by filename convention and the `GENERATED CODE - DO NOT MODIFY BY HAND` banner. Still opened during analysis, so a declaration used only from a `.g.dart` isn't misreported | `--generated` |
| `toJson()` | `jsonEncode(obj)` calls it by dynamic dispatch, leaving no source-level reference | `--report-tojson` |
| Type parameters | always "used" within their scope | — |
| dartdoc `[Xxx]` links | not a code reference; reported as [doc-only](#doc-only-findings) instead of hidden | — |

Private constructors are **not** skipped: an unused `ClassName._` is dead code
like any other. A sole zero-parameter `ClassName._()` — the classic
prevent-instantiation marker — is reported with a hint suggesting `abstract final
class` instead. See [example/](example) for a runnable demonstration of each case.

## Limitations

This is a static, reference-based heuristic, so review its output rather than
deleting blindly:

- **A library package's public API** is legitimately unused from inside the
  package. Prefer `--no-public` there, or treat public findings as advisory.
- **Reflection, dynamic invocation, and names referenced only from generated
  code you excluded** are invisible to a reference search.
- **Entry points other than `main`** (isolate entry points, plugin registrants)
  need excluding or `@pragma('vm:entry-point')`.
- A package that doesn't analyze cleanly (missing `pub get`, errors) yields
  incomplete references.

## Performance

Runtime is the analysis server's, not the tool's. It analyzes the whole package
once per run — tens of seconds for a large Flutter app, and unskippable, since
incomplete analysis means wrong reference counts — then answers one
`textDocument/references` per declaration through a pool of `-j` (default 16),
with scanned files kept open so its resolved-unit cache stays warm.

The lever is how much you ask for. `--no-public` is by far the cheapest mode:
private declarations are library-scoped, so each query searches one library
instead of the whole workspace, and it surfaces the highest-confidence dead code
anyway. `--include`/`--exclude` narrow the scan while still counting references
from everywhere. `dart pub global activate` compiles ahead of time, so there's no
JIT warmup per run.

## Library usage

The finder is also available programmatically:

```dart
import 'package:ciach/ciach.dart';

final result = await Ciach(
  FinderOptions(rootPath: 'path/to/package', includePublic: false),
).run();
for (final decl in result.unused) {
  print('${decl.filePath}:${decl.line} ${decl.qualifiedName}');
}
```

## Development

```bash
dart pub get
dart analyze
dart test          # spins up a real analysis server against the example/ package
```

The implementation lives under `lib/src/`; the CLI entry point is `bin/`.

## License

Licensed under the Apache License, Version 2.0. See [LICENSE](LICENSE).

---

## 🛠️ Maintained by LeanCode

<div align="center">

  [<img src="https://leancodepublic.blob.core.windows.net/public/wide.png" alt="LeanCode Logo" height="100" />][leancode-landing]

</div>

This package is built with 💙 by **[LeanCode][leancode-landing]**.
We are **top-tier experts** focused on Flutter Enterprise solutions.

### Why LeanCode?

- **Creators of [Patrol][patrol-landing]** – the next-gen testing framework for Flutter.
- **Battle-Tested** – we run `ciach` across our own Flutter and Dart codebases to keep them free of dead code.
- **Full-Cycle Product Development** – we take your product from scratch to long-term maintenance.

<div align="center">
  <br />

  **Need help with your Flutter project?**

  [**👉 Hire our team**][leancode-estimate]
  &nbsp;&nbsp;•&nbsp;&nbsp;
  [Check our other packages][leancode-packages]

</div>

[pub-badge]: https://img.shields.io/pub/v/ciach
[pub-badge-link]: https://pub.dev/packages/ciach
[test-badge]: https://github.com/leancodepl/ciach/actions/workflows/test.yml/badge.svg
[test-badge-link]: https://github.com/leancodepl/ciach/actions/workflows/test.yml
[license-badge]: https://img.shields.io/github/license/leancodepl/ciach
[license-badge-link]: https://github.com/leancodepl/ciach/blob/main/LICENSE
[leancode-landing]: https://leancode.co/?utm_source=github.com&utm_medium=referral&utm_campaign=ciach
[leancode-estimate]: https://leancode.co/get-estimate?utm_source=github.com&utm_medium=referral&utm_campaign=ciach
[leancode-packages]: https://pub.dev/packages?q=publisher%3Aleancode.co&sort=downloads
[patrol-landing]: https://patrol.leancode.co/?utm_source=github.com&utm_medium=referral&utm_campaign=ciach
[banner-img]: https://raw.githubusercontent.com/leancodepl/ciach/refs/heads/main/doc/imgs/banner.png
