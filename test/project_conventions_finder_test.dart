@Timeout(Duration(minutes: 5))
library;

import 'dart:io';

import 'package:ciach/ciach.dart';
import 'package:ciach/src/log.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  // Unresolved: local `Endpoint`/`JSExport` match by name.
  late Directory package;

  void write(String path, String contents) => File(p.join(package.path, path))
    ..createSync(recursive: true)
    ..writeAsStringSync(contents);

  setUp(() {
    package = .systemTemp.createTempSync('ciach_project_conventions_');
    write('pubspec.yaml', '''
name: server
environment:
  sdk: ^3.10.0
dependencies:
  dart_frog: any
  serverpod: any
''');
    write('build.yaml', '''
builders:
  stamp:
    import: "package:server/builder.dart"
    builder_factories: ["stampBuilder"]
    build_extensions: {".dart": [".stamp.dart"]}
    auto_apply: root_package
    build_to: source
''');
    write('l10n.yaml', '''
arb-dir: lib/l10n
output-localization-file: strings.dart
''');
    write('lib/endpoint.dart', '''
class Endpoint {}

class Session {}

class GreetingEndpoint extends Endpoint {
  Future<String> hello(Session session, String name) async => _greet(name);

  String _greet(String name) => name;

  void _unusedHelper() {}
}

class NotAnEndpoint {
  void hello() {}
}
''');
    write('lib/builder.dart', '''
Object stampBuilder(Object options) => options;

Object unusedBuilderHelper() => 0;
''');
    write('lib/model.stamp.dart', '''
class StampOutput {}
''');
    write('lib/l10n/strings.dart', '''
abstract class Strings {
  String get unusedMessage;
}
''');
    write('lib/l10n/strings_pl.dart', '''
class StringsPl {}
''');
    write('lib/js.dart', '''
class JSExport {
  const JSExport();
}

@JSExport()
class Counter {
  int value = 0;

  void increment() => value++;

  void _neverCalled() {}
}

class Partial {
  @JSExport()
  void exported() {}

  void notExported() {}
}

void usePartial() => Partial();
''');
    write('test/reflective_test.dart', '''
const reflectiveTest = Object();

void defineReflectiveTests<T>() {}

void main() => defineReflectiveTests<ParserTest>();

@reflectiveTest
class ParserTest {
  void setUp() {}

  void test_parses() {}

  void solo_test_focused() {}

  void skip_test_later() {}

  void helper() {}
}
''');
    write('routes/index.dart', '''
Object onRequest(Object context) => context;

void unusedRouteHelper() {}
''');
    write('routes/admin/_middleware.dart', '''
Object middleware(Object handler) => handler;
''');
    write('main.dart', '''
Object init(Object ip, int port) => ip;

Object run(Object handler, Object ip, int port) => handler;
''');
  });

  tearDown(() => package.deleteSync(recursive: true));

  FinderOptions detected() {
    final conventions = ProjectConventions.read(package.path);
    return .new(
      rootPath: package.path,
      entryPoints: conventions.entryPoints,
      additionalGeneratedGlobs: conventions.generatedGlobs,
    );
  }

  test('declarations the project config names are not reported', () async {
    final result = await Ciach(detected()).run();

    expect(
      {for (final d in result.unused) '${d.filePath}:${d.qualifiedName}'},
      {
        'lib/endpoint.dart:GreetingEndpoint._unusedHelper',
        'lib/endpoint.dart:NotAnEndpoint',
        'lib/endpoint.dart:NotAnEndpoint.hello',
        'lib/builder.dart:unusedBuilderHelper',
        'lib/js.dart:Counter._neverCalled',
        'lib/js.dart:Partial.notExported',
        'lib/js.dart:usePartial',
        'test/reflective_test.dart:ParserTest.helper',
        'routes/index.dart:unusedRouteHelper',
      },
    );
  });

  test('without them, it is all reported', () async {
    final result = await Ciach(.new(rootPath: package.path)).run();
    final unused = {
      for (final d in result.unused) '${d.filePath}:${d.qualifiedName}',
    };

    expect(
      unused,
      containsAll([
        'lib/builder.dart:stampBuilder',
        'lib/endpoint.dart:GreetingEndpoint',
        'lib/model.stamp.dart:StampOutput',
        'lib/l10n/strings_pl.dart:StringsPl',
        'routes/index.dart:onRequest',
        'main.dart:init',
      ]),
    );
    expect(unused, isNot(contains('lib/js.dart:Counter')));
  });

  test('narrates what the project config declares', () async {
    final lines = <String>[];
    final level = Logger.root.level;
    Logger.root.level = .FINE;
    final logging = Logger.root.onRecord
        .where((r) => r.loggerName == 'ciach.finder')
        .listen((r) => lines.add(r.message));
    addTearDown(() {
      Logger.root.level = level;
      return logging.cancel();
    });

    await Ciach(detected()).run();

    const endpointMethod =
        'Skipped lib/endpoint.dart:6 GreetingEndpoint.hello: a Serverpod '
        'endpoint method, called by the generated dispatcher.';
    const jsExported =
        'Skipped lib/js.dart:6 Counter: exported to JavaScript by `@JSExport`.';
    const route =
        'Skipped routes/index.dart:1 onRequest: a dart_frog route handler.';
    expect(lines, containsAll(const [endpointMethod, jsExported, route]));
  });
}
