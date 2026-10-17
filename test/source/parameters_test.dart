@Timeout(Duration(minutes: 5))
library;

import 'dart:io';

import 'package:ciach/ciach.dart';
import 'package:ciach/src/fetch/reference_fetch.dart';
import 'package:ciach/src/lsp/lsp_client.dart';
import 'package:ciach/src/lsp/outline.dart';
import 'package:ciach/src/source/parameters.dart';
import 'package:ciach/src/source/source_index.dart';
import 'package:path/path.dart' as p;
import 'package:pro_lsp/pro_lsp.dart' show Location, Position;
import 'package:test/test.dart';

/// Reads parameters, their reads and the calls of a function as the analysis
/// server sees them: its tokens, syntax nodes and outline.
void main() {
  late Directory tempDir;
  late LspClient client;
  var files = 0;

  setUpAll(() async {
    tempDir = .systemTemp.createTempSync('ciach_parameters_');
    client = await LspClient.start();
    await client.initialize(tempDir.uri);
    await client.waitForAnalysisComplete();
  });

  tearDownAll(() async {
    await client.dispose();
    tempDir.deleteSync(recursive: true);
  });

  /// Writes [source] to a new file, and returns it with its function, method
  /// or constructor named [name] and the selection ranges at its parameter
  /// declarations.
  Future<({String path, SourceIndex sources, Outline function})> index(
    String source,
    String name,
  ) async {
    final path = p.join(tempDir.path, 'lib${files++}.dart');
    File(path).writeAsStringSync(source);
    client.didOpen(File(path).uri, source);
    final sources = SourceIndex()..cacheLines(path, source.split('\n'));
    sources.cacheSemanticTokens(
      path,
      await semanticTokensOrEmpty(client, sources, path),
    );
    final function = (await client.outline(File(path).uri)).descendants
        .firstWhere(
          (node) =>
              node.element.name == name &&
              const {
                OutlineKind.function,
                OutlineKind.method,
                OutlineKind.constructor,
              }.contains(node.element.kind),
        );
    await ReferenceFetch(
      options: FinderOptions(rootPath: tempDir.path),
      sources: sources,
    ).fetchSelectionRanges(client, {
      path: {
        for (final token in sources.parameterDeclarations(path, function))
          token.start,
      },
    });
    return (path: path, sources: sources, function: function);
  }

  group('ownParameters', () {
    Future<List<String>> ownOf(String source, String name) async {
      final (:path, :sources, :function) = await index(source, name);
      return [
        for (final token in sources.ownParameters(path, function)) token.text,
      ];
    }

    test(
      'lists positional, optional and named parameters of a function',
      () async {
        expect(await ownOf('void f(int a, [int b = 0]) {}\n', 'f'), ['a', 'b']);
        expect(
          await ownOf('void f(int a, {int c = 1, required int d}) {}\n', 'f'),
          ['a', 'c', 'd'],
        );
      },
    );

    test('lists the parameters of a method and a named constructor', () async {
      const source = '''
class C {
  C.named(int a, this.b);
  final int b;
  void m(int x) {}
}
''';
      expect(await ownOf(source, 'C.named'), ['a']);
      expect(await ownOf(source, 'm'), ['x']);
    });

    test('leaves out the parameters of closures and function types inside', () {
      return expectLater(
        ownOf('''
void f(void Function(int inType) callback, int a) {
  [1].map((inClosure) => a);
}
''', 'f'),
        completion(['callback', 'a']),
      );
    });

    test(
      'leaves out `super.x` and the declaring parameters of a header',
      () async {
        const source = '''
class A(final int kept, int plain) {}
class B extends A {
  B(super.kept, super.plain, int own);
}
''';
        expect(await ownOf(source, 'A'), ['plain']);
        expect(await ownOf(source, 'B'), ['own']);
      },
    );
  });

  group('isRead', () {
    Future<bool> isReadIn(String source) async {
      final (:path, :sources, :function) = await index(source, 'f');
      return sources.isRead(
        path,
        function.codeRange,
        sources.ownParameters(path, function).first,
      );
    }

    test('is true for a read in the body', () {
      return expectLater(
        isReadIn('int f(int a) => a + 1;\n'),
        completion(isTrue),
      );
    });

    test('is false for a named argument of the same name', () {
      return expectLater(
        isReadIn('void f(int a) => g(a: 1);\nvoid g({int a = 0}) {}\n'),
        completion(isFalse),
      );
    });

    test('is true for a closure parameter of the same name', () {
      return expectLater(
        isReadIn('int f(int a) => [1].map((a) => a).length;\n'),
        completion(isTrue),
      );
    });
  });

  group('hasBody', () {
    Future<bool> hasBodyIn(String source, String name) async {
      final (:path, :sources, :function) = await index(source, name);
      final first = sources.ownParameters(path, function).first;
      return sources.hasBody(
        path,
        function,
        sources.parameterListOf(path, function, first)!,
      );
    }

    test('is true for a block, an empty block and an arrow body', () async {
      expect(await hasBodyIn('void f(int a) { print(1); }\n', 'f'), isTrue);
      expect(await hasBodyIn('void f(int a) {}\n', 'f'), isTrue);
      expect(await hasBodyIn('int f(int a) => 1;\n', 'f'), isTrue);
    });

    test('is false for an abstract method and an external function', () async {
      expect(
        await hasBodyIn('''
abstract class C {
  void m(int a);
}
''', 'm'),
        isFalse,
      );
      expect(await hasBodyIn('external void f(int a);\n', 'f'), isFalse);
    });
  });

  group('isCall', () {
    /// Returns, for each reference to [name] declared at [declaration] in
    /// [source], in source order, whether it is a call.
    Future<List<bool>> callsOf(
      String source,
      String name,
      Position declaration,
    ) async {
      final (:path, :sources, function: _) = await index(source, name);
      final uri = File(path).uri;
      final refs = await client.references(uri, declaration);
      final ranges = await client.selectionRanges(uri, [
        for (final ref in refs) ref.range.start,
      ]);
      for (final (i, ref) in refs.indexed) {
        sources.cacheSelectionRange(path, ref.range.start, ranges[i]!);
      }
      refs.sort((a, b) => a.range.start.line - b.range.start.line);
      return [for (final Location ref in refs) sources.isCall(ref)];
    }

    test('tells calls of a function from its tear-offs', () {
      return expectLater(
        callsOf(
          '''
void f(int a) {}
void use(List<int> xs) {
  f(1);
  f<Object?>;
  xs.forEach(f);
  (f)(1);
}
''',
          'f',
          const .new(line: 0, character: 5),
        ),
        completion([true, false, false, false]),
      );
    });

    test('tells calls of a method from its tear-offs', () {
      return expectLater(
        callsOf(
          '''
class C {
  void m(int a) {}
}
void use(C c, List<int> xs) {
  c.m(1);
  c..m(1);
  xs.forEach(c.m);
}
''',
          'm',
          const .new(line: 1, character: 7),
        ),
        completion([true, true, false]),
      );
    });

    test('tells calls of a constructor from its tear-offs', () {
      return expectLater(
        callsOf(
          '''
class C {
  C.named(int a);
}
void use() {
  C.named(1);
  final g = C.named;
}
''',
          'C.named',
          const .new(line: 1, character: 4),
        ),
        completion([true, false]),
      );
    });

    test('takes a generic call for a call', () {
      return expectLater(
        callsOf(
          '''
T f<T>(T a) => a;
void use() {
  f<int>(1);
}
''',
          'f',
          const .new(line: 0, character: 2),
        ),
        completion([true]),
      );
    });
  });
}
