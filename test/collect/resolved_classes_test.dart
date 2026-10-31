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
import 'package:ciach/src/lsp/semantic_tokens.dart';
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

const sameAsPreview = preview;

const heldPreview = Holder.held;

const previewList = [Preview()];

class Typed<T> extends Preview {
  const Typed();
}

typedef AliasPreview = DarkPreview;

typedef AliasOfAlias = AliasPreview;

typedef AliasTyped<T extends Object> = Typed<T>;

class Holder {
  static const held = DarkPreview();
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
  /// returns the file's path and its document symbols and semantic tokens
  /// with what [ResolvedClasses] made of them.
  Future<
    ({
      String path,
      List<DocumentSymbol> symbols,
      List<SemanticToken> tokens,
      ResolvedClasses classes,
    })
  >
  resolve(String source, List<EntryPoint> rules) async {
    final path = p.join(tempDir.path, 'lib', 'uses.dart');
    File(path).writeAsStringSync(source);
    client.didOpen(File(path).uri, source);
    final tokens = await client.semanticTokens(
      File(path).uri,
      source.split('\n'),
    );
    final symbols = await client.documentSymbol(File(path).uri);
    final classes = ResolvedClasses(.new(), .new(rules));
    await classes.resolve(client, path, 'lib/uses.dart', tokens, symbols);
    return (path: path, symbols: symbols, tokens: tokens, classes: classes);
  }

  const object = ResolvedClass('Object', null);
  ResolvedClass app(String name) => .new(name, 'app');

  /// An annotation that creates a [type] from the package `app`, whose
  /// supertypes are [supertypes] and `Object`.
  ResolvedAnnotation annotation(String type, List<String> supertypes) => .new(
    app(type),
    {for (final supertype in supertypes) app(supertype), object},
  );

  final rule = EntryPoint.annotatedWith('Preview', reason: 'shown');

  test(
    'resolves the class of each annotation that calls a constructor, with all its supertypes, and of no annotation that reads a constant',
    () async {
      const source = '''
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
@Holder.held void n() {}
@previews.preview void o() {}
@sameAsPreview void p() {}
@heldPreview void q() {}
@previewList void r() {}
@previews.Preview.named() void s() {}
@previews.Holder.held void t() {}
''';
      final (:path, :tokens, :classes, symbols: _) = await resolve(source, [
        rule,
      ]);

      expect(
        {
          for (final (line, _) in source.split('\n').indexed)
            line: classes.annotationsOf(
              path,
              tokens.where((token) => token.line == line),
            ),
        },
        {
          0: isEmpty,
          1: isEmpty,
          2: isEmpty,
          3: [annotation('Preview', [])],
          4: [
            annotation('DarkPreview', ['Preview']),
          ],
          5: [
            annotation('ThemedPreview', ['Themed', 'DarkPreview', 'Preview']),
          ],
          6: [
            annotation('DarkPreview', ['Preview']),
          ],
          7: [annotation('Preview', [])],
          8: isEmpty,
          9: isEmpty,
          10: isEmpty,
          // The name of a generic class has no type parameters.
          11: [
            annotation('Typed', ['Preview']),
          ],
          // A typedef stands for the class that it names.
          12: [
            annotation('DarkPreview', ['Preview']),
          ],
          13: [
            annotation('DarkPreview', ['Preview']),
          ],
          14: [
            annotation('Typed', ['Preview']),
          ],
          // A typedef in the type arguments is not the annotation's class.
          15: [
            annotation('Typed', ['Preview']),
          ],
          // A static constant, not a constructor of `Holder`.
          16: isEmpty,
          17: isEmpty,
          18: isEmpty,
          19: isEmpty,
          20: isEmpty,
          // A named constructor of a prefixed class.
          21: [annotation('Preview', [])],
          // A static constant of a prefixed class.
          22: isEmpty,
          23: isEmpty,
        },
      );
    },
  );

  test(
    'resolves the supertypes of each class with an `extends`, `with` or `implements` clause or a bound, and none of a class without one',
    () async {
      final (:path, :symbols, classes: resolved, tokens: _) = await resolve(
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
