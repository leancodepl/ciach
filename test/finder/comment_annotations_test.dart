@Timeout(Duration(minutes: 5))
library;

import 'package:test/test.dart';

import '../support/finder.dart';

void main() {
  setUpFixture();

  group('annotation detection ignores comments', () {
    Future<Set<String>> runCommentAnnotations() async {
      final result = await runScenario(const [
        'lib/scenarios/comment_annotations.dart',
      ]);
      return qualifiedNames(result.unused);
    }

    test(
      'a doc comment mentioning @override does not skip the declaration',
      () {
        return expectLater(
          runCommentAnnotations(),
          completion(contains('deadOverrideInDoc')),
        );
      },
    );

    test('a trailing comment mentioning @override does not skip it', () {
      return expectLater(
        runCommentAnnotations(),
        completion(contains('deadOverrideTrailing')),
      );
    });

    test('a blank-separated comment mentioning @override does not skip it', () {
      return expectLater(
        runCommentAnnotations(),
        completion(contains('deadOverrideBlankSeparated')),
      );
    });

    test('a doc comment mentioning vm:entry-point does not skip it', () {
      return expectLater(
        runCommentAnnotations(),
        completion(contains('deadEntryPointInDoc')),
      );
    });

    test('a trailing comment mentioning vm:entry-point does not skip it', () {
      return expectLater(
        runCommentAnnotations(),
        completion(contains('deadEntryPointTrailing')),
      );
    });

    test('a blank-separated comment mentioning vm:entry-point does not skip '
        'it', () {
      return expectLater(
        runCommentAnnotations(),
        completion(contains('deadEntryPointBlankSeparated')),
      );
    });

    test('a file-header block mentioning both literals does not skip the first '
        'declaration', () {
      return expectLater(
        runCommentAnnotations(),
        completion(contains('deadAfterHeaderBlock')),
      );
    });

    test('an unprefixed block-comment line mentioning @override does not skip '
        'it', () {
      return expectLater(
        runCommentAnnotations(),
        completion(contains('deadOverrideBareBlock')),
      );
    });

    test('an unprefixed block-comment line mentioning vm:entry-point does not '
        'skip it', () {
      return expectLater(
        runCommentAnnotations(),
        completion(contains('deadEntryPointBareBlock')),
      );
    });

    test('a real @pragma(vm:entry-point) is still skipped — the string literal '
        'survives comment-stripping', () async {
      final names = await runCommentAnnotations();
      expect(names, isNot(contains('liveByRealPragma')));
    });
  });
}
