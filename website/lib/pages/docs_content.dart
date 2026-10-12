/// The docs page's text: the code samples, the table of contents and the rows
/// of its tables. The README on GitHub stays the exhaustive reference.
abstract final class DocsContent {
  static const usage = r'''
$ dart install ciach
$ ciach                                  # current package
$ ciach path/to/package                  # another package
$ ciach --no-public -f json              # private-only, as JSON
$ ciach -f github --set-exit-if-changed  # CI: annotations, non-zero on finds
$ ciach --remove                         # delete findings, asks first''';

  static const workflow = '''
- run: dart pub get
- run: dart run ciach -f github --set-exit-if-changed''';

  static const config = '''
# ciach.yaml — every option, keyed by its long name minus the "--".
public: false                     # --no-public
exclude: ['test/**', 'tool/**']   # repeatable options take a list
kinds: [class, function, method]
format: github
set-exit-if-changed: true''';

  static const docOnly = '''
lib/greeting.dart
  15:6  function  danglingFunction  (public)

Referenced only from doc comments (1) · not counted, never removed
lib/greeting.dart
  40:6  function  docOnlyMentioned  (public)''';

  static const library = r'''
import 'package:ciach/ciach.dart';

final result = await Ciach(
  FinderOptions(rootPath: 'path/to/package', includePublic: false),
).run();

for (final decl in result.unused) {
  print('${decl.filePath}:${decl.line} ${decl.qualifiedName}');
}''';

  /// Each section's id and the label the table of contents shows for it.
  static const toc = [
    ('install', 'Install'),
    ('options', 'Options'),
    ('ci', 'CI'),
    ('config', 'Configuration'),
    ('compared', 'vs. the analyzer'),
    ('removing', 'Removing'),
    ('skips', 'Skips and limits'),
    ('library', 'Library API'),
    ('faq', 'FAQ'),
  ];

  /// Each flag and what it does.
  static const options = [
    ('--no-public', 'Report private declarations only. Cheapest mode.'),
    (
      '--no-exported',
      'Skip what other packages can import. The right one for library packages.',
    ),
    (
      '--remove, --force',
      'Delete what was found after confirming. `--force` skips the prompt.',
    ),
    ('-f text|json|github', 'Output format.'),
    (
      '--set-exit-if-changed',
      'Exit 1 when anything is found. Add `--no-fail-public` to count only private findings.',
    ),
    (
      '-k, --kinds',
      'Restrict to declaration kinds, e.g. `class,function,method`.',
    ),
    (
      '-i, -e',
      'Include or exclude file globs. References are still counted from everywhere.',
    ),
    (
      '--analysis-root',
      'Count references from a whole monorepo, not just the scanned package. What is scanned and removed is unchanged.',
    ),
    (
      '--transitive',
      'Also report what only other findings reference, and dead cycles.',
    ),
    (
      '--overrides, --operators, --generated, --report-tojson',
      'Opt back into a category skipped by default.',
    ),
    ('-v', 'Narrate the run on stderr with timings.'),
  ];

  /// Each capability, and whether `dart analyze` and ciach have it.
  static const comparison = [
    ('Unused private declarations', true, true),
    ('Unused public declarations', false, true),
    ('References followed across libraries', false, true),
    ('Removes what it finds', false, true),
    ('GitHub annotations on the pull request', false, true),
    ('JSON output', true, true),
  ];

  /// Each default skip, why, and the flag that opts back in, if any.
  static const skips = [
    ('main', 'The entry point is never unused.', null),
    (
      'testExecutable in flutter_test_config.dart',
      'Called by the `flutter test` bootstrap.',
      null,
    ),
    (
      'Entry points declared in project config files',
      'Builder factories from build.yaml, plugin classes from pubspec.yaml, dart_frog routes and Serverpod endpoints. List more under `entry-points:` in ciach.yaml.',
      null,
    ),
    (
      '@override members',
      'Reached polymorphically or by a framework.',
      '--overrides',
    ),
    (
      'Operator overloads',
      'The server does not resolve `a + b` to the declaration.',
      '--operators',
    ),
    (
      'call methods',
      'Implicit-call syntax `obj(…)` is unresolvable the same way.',
      null,
    ),
    (
      "@pragma('vm:entry-point'), @JSExport, @reflectiveTest",
      'Reachable from native code, reflection or JavaScript.',
      null,
    ),
    (
      'Generated files',
      'Recognized by file name, by a generated-code banner, from build.yaml and l10n.yaml, or by `--generated-glob`. They are still opened for analysis.',
      '--generated',
    ),
    (
      'toJson()',
      '`jsonEncode(obj)` calls it by dynamic dispatch.',
      '--report-tojson',
    ),
    (
      'dartdoc [Xxx] links',
      'Not a code reference; reported as doc-only.',
      null,
    ),
  ];

  /// The findings `--remove` reports but leaves in place.
  static const reportOnly = [
    'A sealed member matched only by type patterns (`--unused-union-members`).',
    'Every value of a still-referenced enum.',
    'The sole constructor of a live class with final fields or super forwarding.',
    'A primary constructor or its declaring parameters.',
  ];
}
