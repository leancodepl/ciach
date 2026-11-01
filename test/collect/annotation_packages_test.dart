/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

@Timeout(Duration(minutes: 5))
library;

import 'dart:io';

import 'package:ciach/src/collect/annotation_packages.dart';
import 'package:ciach/src/lsp/lsp_client.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/package_config.dart';

void main() {
  late Directory tempDir;
  late LspClient client;

  setUpAll(() async {
    tempDir = .systemTemp.createTempSync('ciach_annotation_packages_');
    File(p.join(tempDir.path, '.dart_tool', 'package_config.json'))
      ..createSync(recursive: true)
      ..writeAsStringSync(packageConfig({'app': '.'}));
    File(p.join(tempDir.path, 'lib', 'local.dart'))
      ..createSync(recursive: true)
      ..writeAsStringSync('''
class JSExport {
  const JSExport();
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

  test(
    'resolves the package of each annotation that a rule names, and of no other',
    () async {
      const source = '''
import 'dart:core' as core;
import 'dart:js_interop' as js;
import 'local.dart' as local;

@core.pragma('vm:entry-point') void a() {}
@js.JSExport() class B {}
@local.JSExport() class C {}
@core.Deprecated('x') void d() {}
''';
      final path = p.join(tempDir.path, 'lib', 'uses.dart');
      File(path).writeAsStringSync(source);
      client.didOpen(File(path).uri, source);
      final tokens = await client.semanticTokens(
        File(path).uri,
        source.split('\n'),
      );
      final packages = AnnotationPackages(.new(const []));

      await packages.resolve(client, path, 'lib/uses.dart', tokens);

      expect(
        {
          for (final (line, _) in source.split('\n').indexed)
            line: packages
                .packagesOf(path, tokens.where((token) => token.line == line))
                .values,
        },
        {
          0: isEmpty,
          1: isEmpty,
          2: isEmpty,
          3: isEmpty,
          4: ['dart:core'],
          5: ['dart:js_interop'],
          6: ['app'],
          7: isEmpty,
          8: isEmpty,
        },
      );
    },
  );
}
