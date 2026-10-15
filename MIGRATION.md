# Migrating

## From 0.6 to the next release

### Removed options

Options from 0.6 are errors now, on the command line and in `ciach.yaml`.
Each error says what to use instead:

| Old option | Use instead |
| --- | --- |
| `--overrides`, `--operators` | `--also overrides`, `--also operators` |
| `--report-tojson` | `--also tojson` |
| `--unused-union-members` | `--also union-members` |
| `--exported` | `--exported-packages=` |
| `--generated-suffix <suffix>` | `--generated-glob '**/*<suffix>'` |
| `--fail-public`, `--no-exported` and the `--no-` forms above | nothing: that is the default now |
| `--no-fail-public` | nothing: every finding counts toward the exit code now |

In `ciach.yaml`, the same goes for the keys: `overrides: true` becomes
`also: [overrides]`, and `exported: true` becomes `exported-packages: []`.

### What other packages can import is left out by default

In 0.6, ciach reported every package's public API. Now it leaves out what other
packages can import, because ciach can't see importers outside the analysis.

If all the importers of your packages are in the analysis, as in an app or a
monorepo, check every package's API again:

```yaml
# ciach.yaml
exported-packages: []
```

If only some packages are imported from outside, such as a package published to
pub.dev or used as a git dependency, list just those. See
[Library packages](README.md#library-packages).

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
