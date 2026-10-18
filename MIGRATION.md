# Migrating

## From 0.7 to 0.8

### Operators are reported by default

ciach now finds the uses of operators, so it reports an unused operator like
any other method, and `--also operators` is gone. Drop `operators` from
`--also` and from `also:` in `ciach.yaml`. To keep an operator that ciach
reports, mark it with [`// ciach:ignore`](README.md#ignore-markers). Code
that uses ciach as a library drops the `skipOperators` argument of
`FinderOptions`.

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
