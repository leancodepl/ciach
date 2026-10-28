/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

@Timeout(Duration(minutes: 5))
library;

import 'dart:io';

import 'package:ciach/src/collect/annotation_types.dart';
import 'package:ciach/src/lsp/lsp_client.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory tempDir;
  late LspClient client;

  setUpAll(() async {
    tempDir = .systemTemp.createTempSync('ciach_annotation_types_');
    File(p.join(tempDir.path, 'previews.dart')).writeAsStringSync('''
class Preview {
  const Preview();
  const Preview.named();
}

class DarkPreview extends Preview {
  const DarkPreview();
}

mixin Themed {}

class ThemedPreview with Themed implements DarkPreview {
  const ThemedPreview();
}

const preview = Preview();
''');
    client = await LspClient.start();
    await client.initialize(tempDir.uri);
    await client.waitForAnalysisComplete();
  });

  tearDownAll(() async {
    await client.dispose();
    tempDir.deleteSync(recursive: true);
  });

  /// Returns the class names that [AnnotationTypes.of] gives for the
  /// annotation on each line of [source], by line.
  Future<Map<int, Set<String>>> typesByLine(String source) async {
    final path = p.join(tempDir.path, 'uses.dart');
    File(path).writeAsStringSync(source);
    client.didOpen(File(path).uri, source);
    final tokens = await client.semanticTokens(
      File(path).uri,
      source.split('\n'),
    );
    final types = AnnotationTypes();
    await types.resolve(client, path, tokens);
    return {
      for (final (line, _) in source.split('\n').indexed)
        line: types.of(path, tokens.where((token) => token.line == line)),
    };
  }

  test(
    'resolves the class of each constructor-call annotation with all its supertypes',
    () async {
      final types = await typesByLine('''
import 'previews.dart';
import 'previews.dart' as previews;

@Preview() void a() {}
@DarkPreview() void b() {}
@ThemedPreview() void c() {}
@previews.DarkPreview() void d() {}
@Preview.named() void e() {}
@preview void f() {}
@override void g() {}
void h() {}
''');

      expect(types, {
        0: isEmpty,
        1: isEmpty,
        2: isEmpty,
        3: {'Preview', 'Object'},
        4: {'DarkPreview', 'Preview', 'Object'},
        5: {'ThemedPreview', 'Themed', 'DarkPreview', 'Preview', 'Object'},
        6: {'DarkPreview', 'Preview', 'Object'},
        7: {'Preview', 'Object'},
        // An annotation that reads a constant calls no constructor.
        8: isEmpty,
        9: isEmpty,
        10: isEmpty,
        11: isEmpty,
      });
    },
  );
}
