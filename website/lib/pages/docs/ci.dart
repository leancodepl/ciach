/*
 * AI-Provenance:
 *   model: claude-fable-5-1
 *   harness: Claude Code
 *   plugins:
 *     - lean-ai-provenance
 *   skills:
 *     - mark-ai-provenance
 */

import 'package:ciach_website/components/code_block.dart';
import 'package:ciach_website/components/docs_table.dart';
import 'package:ciach_website/components/section.dart';
import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

const _workflow = '''
- run: dart pub get
- run: dart run ciach''';

const _pipeline = '''
- script: dart pub get && dart run ciach''';

const _gitlab = '''
ciach:
  script: dart run ciach -f gitlab > gl-code-quality-report.json
  artifacts:
    reports:
      codequality: gl-code-quality-report.json''';

/// The formats that are files for another tool to import.
const _reports = [
  (
    'sarif',
    'GitHub code scanning (`github/codeql-action/upload-sarif`), Azure DevOps, SonarQube and other SARIF dashboards.',
  ),
  (
    'checkstyle',
    'Jenkins Warnings Next Generation and other Checkstyle report plugins.',
  ),
  ('gitlab', 'A GitLab Code Quality report, shown on the merge request.'),
];

class const CiSection({super.key}) extends StatelessComponent {
  @override
  Component build(BuildContext context) => DocSection(
    id: 'ci',
    heading: 'CI',
    children: [
      p(
        rich(
          "ciach detects CI from the environment (`CI`, or a service's own "
          'variable such as `GITHUB_ACTIONS`) and changes its defaults there:',
        ),
      ),
      ul(classes: Prose.checklist.name, [
        li(rich('`--set-exit-if-changed` on: the job fails on findings.')),
        li(rich('`--verbose` on: the log explains the run.')),
        li(rich('`--progress` off.')),
        li(
          rich(
            '`--format github` on GitHub Actions, `azure` on Azure Pipelines, `teamcity` on TeamCity.',
          ),
        ),
      ]),
      p(
        rich(
          'An explicit option still wins. `--no-ci` keeps the local defaults '
          'on a runner, `--ci` applies the CI ones elsewhere.',
        ),
      ),
      const DocHeading(
        fragment: 'github-actions',
        text: 'GitHub Actions',
        subsection: true,
      ),
      const CodeBlock(
        source: _workflow,
        language: .yaml,
        title: '.github/workflows/test.yml',
      ),
      p(
        rich(
          'Each finding becomes a `::warning` annotation on the PR diff, and '
          'the job fails when anything is found. Report paths start at the '
          'repository root wherever ciach runs from: on GitHub Actions, GitLab '
          'CI and Azure Pipelines ciach finds the root from the checkout the '
          'service names. Elsewhere they start at the current directory, so '
          'run ciach from the repository root; `ciach app` still works.',
        ),
      ),
      const DocHeading(
        fragment: 'azure-teamcity',
        text: 'Azure Pipelines and TeamCity',
        subsection: true,
      ),
      const CodeBlock(source: _pipeline, language: .yaml, copyText: ''),
      p(
        rich(
          "On Azure Pipelines each finding becomes a warning in the run's "
          'summary (doc-only ones too: Azure has nothing below a warning). On '
          "TeamCity each one is an inspection on the build's Inspections tab, "
          'a doc-only one a weak warning. Run ciach from the checkout root on '
          'TeamCity, which names no checkout to it.',
        ),
      ),
      const DocHeading(
        fragment: 'other-tools',
        text: 'Reports for other tools',
        subsection: true,
      ),
      const p([
        .text(
          'Three formats are files for another tool to import, so redirect them:',
        ),
      ]),
      docsTable(
        columns: const ['Format', 'For'],
        rows: [
          for (final (format, tools) in _reports)
            [
              code([.text(format)]),
              span(rich(tools)),
            ],
        ],
      ),
      const CodeBlock(
        source: _gitlab,
        language: .yaml,
        title: '.gitlab-ci.yml',
      ),
      p(
        rich(
          'Unused findings and empty files are warnings (`minor` in GitLab), '
          'doc-only findings a severity lower. GitLab fingerprints leave out '
          'the line, so a finding that only moved is not reported as new.',
        ),
      ),
    ],
  );
}
