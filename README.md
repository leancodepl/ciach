<!--
AI-Provenance:
  model: claude-opus-4-8
  harness: Claude Code
  plugins:
    - lean-ai-provenance
  skills:
    - mark-ai-provenance
-->

# unused_declarations_finder

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
dart run unused_declarations_finder

# Scan a specific package
dart run unused_declarations_finder path/to/package

# Only the highest-confidence dead code (private, never-referenced), as JSON
dart run unused_declarations_finder --no-public -f json

# GitHub Actions annotations; fail the job if anything is found
dart run unused_declarations_finder -f github --set-exit-if-changed
```

Install it globally with `dart pub global activate --source path .` and then run
`unused_declarations_finder` directly.

### Options

| Option | Default | Description |
| --- | --- | --- |
| `[path]` | `.` | Package root to analyze. |
| `--[no-]public` | on | Report unused public declarations too. Disable to report only private (`_`-prefixed) ones. |
| `--[no-]generated` | off | Scan generated files (`*.g.dart`, `*.freezed.dart`, `*.mocks.dart`, …). |
| `--[no-]overrides` | off | Report `@override` members too. Off by default — see limitations. |
| `--set-exit-if-changed` | off | Exit with status `1` when anything is found (for CI). Named after `dart format`. |
| `-e, --exclude <glob>` | — | Skip files matching the glob (repeatable). |
| `-i, --include <glob>` | — | Only scan files matching the glob (repeatable). |
| `-k, --kinds <list>` | all | Restrict to kinds: `class, mixin, interface, enum, extension, function, method, constructor, field, property, getter, setter, variable, constant, enum-value, operator`. |
| `-f, --format <fmt>` | `text` | `text`, `json`, or `github` (GitHub Actions `::warning` annotations). |
| `-j, --concurrency <n>` | `16` | Reference queries kept in flight against the analysis server. |
| `--[no-]color` | auto | Colorize text output. |
| `--[no-]progress` | auto | Show scan progress on stderr. |
| `--dart <path>` | current SDK | Path to the `dart` executable to launch the server with. |

Exit codes: `0` success, `1` unused found with `--set-exit-if-changed`, `2`
usage or analysis error.

### GitHub Actions

```yaml
- run: dart run unused_declarations_finder -f github --set-exit-if-changed
```

Each finding becomes a `::warning` annotation shown inline on the PR diff. Run
it from the repository root so annotation paths resolve; when scanning a
sub-package (e.g. `unused_declarations_finder -f github app`), the scan path is
prepended automatically so annotations still point at the right files.

## What it skips by default

- **`main`** — the program entry point.
- **`@override` members** — they are frequently reached polymorphically or by a
  framework (Flutter's `build`, `initState`, `dispose`, `toString`, `==`, …),
  which a name-based reference search can miss. Use `--overrides` to include
  them.
- **`@pragma('vm:entry-point')`** — reachable from native code / reflection.
- **Generated files** — by filename convention and the
  `GENERATED CODE - DO NOT MODIFY BY HAND` banner. Use `--generated` to include.
- **`type parameters`** and non-declaration symbols.

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
`dart compile exe bin/unused_declarations_finder.dart -o udf` (or
`dart pub global activate --source path .`).

## Library usage

The tool also exposes a public API for running the finder programmatically:

```dart
import 'package:unused_declarations_finder/unused_declarations_finder.dart';

final result = await UnusedDeclarationsFinder(
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
