@Timeout(Duration(minutes: 5))
library;

import 'dart:io';

import 'package:ciach/src/finder.dart';
import 'package:ciach/src/models.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory root;

  void write(String path, String contents) => File(p.join(root.path, path))
    ..createSync(recursive: true)
    ..writeAsStringSync(contents);

  setUpAll(() {
    root = .systemTemp.createTempSync('ciach_exported_');
    write('pubspec.yaml', 'name: leaks\nenvironment:\n  sdk: ^3.10.0\n');
    write(
      '.dart_tool/package_config.json',
      '{\n  "configVersion": 2,\n  "packages": [\n'
          '    { "name": "leaks", "rootUri": "../", "packageUri": "lib/", '
          '"languageVersion": "3.10" }\n  ]\n}\n',
    );
    write('lib/leaks.dart', '''
export 'src/api.dart';

void publicTopLevel() {}
''');
    write('bin/main.dart', 'void main() {}\n\nvoid cliHelper() {}');
    write('lib/src/api.dart', '''
import 'types.dart';

Client createClient() => Client();
void listen(void Function(Callback) f) {}
Future<List<Generic>> generics() async => [];
class Exported extends Base {}
final inferred = Inferred();
Carrier makeCarrier() => Carrier();
Wrapper makeWrapper() => Wrapper(1);

void _private() => 1.privateUsed();

extension _PrivateExtension on int {
  void privateUsed() {}
  void privateExtensionDead() {}
}

/// Mentions [DocOnly], which hands nothing out.
void work() {
  final body = BodyOnly()..used();
  Hidden().deep.used();
}
''');
    write('lib/src/types.dart', '''
class Client {
  Config get config => Config();
  void clientDead() {}
}

class Config {
  Retry get retry => Retry();
  void configDead() {}
}

class Retry {
  void retryDead() {}
}

class Callback {
  void callbackDead() {}
}

class Generic {
  void genericDead() {}
}

class Base {
  void baseDead() {}
}

class Inferred {
  void inferredDead() {}
}

class Carrier {
  Carried get carried => Carried();
}

class Carried {
  void carriedDead() {}
}

extension type Wrapper(int value) {
  void wrapperDead() {}
}

class DocOnly {
  void docOnlyDead() {}
}

class BodyOnly {
  void used() {}
  void bodyOnlyDead() {}
}

class Hidden {
  Deep get deep => Deep();
  void hiddenDead() {}
}

class Deep {
  void used() {}
  void deepDead() {}
}

void notExported() => 1.used();

extension InternalExtension on int {
  void used() {}
  void extensionDead() {}
}
''');
    write('test/helper_test.dart', '''
class Helper {
  void used() {}
  void helperDead() {}
}

void main() => Helper().used();
''');
  });

  tearDownAll(() => root.deleteSync(recursive: true));

  Future<Set<String>> dead({required bool includeExported}) async {
    final result = await Ciach(
      FinderOptions(rootPath: root.path, includeExported: includeExported),
    ).run();
    return {for (final decl in result.unused) decl.qualifiedName};
  }

  const internal = {
    'DocOnly.docOnlyDead',
    'BodyOnly.bodyOnlyDead',
    'Hidden.hiddenDead',
    'Deep.deepDead',
    'Helper.helperDead',
    'InternalExtension.extensionDead',
    '_PrivateExtension.privateExtensionDead',
    'notExported',
    '_private',
    'cliHelper',
  };

  test('everything under test is dead', () async {
    expect(await dead(includeExported: true), {
      ...internal,
      'publicTopLevel',
      'createClient',
      'listen',
      'generics',
      'Exported',
      'inferred',
      'makeCarrier',
      'makeWrapper',
      'work',
      'Client.config',
      'Client.clientDead',
      'Config.retry',
      'Config.configDead',
      'Retry.retryDead',
      'Callback.callbackDead',
      'Generic.genericDead',
      'Base.baseDead',
      'Inferred.inferredDead',
      'Carrier.carried',
      'Carried.carriedDead',
      'Wrapper.wrapperDead',
    });
  });

  test('what another package can reach is kept', () async {
    expect(await dead(includeExported: false), internal);
  });
}
