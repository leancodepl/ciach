/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

@Timeout(Duration(minutes: 5))
library;

import 'dart:io';

import 'package:ciach/src/finder.dart';
import 'package:ciach/src/project_config/project_config.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/package_config.dart';

void main() {
  test(
    'keeps what Pigeon reads from an input file, and reports what it skips',
    () async {
      final root = Directory.systemTemp.createTempSync('ciach_pigeon_');
      addTearDown(() => root.deleteSync(recursive: true));
      void write(String path, String contents) => File(p.join(root.path, path))
        ..createSync(recursive: true)
        ..writeAsStringSync(contents);
      // A stand-in for the library of Pigeon that declares the annotations.
      write('pigeon/lib/pigeon.dart', '''
class ConfigurePigeon {
  const ConfigurePigeon(this.options);
  final PigeonOptions options;
}

class PigeonOptions {
  const PigeonOptions({this.dartOut});
  final String? dartOut;
}

class HostApi {
  const HostApi();
}

class FlutterApi {
  const FlutterApi();
}
''');
      write(
        'app/.dart_tool/package_config.json',
        packageConfig({'app': '.', 'pigeon': '../pigeon'}),
      );
      write('app/pubspec.yaml', '''
name: app
environment: {sdk: ^3.13.0}
dev_dependencies:
  pigeon: any
''');
      write('app/pigeons/messages.dart', '''
import 'package:pigeon/pigeon.dart';

// What Pigeon reads.

@ConfigurePigeon(PigeonOptions(dartOut: 'lib/src/messages.g.dart'))
class Message {
  String? text;
  Priority? priority;
}

class Unreferenced {
  int? count;
}

enum Priority { low, high }

const int version = 1;

@HostApi()
abstract class MessageApi {
  void send(Message message);
}

@FlutterApi()
abstract class MessageListener {
  void onMessage(Message message);
}

// What Pigeon skips.

abstract class NotAnApi {
  void call();
}

final int notAConstant = 2;

void helper() {}

mixin Helpers {}

typedef Alias = Message;

extension MessageText on Message {
  bool get isEmpty => text?.isEmpty ?? true;
}
''');
      write('app/lib/app.dart', '''
class Unused {}
''');

      final appPath = p.join(root.path, 'app');
      final result = await Ciach(
        .new(
          rootPath: appPath,
          entryPoints: ProjectConfig.read(appPath).entryPoints,
        ),
      ).run();

      expect(result.unused.map((d) => d.qualifiedName).toSet(), {
        'NotAnApi',
        'notAConstant',
        'helper',
        'Helpers',
        'Alias',
        'MessageText',
        'Unused',
      });
    },
  );
}
