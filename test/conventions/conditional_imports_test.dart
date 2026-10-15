import 'dart:io';

import 'package:ciach/src/conventions/conditional_imports.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory package;

  setUp(() {
    package = .systemTemp.createTempSync('ciach_conditional_imports_');
    File(p.join(package.path, 'pubspec.yaml')).writeAsStringSync('name: pkg');
  });

  tearDown(() => package.deleteSync(recursive: true));

  void write(String path, String content) => File(p.join(package.path, path))
    ..createSync(recursive: true)
    ..writeAsStringSync(content);

  String path(String relative) => p.join(package.path, 'lib', relative);

  Set<String> counterpartsOf(String relative) => {
    for (final file in ConditionalImports.scan(
      package.path,
    ).counterpartFilesOf(path(relative)))
      p.relative(file, from: p.join(package.path, 'lib')),
  };

  test('the default file and the file of every if clause are counterparts', () {
    write('lib/a.dart', '''
import 'stub.dart'
    if (dart.library.io) 'io.dart'
    if (dart.library.js_interop) 'web.dart' as impl;
''');

    expect(counterpartsOf('web.dart'), {'stub.dart', 'io.dart'});
    expect(counterpartsOf('stub.dart'), {'io.dart', 'web.dart'});
  });

  test('the variants of one directive are not counterparts of another', () {
    write('lib/a.dart', '''
export 'io.dart' if (dart.library.js_interop) "web.dart" show f;
''');
    write('lib/b.dart', '''
import 'web.dart' if (dart.library.ffi) 'native.dart';
''');

    expect(counterpartsOf('web.dart'), {'io.dart', 'native.dart'});
    expect(counterpartsOf('io.dart'), {'web.dart'});
  });

  test('a variant includes its parts and the files it exports', () {
    write('lib/a.dart', '''
import 'io.dart' if (dart.library.js_interop) 'web.dart';
''');
    write('lib/io.dart', '''
export 'src/io_impl.dart';
import 'src/helper.dart';
part 'io_part.dart';
''');
    write('lib/src/io_impl.dart', 'void f() {}');
    write('lib/src/helper.dart', 'void g() {}');
    write('lib/io_part.dart', "part of 'io.dart';");

    expect(counterpartsOf('web.dart'), {
      'io.dart',
      'src/io_impl.dart',
      'io_part.dart',
    });
    expect(counterpartsOf('src/io_impl.dart'), {'web.dart'});
  });

  test('a string compared in the condition is not a variant', () {
    write('lib/a.dart', '''
import 'stub.dart' if (dart.library.io == 'true') 'io.dart';
''');

    expect(counterpartsOf('stub.dart'), {'io.dart'});
  });

  test('a commented-out directive and a plain import are ignored', () {
    write('lib/a.dart', '''
// import 'stub.dart' if (dart.library.io) 'io.dart';
import 'plain.dart';
''');

    expect(
      ConditionalImports.scan(package.path).contains(path('stub.dart')),
      isFalse,
    );
    expect(counterpartsOf('plain.dart'), isEmpty);
  });
}
