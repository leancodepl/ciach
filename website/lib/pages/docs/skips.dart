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
import 'package:ciach_website/styles.dart';
import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

/// What is skipped, why, and the flag that opts back in.
const _skips = [
  ('`main`', 'the entry point is never unused', null),
  (
    '`testExecutable` in a `flutter_test_config.dart`',
    '`flutter test` calls it',
    null,
  ),
  (
    'Entry points from the project config',
    'a framework or a tool calls them',
    '--no-project-config',
  ),
  (
    '`@override` members',
    'often reached polymorphically or by a framework (`build`, `initState`, '
        '`==`, …), which a name-based search misses. One that overrides a dead '
        'member is dead too, and `--remove` takes both',
    '--also overrides',
  ),
  (
    'Operator overloads',
    "the server doesn't resolve `a + b` back to the declaration, so a used operator is flagged every time",
    '--also operators',
  ),
  (
    'Declarations and files marked `// ciach:ignore`',
    'they are kept on purpose',
    null,
  ),
  (
    "`@pragma('vm:entry-point')`",
    'reachable from native code or reflection',
    null,
  ),
  (
    '`@JSExport`, and the public members of a `@JSExport` class',
    'JavaScript can call them',
    null,
  ),
  (
    '`test_…` methods of a `@reflectiveTest` class',
    'they run through `dart:mirrors`',
    null,
  ),
  (
    'Generated files',
    'by filename, by a generated-code banner, by the project config and by '
        '`--generated-glob`. Still read, so a declaration used only from a '
        '`.g.dart` is not misreported',
    '--generated',
  ),
  (
    '`toJson()`',
    '`jsonEncode(obj)` calls it by dynamic dispatch, leaving no reference',
    '--also tojson',
  ),
  ('Type parameters', 'always used within their scope', null),
  (
    'dartdoc `[Xxx]` links',
    'not a code reference; reported as doc-only instead',
    null,
  ),
];

/// The entry points read from the project's own config files.
const _entryPoints = [
  (
    '`build.yaml` builders',
    'the functions under `builder_factories` or `builder_factory`',
  ),
  (
    '`pubspec.yaml` plugin',
    "`registerWith` on each platform's `dartPluginClass` and on the web `pluginClass`",
  ),
  ('`dart_frog`', '`onRequest`, `middleware`, `init`, `run`'),
  (
    '`serverpod`',
    'the classes that extend `Endpoint`, and their public methods',
  ),
  (
    '`analysis_server_plugin`, or a package an `analysis_options.yaml` under the root loads as a plugin by `path:`',
    '`plugin` in `lib/main.dart`',
  ),
  ('`custom_lint_builder`', '`createPlugin` in `lib/<package>.dart`'),
];

const _entryPointsConfig = '''
entry-points:
  - name: MyHost.callback         # a member: `Type.member`, no type parameters
    glob: 'lib/my_host.dart'      # one glob or a list; omit for any file
  - name: bootstrap               # a top-level declaration
    glob: 'lib/src/isolate.dart\'''';

const _markers = '''
// ciach:ignore
void keptForTheWidgetbook() {}        // the declaration on the next line

/// Its doc comment and annotations may sit around the marker.
// ciach:ignore
@visibleForTesting
void alsoKept() {}

void keptToo() {} // ciach:ignore    // after code: the one named on its line

// ciach:ignore-start
class Catalog {                       // everything named in the range
  void member() {}
}
// ciach:ignore-end''';

