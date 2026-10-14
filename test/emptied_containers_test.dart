@Timeout(Duration(minutes: 5))
library;

import 'dart:io';

import 'package:ciach/ciach.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/package_config.dart';

/// Classes, mixins and extensions whose members are all unused but that other
/// code still uses: the finder lists those that `--remove` leaves empty.
void main() {
  late Directory root;

  setUpAll(() {
    root = .systemTemp.createTempSync('ciach_emptied_containers_');
    void write(String path, String contents) => File(p.join(root.path, path))
      ..createSync(recursive: true)
      ..writeAsStringSync(contents);
    write('.dart_tool/package_config.json', packageConfig({'shapes': '.'}));
    write('pubspec.yaml', '''
name: shapes
environment: {sdk: ^3.13.0}
''');
    write('lib/shapes.dart', '''
mixin Painter {
  int paint() => 1;
}

class Tile with Painter {}

class Canvas {
  int paint() => 1;
  int erase() => 0;
}

extension Parsing on String {
  // Parses nothing.
  int paint() => 1;
}

extension type Wrapped(int value) {
  int doubled() => value * 2;
}

class Point(final int x) {
  int moved() => x + 1;
}

class Dead {
  int paint() => 1;
}
''');
    write('bin/main.dart', '''
import 'package:shapes/shapes.dart';

void main() {
  print([Tile() is Painter, Canvas().erase(), Wrapped(1).value, Point(1).x]);
}
''');
  });

  tearDownAll(() => root.deleteSync(recursive: true));

  test('lists the containers --remove leaves empty', () async {
    final result = await Ciach(
      .new(rootPath: root.path, exportedPackages: const []),
    ).run();

    expect(result.unused.map((d) => d.qualifiedName), [
      'Painter.paint',
      'Canvas.paint',
      'Parsing',
      'Wrapped.doubled',
      'Point.moved',
      'Dead',
      'Dead.paint',
    ]);
    // Canvas keeps erase, and Wrapped and Point keep the fields their headers
    // declare. Dead is removed whole, and so is Parsing, which nothing names.
    expect(result.emptiedContainers, [
      (filePath: 'lib/shapes.dart', name: 'Painter'),
    ]);
  });
}
