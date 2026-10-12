import 'dart:convert';

import 'package:ciach/src/reporter.dart';
import 'package:test/test.dart';

import '../support/reporter.dart';

void main() {
  test('Reporter.json lists every dead referrer', () {
    final json =
        jsonDecode(
              Reporter.json(
                resultWith([
                  decl(onlyReferencedFrom: [rootReferrer, otherReferrer]),
                ]),
              ),
            )
            as Map<String, Object?>;
    final unused = json['unused']! as List<Object?>;
    expect((unused.single! as Map)['onlyReferencedFrom'], [
      {'qualifiedName': '_root', 'file': 'lib/a.dart', 'line': 1},
      {'qualifiedName': '_other', 'file': 'lib/b.dart', 'line': 7},
    ]);
  });

  group('Reporter.json', () {
    test('reports unused and docOnly as separate arrays', () {
      final json =
          jsonDecode(
                Reporter.json(
                  resultWith(
                    [decl(name: 'trulyDead')],
                    docOnly: [decl(name: 'onlyLinkedFromDocs')],
                  ),
                ),
              )
              as Map<String, Object?>;
      final summary = json['summary']! as Map<String, Object?>;
      expect(summary['unusedCount'], 1);
      expect(summary['docOnlyCount'], 1);
      final unused = json['unused']! as List<Object?>;
      final docOnly = json['docOnly']! as List<Object?>;
      expect((unused.single! as Map<String, Object?>)['name'], 'trulyDead');
      expect(
        (docOnly.single! as Map<String, Object?>)['name'],
        'onlyLinkedFromDocs',
      );
    });

    test('includes recovered references as a warnings array', () {
      final json =
          jsonDecode(
                Reporter.json(
                  resultWith(const [], recoveredReferences: [warning()]),
                ),
              )
              as Map<String, Object?>;
      final warnings = json['warnings']! as List<Object?>;
      final entry = warnings.single! as Map<String, Object?>;
      // `name`/`qualifiedName` mean the same as in `unused[]`.
      expect(entry['name'], 'baz');
      expect(entry['qualifiedName'], 'A.baz');
      expect(entry['file'], 'lib/a.dart');
      expect(entry['line'], 4);
      expect(entry['column'], 7);
      expect(entry['usageFile'], 'lib/b.dart');
      expect(entry['usageLine'], 9);
      expect(entry['usageColumn'], 2);
      expect(entry['message'], contains('used at lib/b.dart:9:2'));
    });

    test('warnings array is empty when there are no recovered references', () {
      final json =
          jsonDecode(Reporter.json(resultWith([decl()])))
              as Map<String, Object?>;
      expect(json['warnings'], isEmpty);
    });
  });
}
