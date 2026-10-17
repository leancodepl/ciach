/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

@Timeout(Duration(minutes: 5))
library;

import 'dart:io';

import 'package:ciach/src/collect/exposed_types.dart';
import 'package:ciach/src/lsp/lsp_client.dart';
import 'package:ciach/src/source/source_index.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Reads which private types a public declaration exposes, as the analysis
/// server shows the library.
void main() {
  late Directory tempDir;
  late LspClient client;
  var libraries = 0;

  setUpAll(() async {
    tempDir = .systemTemp.createTempSync('ciach_exposed_');
    client = await LspClient.start();
    await client.initialize(tempDir.uri);
    await client.waitForAnalysisComplete();
  });

  tearDownAll(() async {
    await client.dispose();
    tempDir.deleteSync(recursive: true);
  });

  /// Writes [files], by name, into a new directory, opens them in the server,
  /// and returns what `ExposedTypes.of` reads for the first of them.
  Future<Map<String, ExposedMembers>> exposedIn(
    Map<String, String> files,
  ) async {
    final dir = Directory(p.join(tempDir.path, 'lib${libraries++}'))
      ..createSync();
    final sources = {
      for (final MapEntry(key: name, value: source) in files.entries)
        p.join(dir.path, name): source,
    };
    for (final MapEntry(key: path, value: source) in sources.entries) {
      File(path).writeAsStringSync(source);
      client.didOpen(File(path).uri, source);
    }
    final library = sources.keys.first;
    final unit = await client.outline(File(library).uri);
    return await ExposedTypes(client, SourceIndex()).of(library, unit);
  }

  test('a supertype of a public class exposes its instance members', () async {
    expect(
      await exposedIn({
        'a.dart': '''
class _Root {}
class _Base extends _Root {}
class Circle extends _Base {}
''',
      }),
      {'_Root': ExposedMembers.instance, '_Base': ExposedMembers.instance},
    );
  });

  test('a type alias of a class or an enum exposes all its members', () async {
    expect(
      await exposedIn({
        'a.dart': '''
class _Aliased {}
enum _Level { low }
typedef Alias = _Aliased;
typedef Level = _Level;
''',
      }),
      {'_Aliased': ExposedMembers.all, '_Level': ExposedMembers.all},
    );
  });

  test(
    'a type alias that names the type only as a type argument exposes its instance members',
    () async {
      expect(
        await exposedIn({
          'a.dart': '''
class _Crate {}
class _Visited {}
typedef Stock = List<_Crate>;
typedef Visit = void Function(_Visited);
''',
        }),
        {
          '_Crate': ExposedMembers.instance,
          '_Visited': ExposedMembers.instance,
        },
      );
    },
  );

  test(
    'a public function exposes its return type, and that type its getter type',
    () async {
      expect(
        await exposedIn({
          'a.dart': '''
_Tool makeTool() => _Tool();
class _Tool {
  _Part get part => _Part();
  _Hidden get _hidden => _Hidden();
}
class _Part {}
class _Hidden {}
''',
        }),
        {'_Tool': ExposedMembers.instance, '_Part': ExposedMembers.instance},
      );
    },
  );

  test('a public variable exposes the types of its inferred type', () async {
    expect(
      await exposedIn({
        'a.dart': '''
final items = [_Item()];
class _Item {}
''',
      }),
      {'_Item': ExposedMembers.instance},
    );
  });

  test(
    'a bound exposes a type only when the class uses its type parameter',
    () async {
      expect(
        await exposedIn({
          'a.dart': '''
class _Unused {}
class _Held {}
class Circle<T extends _Unused> {}
class Holder<T extends _Held> {
  T? held;
}
''',
        }),
        {'_Held': ExposedMembers.instance},
      );
    },
  );

  test('a concrete class exposes the types that it implements, and an '
      'extension does not expose its `on` type', () async {
    expect(
      await exposedIn({
        'a.dart': '''
class _Gauge {
  void calibrate() {}
}
class Ruler implements _Gauge {
  @override
  void calibrate() {}
}
class _Extended {}
extension Doubling on _Extended {}
''',
      }),
      {'_Gauge': ExposedMembers.instance},
    );
  });

  test('a body and a private declaration expose nothing', () async {
    expect(
      await exposedIn({
        'a.dart': '''
void run() => _InBody();
_Private _make() => _Private();
class _InBody {}
class _Private {}
''',
      }),
      isEmpty,
    );
  });

  test('a subtype in a part file exposes a type of the library', () async {
    expect(
      await exposedIn({
        'a.dart': '''
part 'a_part.dart';
class _InPart {}
''',
        'a_part.dart': '''
part of 'a.dart';
class FromPart extends _InPart {}
''',
      }),
      {'_InPart': ExposedMembers.instance},
    );
  });

  test(
    'every private type is exposed in full when the library is unknown',
    () async {
      expect(
        await exposedIn({
          'a.dart': '''
part of 'b.dart';
class _Kept {}
''',
          'b.dart': "part of 'a.dart';",
        }),
        {'_Kept': ExposedMembers.all},
      );
    },
  );
}
