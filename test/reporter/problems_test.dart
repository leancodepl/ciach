import 'dart:convert';

import 'package:ciach/src/reporter.dart';
import 'package:test/test.dart';

import '../support/reporter.dart';

void main() {
  group('problems', () {
    test('json carries them in-band', () {
      final decoded =
          jsonDecode(Reporter.json(resultWith(const [], problems: [problem()])))
              as Map<String, Object?>;
      expect(decoded['problems'], [
        {
          'summary': 'Could not find the references; kept.',
          'cause': 'Null check operator used on a null value',
          'file': 'lib/a.dart',
          'line': 3,
          'column': 5,
          'name': 'A.foo',
          'detail': '#0      Foo.bar',
        },
      ]);
    });

    test('github annotates each, with what position is known', () {
      final github = Reporter.github(
        resultWith(
          const [],
          problems: [problem(), problem(line: null, column: null, name: null)],
        ),
        pathPrefix: 'pkg',
      );
      expect(
        github,
        '::warning file=pkg/lib/a.dart,line=3,col=5,title=Could not analyze'
        "::'A.foo': Could not find the references; kept. "
        'Cause: Null check operator used on a null value\n'
        '::warning file=pkg/lib/a.dart,title=Could not analyze'
        '::Could not find the references; kept. '
        'Cause: Null check operator used on a null value\n',
      );
    });
  });
}
