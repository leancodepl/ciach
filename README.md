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

*"Ciach!"* — pronounced **/t͡ɕax/** — is Polish for the sound of a clean chop,
the noise a knife makes right before something falls off. Fitting, since
that's exactly what this tool finds for you: dead code, waiting to be cut.

Finds **unused (never-referenced) declarations** — classes, functions, methods,
fields, constants, enum values, and so on — in a Dart or Flutter package.

Rather than re-implementing reference resolution, it drives the **Dart analysis
server over LSP** and asks it, for every declaration, `textDocument/references`
with `includeDeclaration: false`. If the server reports zero references, the
declaration is unused. This reuses the analyzer's battle-tested, cross-file
reference search (including polymorphic dispatch through interfaces).

The LSP transport (JSON-RPC framing, request/response correlation, lifecycle,
and the typed wire models) is handled by the
[`pro_lsp`](https://pub.dev/packages/pro_lsp) package, whose types are used
directly throughout. `lib/src/lsp/lsp_client.dart` is a thin session wrapper
that adds only what `pro_lsp` doesn't: spawning the server process, awaiting the
Dart-specific `$/analyzerStatus` idle signal, and shutting the process down
cleanly.

## How it works

1. Spawn the analysis server: `dart language-server --protocol=lsp`, using the
   same SDK that runs the tool (`Platform.resolvedExecutable`).
2. `initialize` at the package root and wait for the initial analysis to settle
   (tracked via the server's `$/analyzerStatus` notifications).
3. For each `.dart` file, enumerate declarations with
   `textDocument/documentSymbol`.
4. For each declaration, query `textDocument/references` at its name. Empty
   result ⇒ unused.

Because the whole package is analyzed, references from anywhere — including test
files — count as usage, so the tool won't flag production code that is only used
by tests.

## Usage

```bash
# Scan the current package
dart run ciach

# Scan a specific package
dart run ciach path/to/package

# Only the highest-confidence dead code (private, never-referenced), as JSON
dart run ciach --no-public -f json

# GitHub Actions annotations; fail the job if anything is found
dart run ciach -f github --set-exit-if-changed

# Remove what's found, after confirming
dart run ciach --remove

# Remove without asking (e.g. from a script)
dart run ciach --remove --force
```

Install it globally with `dart pub global activate --source path .` and then run
`ciach` directly.

### Options

| Option | Default | Description |
| --- | --- | --- |
| `[path]` | `.` | Package root to analyze. |
| `--[no-]public` | on | Report unused public declarations too. Disable to report only private (`_`-prefixed) ones. |
| `--[no-]generated` | off | Scan generated files (`*.g.dart`, `*.freezed.dart`, `*.mocks.dart`, …). |
| `--[no-]overrides` | off | Report `@override` members too. Off by default — see limitations. |
| `--[no-]operators` | off | Report operator overloads (`operator +`, `operator ==`, …) too. Off by default — see limitations. |
| `--ignore-doc-references` | off | Don't count dartdoc `[Xxx]` comment links as a use. Off by default — see limitations. |
| `--set-exit-if-changed` | off | Exit with status `1` when anything is found (for CI). Named after `dart format`. |
| `--remove` | off | Remove unused declarations after reporting them. Prompts for confirmation first. |
| `--force` | off | Skip the confirmation prompt for `--remove`. Requires `--remove`. |
| `-e, --exclude <glob>` | — | Skip files matching the glob (repeatable). |
| `-i, --include <glob>` | — | Only scan files matching the glob (repeatable). |
| `-k, --kinds <list>` | all | Restrict to kinds: `class, mixin, interface, enum, extension, function, method, constructor, field, property, getter, setter, variable, constant, enum-value`. |
| `-f, --format <fmt>` | `text` | `text`, `json`, or `github` (GitHub Actions `::warning` annotations). |
| `-j, --concurrency <n>` | `16` | Reference queries kept in flight against the analysis server. |
| `--[no-]color` | auto | Colorize text output. |
| `--[no-]progress` | auto | Show scan progress on stderr. |
| `--dart <path>` | current SDK | Path to the `dart` executable to launch the server with. |

Exit codes: `0` success, `1` unused found with `--set-exit-if-changed`, `2`
usage or analysis error.

### GitHub Actions

```yaml
- run: dart run ciach -f github --set-exit-if-changed
```

Each finding becomes a `::warning` annotation shown inline on the PR diff. Run
it from the repository root so annotation paths resolve; when scanning a
sub-package (e.g. `ciach -f github app`), the scan path is
prepended automatically so annotations still point at the right files.

### Removing declarations

`--remove` deletes every reported declaration from source — its doc comment
and annotations included — after showing what it's about to remove and asking
for confirmation:

```
$ dart run ciach --remove
lib/greeting.dart
  15:6  function  danglingFunction  (public)
...
Found 4 unused declarations in 2 files (scanned 6 files, 44 declarations, 0.5s).
Remove 4 unused declarations? [y/N] y
Removed 4 unused declarations from 2 files.
```

`--remove --force` skips the prompt; use it in a script once you're confident
in the results (`--force` on its own, without `--remove`, is a usage error).
Without a terminal to confirm on (e.g. piped into another program) and
without `--force`, nothing is removed.

Run `dart format` afterward — removal is conservative about *what* to delete
(it leaves ambiguous multi-variable statements like `int a = 1, b = 2;`
alone unless every declarator in them is unused) but not about spacing, so
expect the odd extra blank line.

Because removal acts on whatever the finder reports, it inherits the same
false-positive risk as the report itself (see [What it skips by
default](#what-it-skips-by-default) and [Limitations](#limitations) below) —
enabling `--overrides` or `--operators` widens that risk considerably. Review
the diff (or your test suite) after removing, the same as you would after any
automated refactor.

## What it skips by default

These are all off by default because they're known sources of false
positives — a used declaration reported as unused. Each has a flag to opt
back in, at the cost of reintroducing that risk:

- **`main`** — the program entry point. Always skipped; there's no flag for
  this one.
- **`@override` members** — they are frequently reached polymorphically or by a
  framework (Flutter's `build`, `initState`, `dispose`, `toString`, `==`, …),
  which a name-based reference search can miss. Use `--overrides` to include
  them.
- **Operator overloads** (`operator +`, `operator ==`, …) — the analysis
  server's reference search does not resolve infix operator syntax (`a + b`)
  back to the operator's declaration, so a used operator is reported as
  unused every time. See `example/lib/extensions.dart`. Use `--operators` to
  include them.
- **`@pragma('vm:entry-point')`** — reachable from native code / reflection.
- **Generated files** — by filename convention and the
  `GENERATED CODE - DO NOT MODIFY BY HAND` banner. Use `--generated` to include.
- **`type parameters`** and non-declaration symbols.

By contrast, **dartdoc `[Xxx]` reference links count as a use** — this
errs the other way, toward under-reporting: a link resolves to a real
declaration, so the analysis server treats it as a reference even if nothing
actually calls the declaration. This can hide genuinely dead code (e.g. `///
See [Dog.sound]` keeps `Dog.sound` looking used). Pass
`--ignore-doc-references` to disregard those comment-only references and
surface declarations like that as unused — at the cost of flagging things
that are legitimately referenced only from documentation.

## Limitations

This is a static, reference-based heuristic. Expect to review its output rather
than delete blindly:

- **Public API of a library package** is legitimately "unused" from the
  package's own perspective. Prefer `--no-public` for library packages, or treat
  public findings as advisory.
- **Reflection / dynamic invocation / serialization** (e.g. `dart:mirrors`,
  code that is only referenced by name in generated code you excluded) is not
  visible to a reference search.
- **Entry points beyond `main`** (isolate entry points, plugin registrants) may
  need excluding or annotating with `@pragma('vm:entry-point')`.
- Results are only as good as the analysis: a package that does not analyze
  cleanly (missing `pub get`, errors) may yield incomplete references.

## Performance

Runtime is dominated by the analysis server, not the tool. Two phases matter:

1. **Initial analysis** — the server analyzes the whole package (and, for a
   Flutter app, the SDK/dependencies) once before any query. This is a fixed
   per-run cost (tens of seconds for a large app) and cannot be skipped:
   incomplete analysis would produce wrong reference counts.
2. **Reference queries** — one `textDocument/references` per declaration.
   Requests run through a global pool (`-j/--concurrency`, default 16) and the
   scanned files are kept open so the server's resolved-unit cache stays warm.

The biggest lever is **how much you ask**:

- **`--no-public`** is by far the cheapest mode. Private declarations are
  library-scoped, so the server only searches one library per query instead of
  the whole workspace — often several times faster, and it surfaces the
  highest-confidence dead code.
- **`--include` / `--exclude`** to scan only the part of the tree you care
  about — references are still counted from everywhere, so results stay correct.
- **`-j`** to tune concurrency; the default (16) is near the point of
  diminishing returns for the analysis server's internal parallelism.

For repeated runs, compile once to skip the JIT warmup:
`dart compile exe bin/ciach.dart -o ciach` (or
`dart pub global activate --source path .`).

## Library usage

The tool also exposes a public API for running the finder programmatically:

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

The implementation lives under `lib/src/`; the CLI entry point is `bin/`. See
[example/](example) for a runnable demonstration.

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