class const SkipsSection({super.key}) extends StatelessComponent {
  @override
  Component build(BuildContext context) => DocSection(
    id: 'skips',
    heading: 'What it skips by default',
    children: [
      const p([
        .text(
          'Each of these is a known source of false positives. Where there is a flag, it opts back in at that cost.',
        ),
      ]),
      docsTable(
        columns: const ['Skipped', 'Why', 'Flag'],
        rows: [
          for (final (what, why, flag) in _skips)
            [
              span(rich(what)),
              span(rich(why)),
              if (flag != null)
                code(classes: DocsTable.flag.name, [.text(flag)])
              else
                span(classes: Utility.muted.name, const [.text('—')]),
            ],
        ],
      ),
      p(
        rich(
          'The variants of a conditional import, like `io.dart` and `web.dart` '
          "in `import 'io.dart' if (dart.library.js_interop) 'web.dart';`, are "
          'checked together: a public declaration shares the references of its '
          'namesakes in the other variants, and is reported and removed only '
          'with them. A variant whose other variant is not scanned is not '
          'checked.',
        ),
      ),
      p(
        rich(
          'Private constructors are not skipped: an unused `ClassName._` is '
          'dead code like any other. A sole `ClassName._()` with no '
          'parameters, the classic prevent-instantiation marker, comes with a '
          'hint suggesting `abstract final class` instead.',
        ),
      ),
      const h3([.text('Entry points')]),
      p(
        rich(
          'Some declarations are only called from code a tool generates, so '
          'nothing in the package references them: `flutter test` runs '
          '`testExecutable`, flutter_tools calls `MyPlugin.registerWith()`. '
          'ciach knows about `main` and `testExecutable`, and reads these from '
          "the project's own config files:",
        ),
      ),
      docsTable(
        columns: const ['Source', 'Entry point'],
        rows: [
          for (final (source, entryPoint) in _entryPoints)
            [span(rich(source)), span(rich(entryPoint))],
        ],
      ),
      p(
        rich(
          'List any other entry points under `entry-points:` in `ciach.yaml`:',
        ),
      ),
      const CodeBlock(
        source: _entryPointsConfig,
        language: .yaml,
        title: 'ciach.yaml',
      ),
      p(
        rich(
          'A matching declaration is neither reported nor removed. A member '
          "rule also keeps its type, while the type's other members are still "
          'checked. A rule that names a class or extension type also keeps its '
          'unnamed constructor, but not its named ones. Name a constructor the '
          'way the report does: `MyWidget.new` or `MyWidget.named`. `-v` names '
          'each skipped entry point.',
        ),
      ),
      const h3([.text('Ignore markers')]),
      p(
        rich(
          'A `// ciach:ignore` comment keeps a declaration from being reported or removed:',
        ),
      ),
      const CodeBlock(source: _markers, language: .dart, copyText: ''),
      p(
        rich(
          '`// ciach:ignore-file` anywhere in a file keeps the whole file: '
          'ciach still counts the uses of other code in it, but reports and '
          'changes nothing in it.',
        ),
      ),
      p(
        rich(
          'Any declaration can be marked, enum values and constructors '
          "included. Marking a member also keeps its type, while the type's "
          'other members are still checked. Free text may follow a marker, as '
          'a reason. Only `//` comments count: a marker in a doc comment, a '
          'block comment or a string does nothing. ciach warns about a marker '
          'that keeps nothing, an unclosed range, and an unknown `// ciach:` '
          'word, and `-v` names each kept declaration.',
        ),
      ),
      const h3([.text('Generated files')]),
      const p([
        .text(
          'Besides files named like generated code or carrying a generated-code banner, ciach treats these as generated:',
        ),
      ]),
      ul(classes: Prose.checklist.name, [
        li(
          rich(
            'The files build_runner writes into the source tree, read from the '
            'outputs the applied builders declare in `build.yaml` and every '
            '`build.<name>.yaml`.',
          ),
        ),
        li(
          rich(
            'The files `flutter gen-l10n` writes, as `l10n.yaml` configures '
            'them. The template file is scanned instead, and its unused '
            'messages reported; `--no-unused-translations` treats it as '
            'generated too.',
          ),
        ),
        li(
          rich(
            'The `firebase_options*.dart` files `flutterfire configure` writes, as `firebase.json` records them.',
          ),
        ),
      ]),
      const p([
        .text(
          'Every package under the scanned path is read from its own files, so '
          'scanning the root of a pub workspace or monorepo covers all of its '
          'members.',
        ),
      ]),
    ],
  );
}
