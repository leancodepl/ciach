<!--
AI-Provenance:
  model: claude-fable-5-1
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
[![style: leancode_lint][leancode-lint-badge]][leancode-lint-badge-link]
[![Pub Points][pub-points-badge]][pub-points-badge-link]

**Dead code detector for Dart and Flutter.** Finds declarations that are never
referenced — classes, functions, methods, fields, constants, enum values — and
can remove them for you.

<div align="center">
  <a href="https://ciach.leancode.co/"><img src="https://raw.githubusercontent.com/leancodepl/ciach/refs/heads/main/doc/imgs/landing-page-button.svg" alt="Explore ciach.leancode.co" /></a>
</div>

*"Ciach!"* — pronounced **/t͡ɕax/** — is Polish for the sound of a clean chop,
the noise a knife makes right before something falls off.

## Contents

- [Installation](#installation)
- [Quick start](#quick-start)
- [Reading the report](#reading-the-report)
- [What it skips by default](#what-it-skips-by-default)
- [Removing dead code](#removing-dead-code)
- [Options](#options)
- [Configuration file](#configuration-file)
- [CI](#ci)
- [Limitations](#limitations)
- [Library usage](#library-usage)
- [Development](#development)
- [License](#license)

The [docs][docs] describe everything in full; each section below links to
its page.

## Installation

```bash
dart install ciach
```

That builds a native `ciach` you can run from anywhere. It runs the analysis
server with the `dart` on your `PATH` (an fvm or Flutter `dart` works too);
`--dart <path>` picks another one.

Or add it as a dev dependency, which pins the version for the team and CI:

```bash
dart pub add --dev ciach
dart run ciach
```

The examples below use a bare `ciach`; with the dev dependency, prefix them with
`dart run`.

ciach needs Dart 3.10 or newer. It analyzes with the SDK it runs on, so that
SDK has to be new enough for the code it scans.

## Quick start

```bash
ciach                                     # the current package
ciach path/to/package                     # another package
ciach --no-public -f json                 # private declarations only, as JSON
ciach --also overrides,operators          # also what is skipped by default
ciach --remove                            # delete the findings, asking first
ciach --remove --force                    # …without asking
ciach -v                                  # explain each step
```

Run `dart pub get` first in every package ciach scans. The report goes to
stdout and everything else to stderr. Exit code `1` means something was found
with `--set-exit-if-changed`, `2` a usage or analysis error. `--no-public` is
by far the cheapest mode. See [Running ciach][docs-running].

## Reading the report

```
lib/user.dart
  12:13  constructor  UsedClass.named  (public)
  27:14  property     UsedClass.shout  (public)
  36:8   method       UsedClass.unusedMethod  (public)
  39:13  field        UsedClass._unusedField  (private)

Found 4 unused declarations in 1 file (scanned 1 file, 12 declarations, 1.2s)
```

An unused class, mixin, extension, extension type or enum is reported once,
without its members. A declaration that only a dartdoc `[Xxx]` link mentions
is listed separately as doc-only: it never counts toward
`--set-exit-if-changed`, and `--remove` never touches it. A declaration used
only by other dead code is reported in the same run, naming what uses it.

Empty files, the declarations that the analysis server could not analyze and
the JSON keys are described in [Reading the report][docs-report].

## What it skips by default

Each of these is a known source of false positives. Where there is a flag, it
opts back in at that cost.

| Skipped | Why | Flag |
| --- | --- | --- |
| `main` | the entry point is never unused | — |
| `testExecutable` in a `flutter_test_config.dart` | `flutter test` calls it | — |
| Declarations annotated with `@Preview` or `@MultiPreview`, or with a subclass of either | `flutter widget-preview` shows them | — |
| Entry points from the [project config][docs-skips] | a framework or a tool calls them | `--no-project-config` |
| `@override` members | often reached polymorphically or by a framework (`build`, `initState`, `==`, …), which a name-based search misses. One that overrides a dead member is dead too, and `--remove` [takes both](#removing-dead-code) | `--also overrides` |
| Operator overloads | the server doesn't resolve `a + b` back to the declaration, so a used operator is flagged every time | `--also operators` |
| Declarations and files marked [`// ciach:ignore`][docs-skips] | they are kept on purpose | — |
| `@pragma('vm:entry-point')` | reachable from native code or reflection | — |
| `@JSExport`, and the public members of a `@JSExport` class | JavaScript can call them | — |
| `test_…` methods of a `@reflectiveTest` class | they run through `dart:mirrors` | — |
| Generated files | by filename, by a generated-code banner, by the [project config][docs-skips] and by `--generated-glob`. Still read, so a declaration used only from a `.g.dart` is not misreported | `--generated` |
| `toJson()` | `jsonEncode(obj)` calls it by dynamic dispatch, leaving no reference | `--also tojson` |
| Type parameters | always used within their scope | — |
| dartdoc `[Xxx]` links | not a code reference; reported as [doc-only][docs-report] instead | — |

`// ciach:ignore` above a declaration keeps it, `// ciach:ignore-file` keeps a
whole file, and `entry-points:` in `ciach.yaml` names what a tool calls.
Private constructors are not skipped: an unused `ClassName._` is dead code
like any other. [What it skips by default][docs-skips] covers the markers,
entry points and generated files in full.

## Removing dead code

`--remove` deletes every reported declaration, doc comment and annotations
included, after showing what it is about to remove and asking:

```
Found 4 unused declarations in 2 files (scanned 6 files, 44 declarations, 0.5s)
Remove 4 unused declarations? [y/N] y
Removed 4 unused declarations from 2 files.
```

`--force` skips the prompt. With no terminal to confirm on and no `--force`,
nothing is removed. Run `dart format` afterward, and review the diff, as you
would after any automated refactor: removal inherits the finder's
false-positive risk, which `--also overrides,operators` widens considerably.

What goes with a removed declaration, which comments stay, and the findings
that are report-only because removing them would not compile:
[Removing dead code][docs-removing].

## Options

`ciach --help` describes every option. In short:

| Option | Default | Description |
| --- | --- | --- |
| `[path]` | `.` | The package to analyze. |
| `--config <path>` | auto | Read this config file instead of the discovered one. See [Configuration file](#configuration-file). |
| `--no-config` | off | Ignore the config file. |
| `--analysis-root <path>` | the scanned path | Count references from this whole directory, not just the scanned package. See [Monorepos][docs-packages]. |
| `--[no-]public` | on | Report public declarations too. Off reports only private ones: `_`-prefixed, or an unnamed extension and its members. |
| `--[no-]generated` | off | Scan generated files (`*.g.dart`, `*.freezed.dart`, `*.mocks.dart`, …) too. |
| `--exported-packages <glob>` | none | Packages that code outside the analysis imports, such as one published to pub.dev: their public API is not reported. Repeatable. See [Library packages][docs-packages]. |
| `--[no-]project-config` | on | Read [entry points][docs-skips] and [generated files][docs-skips] from `pubspec.yaml`, `build.yaml`, `l10n.yaml`, `analysis_options.yaml` and `firebase.json`. |
| `--[no-]unused-translations` | on | Report the unused messages in the gen-l10n template file an `l10n.yaml` configures. Report-only: remove them from the ARB file yourself. |
| `--also <list>` | — | Also report what is [skipped by default](#what-it-skips-by-default): `overrides`, `operators`, `tojson`, `union-members`. |
| `--[no-]transitive` | on | Also report declarations used only by other dead code, naming what uses them. See [Transitively dead code][docs-report]. |
| `--[no-]set-exit-if-changed` | off; on in CI | Exit with `1` when anything is found. |
| `--[no-]ci` | auto | Use the CI defaults, or not. See [CI](#ci). |
| `--remove` | off | Remove the findings and delete empty files, after asking. See [Removing dead code](#removing-dead-code). |
| `--force` | off | Skip the `--remove` prompt. |
| `-e, --exclude <glob>` | — | Skip these files: nothing in them is reported, but their references still count. Repeatable. |
| `-i, --include <glob>` | — | Scan only these files. The references in other files still count. Repeatable. |
| `--generated-glob <glob>` | — | Treat these files as generated: their references count, but nothing in them is reported or removed. For output without a suffix or banner, or code kept as is, like a vendored copy. Repeatable. |
| `-k, --kinds <list>` | all | Report only these kinds: `class, mixin, interface, enum, extension, extension-type, function, method, constructor, field, property, getter, setter, variable, constant, enum-value, typedef`. |
| `-f, --format <fmt>` | `text`; the service's on CI | `text`, `json`, `github`, `azure`, `teamcity`, `sarif`, `checkstyle` or `gitlab`. See [CI](#ci). |
| `-j, --concurrency <n>` | `16` | Reference queries to run at once. |
| `--[no-]color` | auto | Colorize the output. Honors `NO_COLOR`. |
| `--[no-]progress` | auto | Show progress on stderr. On for a terminal, off in CI. |
| `-v, --verbose` | off; on in CI | Explain the run on stderr: the config file and what it set, the settings, each phase, what was skipped and why, and what `--remove` touches. |
| `--dart <path>` | auto | The `dart` to run the analysis server with. |
| `--version` | — | Print the ciach version and exit. |
| `-h, --help` | — | Print the usage information. |

## Configuration file

Every option except `--help`, `--version`, `--config` and `--no-config` can
live in a `ciach.yaml` in the package root, keyed by its long name without the
`--`, plus `path` for the positional argument:

```yaml
public: false                     # --no-public
analysis-root: ..                 # --analysis-root
exported-packages: [packages/api] # see Library packages
exclude: ['test/**', 'tool/**']   # a repeatable option takes a list, or one string
kinds: [class, function, method]
format: github
set-exit-if-changed: true
entry-points:                     # config file only; see Entry points
  - name: bootstrap
    glob: 'lib/src/isolate.dart'
```

The command line wins over the file, and the file over the default. Options
from earlier versions are errors that say what to use instead; see
[MIGRATION.md](MIGRATION.md). The keys, including `exported-packages` for a
library package and `entry-points`, are in [Configuration file][docs-config].

## CI

ciach detects CI from the environment and changes its defaults there:
`--set-exit-if-changed` and `--verbose` on, `--progress` off, and the
service's format on GitHub Actions, Azure Pipelines and TeamCity. An explicit
option still wins.

```yaml
- run: dart pub get
- run: dart run ciach
```

On GitHub Actions each finding becomes a `::warning` annotation on the PR
diff, and the job fails when anything is found. Azure Pipelines, TeamCity, and
the SARIF, Checkstyle and GitLab report formats: [CI][docs-ci].

## Limitations

ciach is a static, reference-based heuristic, so review its output rather than
deleting blindly:

- **A published package's consumers** are invisible, which is why its API is
  [left out][docs-packages]. In a monorepo, [`--analysis-root`][docs-packages]
  recovers uses from a sibling package.
- **Reflection, dynamic invocation, and names used only from generated code you
  excluded** are invisible to a reference search.
- **Other entry points**, such as isolate entry points and native callbacks,
  have to be listed under [`entry-points`][docs-skips] or marked with
  `@pragma('vm:entry-point')`.
- **A primary constructor shares its class's references**: a never-invoked one
  only surfaces once the class itself is dead.
- **A package that doesn't analyze cleanly**, from a stale `pub get` or errors,
  yields incomplete references.
- **Bugs in the analysis server's reference search** can report used code as
  unused, or make a query fail and land a declaration under "Not analyzed".
  [doc/upstream_bugs.md][upstream-bugs] lists the ones ciach has found and the
  SDK commits that fixed them.

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

ciach logs through [`package:logging`](https://pub.dev/packages/logging), with
loggers such as `ciach.finder` and `ciach.lsp`. It never configures the root
logger; listen on `Logger.root.onRecord` to see the records.

## Development

```bash
dart pub get
dart analyze --fatal-infos
dart test          # spins up a real analysis server against the example/ package
```

The implementation lives under `lib/src/`; the CLI entry point is `bin/`.
`lib/src/finder.dart` runs a scan as a pipeline, and its doc comment maps the
directories under `lib/src/` to the stages. Tests mirror that layout under
`test/`; `test/finder/` runs the whole finder against the `example/` package.
`test/readme_toc_test.dart` checks that [Contents](#contents) lists every
section of this file.

## License

Licensed under the Apache License, Version 2.0. See [LICENSE](LICENSE).

---

## 🛠️ Maintained by LeanCode

<div align="center">

  [<img src="https://leancodepublic.blob.core.windows.net/public/wide.png" alt="LeanCode Logo" width="262" />][leancode-landing]

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

[site]: https://ciach.leancode.co/
[docs]: https://ciach.leancode.co/docs
[docs-running]: https://ciach.leancode.co/docs#running-ciach
[docs-report]: https://ciach.leancode.co/docs#reading-the-report
[docs-skips]: https://ciach.leancode.co/docs#what-it-skips-by-default
[docs-removing]: https://ciach.leancode.co/docs#removing-dead-code
[docs-config]: https://ciach.leancode.co/docs#configuration-file
[docs-packages]: https://ciach.leancode.co/docs#packages-and-monorepos
[docs-ci]: https://ciach.leancode.co/docs#ci
[upstream-bugs]: https://github.com/leancodepl/ciach/blob/main/doc/upstream_bugs.md

[pub-badge]: https://img.shields.io/pub/v/ciach?style=for-the-badge&logo=dart
[pub-badge-link]: https://pub.dev/packages/ciach

[test-badge]: https://img.shields.io/github/actions/workflow/status/leancodepl/ciach/test.yml?branch=main&style=for-the-badge&logo=github
[test-badge-link]: https://github.com/leancodepl/ciach/actions/workflows/test.yml

[license-badge]: https://img.shields.io/github/license/leancodepl/ciach?style=for-the-badge
[license-badge-link]: https://github.com/leancodepl/ciach/blob/main/LICENSE

[leancode-lint-badge]: https://img.shields.io/badge/style-leancode__lint-f0ff00?style=for-the-badge
[leancode-lint-badge-link]: https://pub.dev/packages/leancode_lint

[pub-points-badge]: https://img.shields.io/pub/points/ciach?style=for-the-badge&logo=dart
[pub-points-badge-link]: https://pub.dev/packages/ciach/score

[leancode-landing]: https://leancode.co/?utm_source=github.com&utm_medium=referral&utm_campaign=ciach
[leancode-estimate]: https://leancode.co/get-estimate?utm_source=github.com&utm_medium=referral&utm_campaign=ciach
[leancode-packages]: https://pub.dev/packages?q=publisher%3Aleancode.co&sort=downloads
[patrol-landing]: https://patrol.leancode.co/?utm_source=github.com&utm_medium=referral&utm_campaign=ciach
[banner-img]: https://raw.githubusercontent.com/leancodepl/ciach/refs/heads/main/doc/imgs/banner.png
