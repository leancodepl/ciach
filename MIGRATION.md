# Migrating

## From 0.7 to 0.8

### `SymbolKind` in the Dart API

This concerns only code that uses `package:ciach` as a library. The
`SymbolKind` that it exports is now ciach's own enum, with the same values,
instead of the one from `package:pro_lsp`:

- The `SymbolKindLabel` extension is gone. `kind.label` works as before,
  because `label` is now a member of the enum.
- `SymbolKind.value` and `SymbolKind.decode`, the protocol's numbers for the
  kinds, are gone too.
- Code that imports `package:pro_lsp` as well gets two different
  `SymbolKind`s, so hide one of them: `import 'package:pro_lsp/pro_lsp.dart'
  hide SymbolKind;`.

### `EntryPoint.lookups` and `EntryPoint.annotationNames`

These getters named what the analysis server had to look up before a rule
could select a declaration. `package:analyzer` now resolves all of it, so
both getters are gone, with no replacement.

### Operator overloads are reported

ciach used to skip operator overloads, because the analysis server didn't
connect `a + b` to `operator +`. It now finds those uses, so an operator
overload that nothing uses is reported like any other method. Drop
`operators` from `--also` and from `also:` in `ciach.yaml`: both are errors
now.

### Recovered references

ciach used to look again for the uses of a declaration that the analysis
server reported no references for, and listed each use that it found as a
recovered reference. It now finds every use with `package:analyzer`, so there
is nothing left to recover, and the list is gone from every output:

- The text report has no "Recovered references" section, and its summary line
  no "recovered" count.
- The JSON report has no `warnings` array.
- The CI annotations and SARIF have no `recovered-reference` check.
- In the Dart API, `FinderResult.recoveredReferences` and the
  `RecoveredReference` class are gone, with no replacement.

### `--concurrency` is removed

`--concurrency`, or `-j`, set how many requests ciach sent to the Dart
analysis server at once. ciach no longer starts the analysis server, so the
option has nothing left to set. Drop it from the command line and
`concurrency` from `ciach.yaml`: both are errors now.

### The analysis server in the Dart API

This concerns only code that uses `package:ciach` as a library. ciach reads
the code with `package:analyzer` in its own process and no longer starts the
Dart analysis server, so these are gone, with no replacement:

- `FinderOptions.concurrency`.
- `LspRequestException` and `AnalysisServerExitedException`, which a run no
  longer throws.
- `AnalysisProblem.detail`, the stack trace of the server, and the `detail`
  key of a problem in the JSON report.

## From 0.6 to 0.7

### Removed options

Options from 0.6 are errors now, on the command line and in `ciach.yaml`.
Each error says what to use instead:

| Old option | Use instead |
| --- | --- |
| `--overrides`, `--operators` | `--also overrides`, `--also operators` |
| `--report-tojson` | `--also tojson` |
| `--unused-union-members` | `--also union-members` |
| `--no-exported` | `--exported-packages '**'` |
| `--generated-suffix <suffix>` | `--generated-glob '**/*<suffix>'` |
| `--fail-public`, `--exported` and the `--no-` forms above | nothing: that is the default now |
| `--no-fail-public` | nothing: every finding counts toward the exit code now |

In `ciach.yaml`, the same goes for the keys: `overrides: true` becomes
`also: [overrides]`, and `exported: false` becomes `exported-packages: ['**']`.

### What only dead code references is reported by default

In 0.6, a helper called only by dead code showed up only after that code was
removed and ciach ran again, unless you passed `--transitive`. Now ciach
reports it in the same run, and dead cycles too, each naming what it is only
referenced from. To report only what nothing references at all, as before:

```yaml
# ciach.yaml
transitive: false
```

See [Transitively dead code](README.md#transitively-dead-code).
