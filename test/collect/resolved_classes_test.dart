/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

@Timeout(Duration(minutes: 5))
library;

import 'dart:io';

import 'package:ciach/src/collect/resolved_classes.dart';
import 'package:ciach/src/conventions/entry_points.dart';
import 'package:ciach/src/conventions/resolved_declaration.dart';
import 'package:ciach/src/lsp/lsp_client.dart';
import 'package:path/path.dart' as p;
import 'package:pro_lsp/pro_lsp.dart' show DocumentSymbol;
import 'package:test/test.dart';

import '../support/package_config.dart';

void main() {
  late Directory tempDir;
  late LspClient client;

  setUpAll(() async {
    tempDir = .systemTemp.createTempSync('ciach_resolved_classes_');
    File(p.join(tempDir.path, '.dart_tool', 'package_config.json'))
      ..createSync(recursive: true)
      ..writeAsStringSync(packageConfig({'app': '.'}));
    File(p.join(tempDir.path, 'lib', 'previews.dart'))
      ..createSync(recursive: true)
      ..writeAsStringSync('''
class Preview {
  const Preview();
}

class DarkPreview extends Preview {
  const DarkPreview();
}
''');
    client = await LspClient.start();
    await client.initialize(tempDir.uri);
    await client.waitForAnalysisComplete();
  });

  tearDownAll(() async {
    await client.dispose();
    tempDir.deleteSync(recursive: true);
  });

  /// Writes [source] to a file in the package, resolves it for [rules], and
  /// returns the file's path and its document symbols with what
  /// [ResolvedClasses] made of them.
  Future<({String path, List<DocumentSymbol> symbols, ResolvedClasses classes})>
  resolve(String source, List<EntryPoint> rules) async {
    final path = p.join(tempDir.path, 'lib', 'uses.dart');
    File(path).writeAsStringSync(source);
    client.didOpen(File(path).uri, source);
    final tokens = await client.semanticTokens(
      File(path).uri,
      source.split('\n'),
    );
    final symbols = await client.documentSymbol(File(path).uri);
    final classes = ResolvedClasses(.new(rules));
    await classes.resolve(client, path, 'lib/uses.dart', tokens, symbols);
    return (path: path, symbols: symbols, classes: classes);
  }

  const object = ResolvedClass('Object', null);
  ResolvedClass app(String name) => .new(name, 'app');

  test(
    'resolves the supertypes of each class with an `extends`, `with` or `implements` clause or a bound, and none of a class without one',
    () async {
      final (:path, :symbols, classes: resolved) = await resolve(
        '''
import 'previews.dart';

class Shown extends DarkPreview {
  const Shown();
}

class Implementing implements Preview {}

mixin Themed {}

class Mixing with Themed {}

class Bounded<T extends num> {}

class Plain {}

void notAClass() {}
''',
        [.publicMethodsOfSubclasses('Preview', reason: 'called')],
      );

      expect(
        {
          for (final symbol in symbols)
            symbol.name: resolved.supertypesOf(path, symbol),
        },
        {
          'Shown': {app('DarkPreview'), app('Preview'), object},
          'Implementing': {app('Preview'), object},
          'Themed': isEmpty,
          'Mixing': {app('Themed'), object},
          'Bounded': {object},
          'Plain': isEmpty,
          'notAClass': isEmpty,
        },
      );
    },
  );
}
