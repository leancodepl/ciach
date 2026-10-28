/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

@Timeout(Duration(minutes: 5))
library;

import 'dart:io';

import 'package:ciach/src/collect/annotation_types.dart';
import 'package:ciach/src/conventions/entry_points.dart';
import 'package:ciach/src/lsp/lsp_client.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/package_config.dart';

void main() {
  late Directory tempDir;
  late LspClient client;

  setUpAll(() async {
    tempDir = .systemTemp.createTempSync('ciach_annotation_types_');
    File(p.join(tempDir.path, '.dart_tool', 'package_config.json'))
      ..createSync(recursive: true)
      ..writeAsStringSync(packageConfig({'app': '.'}));
    File(p.join(tempDir.path, 'lib', 'previews.dart'))
      ..createSync(recursive: true)
      ..writeAsStringSync('''
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

class Typed<T> extends Preview {
  const Typed();
}

typedef AliasPreview = DarkPreview;

typedef AliasOfAlias = AliasPreview;

typedef AliasTyped<T extends Object> = Typed<T>;
''');
    client = await LspClient.start();
    await client.initialize(tempDir.uri);
    await client.waitForAnalysisComplete();
  });

  tearDownAll(() async {
    await client.dispose();
    tempDir.deleteSync(recursive: true);
  });

  /// Returns the classes that [AnnotationTypes.of] gives for the annotation
  /// on each line of [source], by line.
  Future<Map<int, Set<AnnotationClass>>> typesByLine(String source) async {
    final path = p.join(tempDir.path, 'lib', 'uses.dart');
    File(path).writeAsStringSync(source);
    client.didOpen(File(path).uri, source);
    final tokens = await client.semanticTokens(
      File(path).uri,
      source.split('\n'),
    );
    final types = AnnotationTypes(.new());
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
@Typed<int>() void i() {}
@AliasPreview() void j() {}
@previews.AliasOfAlias() void k() {}
@AliasTyped<int>() void l() {}
@Typed<AliasPreview>() void m() {}
''');

      const object = AnnotationClass('Object', null);
      AnnotationClass app(String name) =>
          .new(name, .parse('package:app/previews.dart'));
      expect(types, {
        0: isEmpty,
        1: isEmpty,
        2: isEmpty,
        3: {app('Preview'), object},
        4: {app('DarkPreview'), app('Preview'), object},
        5: {
          app('ThemedPreview'),
          app('Themed'),
          app('DarkPreview'),
          app('Preview'),
          object,
        },
        6: {app('DarkPreview'), app('Preview'), object},
        7: {app('Preview'), object},
        // An annotation that reads a constant calls no constructor.
        8: isEmpty,
        9: isEmpty,
        10: isEmpty,
        // The name of a generic class has no type parameters.
        11: {app('Typed'), app('Preview'), object},
        // A typedef stands for the class that it names.
        12: {app('DarkPreview'), app('Preview'), object},
        13: {app('DarkPreview'), app('Preview'), object},
        14: {app('Typed'), app('Preview'), object},
        // A typedef in the type arguments is not the annotation's class.
        15: {app('Typed'), app('Preview'), object},
        16: isEmpty,
      });
    },
  );
}
