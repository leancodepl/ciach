{{!
  AI-Provenance:
    model: claude-fable-5-1
    harness: Claude Code
    plugins:
      - lean-ai-provenance
    skills:
      - mark-ai-provenance
}}

## CI

ciach detects CI from the environment (`CI`, or a service's own variable such as `GITHUB_ACTIONS`) and changes its defaults there:

- `--set-exit-if-changed` on: the job fails on findings.
- `--verbose` on: the log explains the run.
- `--progress` off.
- `--format github` on GitHub Actions, `azure` on Azure Pipelines, `teamcity` on TeamCity.

An explicit option still wins. `--no-ci` keeps the local defaults on a runner, `--ci` applies the CI ones elsewhere.

### GitHub Actions

```yaml title=".github/workflows/test.yml"
- run: dart pub get
- run: dart run ciach
```

Each finding becomes a `::warning` annotation on the PR diff, and the job fails when anything is found. Report paths start at the repository root wherever ciach runs from: on GitHub Actions, GitLab CI and Azure Pipelines ciach finds the root from the checkout the service names. Elsewhere they start at the current directory, so run ciach from the repository root; `ciach app` still works.

### Azure Pipelines and TeamCity

```yaml copy=false
- script: dart pub get && dart run ciach
```

On Azure Pipelines each finding becomes a warning in the run's summary (doc-only ones too: Azure has nothing below a warning). On TeamCity each one is an inspection on the build's Inspections tab, a doc-only one a weak warning. Run ciach from the checkout root on TeamCity, which names no checkout to it.

### Reports for other tools

Three formats are files for another tool to import, so redirect them:

| Format | For |
| --- | --- |
| `sarif` | GitHub code scanning (`github/codeql-action/upload-sarif`), Azure DevOps, SonarQube and other SARIF dashboards. |
| `checkstyle` | Jenkins Warnings Next Generation and other Checkstyle report plugins. |
| `gitlab` | A GitLab Code Quality report, shown on the merge request. |

```yaml title=".gitlab-ci.yml"
ciach:
  script: dart run ciach -f gitlab > gl-code-quality-report.json
  artifacts:
    reports:
      codequality: gl-code-quality-report.json
```

Unused findings and empty files are warnings (`minor` in GitLab), doc-only findings a severity lower. GitLab fingerprints leave out the line, so a finding that only moved is not reported as new.
