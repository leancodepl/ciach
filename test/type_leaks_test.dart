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
    root = .systemTemp.createTempSync('ciach_type_leaks_');
    write('pubspec.yaml', 'name: leaks\nenvironment:\n  sdk: ^3.10.0\n');
    write(
      '.dart_tool/package_config.json',
      '{\n  "configVersion": 2,\n  "packages": [\n'
          '    { "name": "leaks", "rootUri": "../", "packageUri": "lib/", '
          '"languageVersion": "3.10" }\n  ]\n}\n',
    );
    write('lib/leaks.dart', "export 'src/api.dart';");
    write('lib/src/api.dart', '''
import 'types.dart';

Client createClient() => Client();
void listen(void Function(Callback) f) {}
Future<List<Generic>> generics() async => [];
class Exported extends Base {}
final inferred = Inferred();
Carrier makeCarrier() => Carrier();
Wrapper makeWrapper() => Wrapper(1);

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

  Future<Set<String>> deadMembers({required bool includeExported}) async {
    final result = await Ciach(
      FinderOptions(rootPath: root.path, includeExported: includeExported),
    ).run();
    return {
      for (final decl in result.unused)
        if (decl.container != null) decl.qualifiedName,
    };
  }

  test('every member under test is dead', () async {
    expect(await deadMembers(includeExported: true), {
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
      'DocOnly.docOnlyDead',
      'BodyOnly.bodyOnlyDead',
      'Hidden.hiddenDead',
      'Deep.deepDead',
      'Helper.helperDead',
    });
  });

  test('members of a type reachable from another package are kept', () async {
    expect(await deadMembers(includeExported: false), {
      'DocOnly.docOnlyDead',
      'BodyOnly.bodyOnlyDead',
      'Hidden.hiddenDead',
      'Deep.deepDead',
      'Helper.helperDead',
    });
  });
}
