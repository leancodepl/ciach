import 'dart:io';

import 'package:ciach/src/conventions/entry_points.dart';
import 'package:ciach/src/finder.dart';
import 'package:ciach/src/finder_options.dart';
import 'package:ciach/src/models.dart';
import 'package:collection/collection.dart';
import 'package:path/path.dart' as p;
import 'package:pro_lsp/pro_lsp.dart' show SymbolKind;
import 'package:test/test.dart';

/// The example package doubles as the test fixture: a real `sample_pkg`
/// package with a known mix of used and unused declarations.
final fixturePath = p.join(Directory.current.path, 'example');

/// The scenario fixtures under lib/scenarios/ are scanned only by their
/// dedicated tests; a default run excludes them.
const scenarioGlobs = ['lib/scenarios/**'];

/// Resolves the fixture's dependencies once per test file, before its tests
/// run. The fixture is a real package; the analysis server needs its
/// package_config.json to resolve `package:sample_pkg/...` imports.
void setUpFixture() {
  setUpAll(_resolveFixturePackages);
}

Future<void> _resolveFixturePackages() async {
  final config = File(p.join(fixturePath, '.dart_tool', 'package_config.json'));
  if (config.existsSync()) {
    return;
  }
  // Test files run in parallel, so the `pub get` is serialized on a file
  // lock, and the next file in finds the config written.
  final lock = File(
    p.join(Directory.systemTemp.path, 'ciach_fixture_pub_get.lock'),
  ).openSync(mode: .write);
  try {
    lock.lockSync(FileLock.blockingExclusive);
    if (config.existsSync()) {
      return;
    }
    final result = await Process.run(Platform.resolvedExecutable, [
      'pub',
      'get',
    ], workingDirectory: fixturePath);
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
  } finally {
    lock
      ..unlockSync()
      ..closeSync();
  }
}

/// Runs the finder on the fixture.
Future<FinderResult> runFinder({
  bool includePublic = true,
  bool skipOverrides = true,
  bool skipOperators = true,
  Set<SymbolKind>? kinds,
  List<String> exclude = scenarioGlobs,
  List<String> include = const [],
  List<EntryPoint> entryPoints = const [],
  bool transitive = false,
}) => Ciach(
  .new(
    rootPath: fixturePath,
    includePublic: includePublic,
    skipOverrides: skipOverrides,
    skipOperators: skipOperators,
    kinds: kinds ?? FinderOptions.defaultKinds,
    excludeGlobs: exclude,
    includeGlobs: include,
    entryPoints: entryPoints,
    transitive: transitive,
  ),
).run();

/// Runs the finder on the scenario fixtures matching [include] alone.
/// Cross-file references still resolve, since the analysis server analyzes
/// the whole package regardless of the candidate filter.
Future<FinderResult> runScenario(
  List<String> include, {
  Set<SymbolKind>? kinds,
  List<EntryPoint> entryPoints = const [],
  bool transitive = false,
}) => runFinder(
  include: include,
  exclude: const [],
  kinds: kinds,
  entryPoints: entryPoints,
  transitive: transitive,
);

/// The qualified names of the unused declarations a run reports.
Future<Set<String>> findUnused({
  bool includePublic = true,
  bool skipOverrides = true,
  bool skipOperators = true,
  Set<SymbolKind>? kinds,
  List<String> exclude = scenarioGlobs,
  List<String> include = const [],
}) async {
  final result = await runFinder(
    includePublic: includePublic,
    skipOverrides: skipOverrides,
    skipOperators: skipOperators,
    kinds: kinds,
    exclude: exclude,
    include: include,
  );
  return qualifiedNames(result.unused);
}

/// The qualified names of the doc-only declarations a run reports.
Future<Set<String>> findDocOnly({bool includePublic = true}) async {
  final result = await runFinder(includePublic: includePublic);
  return qualifiedNames(result.docOnly);
}

/// The qualified names of [decls].
Set<String> qualifiedNames(Iterable<UnusedDeclaration> decls) =>
    decls.map((d) => d.qualifiedName).toSet();

/// The unused finding named [qualified], if any.
UnusedDeclaration? findByQualified(FinderResult result, String qualified) =>
    result.unused.firstWhereOrNull((d) => d.qualifiedName == qualified);

/// Copies [from] into [to], `.dart_tool` included.
void copyTree(Directory from, Directory to) {
  for (final entity in from.listSync(recursive: true, followLinks: false)) {
    final relative = p.relative(entity.path, from: from.path);
    final target = p.join(to.path, relative);
    if (entity is Directory) {
      Directory(target).createSync(recursive: true);
    } else if (entity is File) {
      File(target).parent.createSync(recursive: true);
      entity.copySync(target);
    }
  }
}
