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
