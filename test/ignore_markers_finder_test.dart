@Timeout(Duration(minutes: 5))
library;

import 'dart:io';

import 'package:ciach/ciach.dart';
import 'package:ciach/src/log.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/package_config.dart';

/// A package whose declarations nothing calls, some of them kept by
/// `// ciach:` markers: on the line before, trailing, in a range, and for a
/// whole file.
void main() {
  late Directory package;

  void write(String path, String contents) => File(p.join(package.path, path))
    ..createSync(recursive: true)
    ..writeAsStringSync(contents);

  setUp(() {
    package = .systemTemp.createTempSync('ciach_ignore_markers_');
    write('pubspec.yaml', '''
name: markers
environment: {sdk: ^3.10.0}
''');
    write('.dart_tool/package_config.json', packageConfig({'markers': '.'}));
    write('lib/single.dart', '''
// ciach:ignore
void keptNextLine() {}

/// Documented.
// ciach:ignore
@Deprecated('Use something else.')
void keptAmongMetadata() {}

void keptTrailing() {} // ciach:ignore

void reported() {}

// ciach:ignore

void reportedAfterBlankLine() {}

class Catalog {
  // ciach:ignore
  void keptMember() {}

  void reportedMember() {}
}

const marker = '// ciach:ignore'; void reportedBesideString() {}

// ciach:ignroe
void reportedAfterTypo() {}
''');
    write('lib/range.dart', '''
void reportedBefore() {}

// ciach:ignore-start
void keptInRange() {}

class KeptInRange {
  void keptMember() {}
}
// ciach:ignore-end

void reportedAfter() {}
''');
    write('lib/ignored.dart', '''
// ciach:ignore-file
import 'helper.dart';

void keptInIgnoredFile() => helper();
''');
    write('lib/helper.dart', '''
/// Used only from the ignored file, which still counts.
void helper() {}
''');
  });

  tearDown(() => package.deleteSync(recursive: true));

  test('a marker keeps every declarator of a field statement', () async {
    write('lib/fields.dart', '''
abstract interface class Shape {
  int get a;
  int get b;
  int get c;
}

class Square implements Shape {
  @override
  final int a = 1, b = 2, c = 3;

  // ciach:ignore
  static int x = 1, y = 2, z = 3;
}

int area(Shape shape) => shape.a + shape.b + shape.c;

void main() => print(area(Square()));
''');

    final result = await Ciach(
      .new(rootPath: package.path, exportedPackages: const []),
    ).run();

    expect([
      for (final d in result.unused)
        if (d.filePath == 'lib/fields.dart') d.qualifiedName,
    ], isEmpty);
  });

  test('--remove keeps a marked override, and its dead member', () async {
    write('lib/hooks.dart', '''
abstract class Base {
  void hook() {}
}

class Impl extends Base {
  // ciach:ignore
  @override
  void hook() {}
}

void main() => print(Impl());
''');

    final result = await Ciach(
      .new(rootPath: package.path, exportedPackages: const []),
    ).run();
    final hook = result.unused.singleWhere(
      (d) => d.qualifiedName == 'Base.hook',
    );

    expect(hook.removalBlocked, isTrue);
  });

  test('marked declarations are not reported, and the log says why', () async {
    final lines = <String>[];
    final warnings = <String>[];
    final level = Logger.root.level;
    Logger.root.level = .FINE;
    final logging = Logger.root.onRecord
        .where((r) => r.loggerName == 'ciach.finder')
        .listen((r) => (r.level >= .WARNING ? warnings : lines).add(r.message));
    addTearDown(() {
      Logger.root.level = level;
      return logging.cancel();
    });

    final result = await Ciach(
      .new(rootPath: package.path, exportedPackages: const []),
    ).run();

    expect(
      {for (final d in result.unused) '${d.filePath}:${d.qualifiedName}'},
      {
        'lib/single.dart:reported',
        'lib/single.dart:reportedAfterBlankLine',
        'lib/single.dart:Catalog.reportedMember',
        'lib/single.dart:marker',
        'lib/single.dart:reportedBesideString',
        'lib/single.dart:reportedAfterTypo',
        'lib/range.dart:reportedBefore',
        'lib/range.dart:reportedAfter',
      },
    );
    expect(
      lines,
      containsAll(const [
        'Skipped lib/ignored.dart: marked `// ciach:ignore-file`.',
        'Skipped lib/single.dart:2 keptNextLine: kept by `// ciach:ignore` on line 1.',
        'Skipped lib/single.dart:7 keptAmongMetadata: kept by `// ciach:ignore` on line 5.',
        'Skipped lib/single.dart:9 keptTrailing: kept by `// ciach:ignore` on line 9.',
        'Skipped lib/single.dart:19 Catalog.keptMember: kept by `// ciach:ignore` on line 18.',
        'Skipped lib/single.dart:17 Catalog: declares Catalog.keptMember, kept by `// ciach:ignore`.',
        'Skipped lib/range.dart:7 KeptInRange.keptMember: kept by `// ciach:ignore-start` on line 3.',
      ]),
    );
    expect(warnings, [
      'lib/single.dart:13: `// ciach:ignore` keeps no declaration: on a line of its own it applies to the declaration on the next line, after code to the one named on its line.',
      'lib/single.dart:26: unknown marker `ciach:ignroe`; the markers are ciach:ignore, ciach:ignore-file, ciach:ignore-start and ciach:ignore-end.',
    ]);
  });
}
