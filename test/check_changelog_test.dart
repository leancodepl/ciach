import 'package:test/test.dart';

import '../tool/check_changelog.dart';

const _base = '''
## Unreleased

- Old entry without a link.
- Old entry. ([#5](https://github.com/leancodepl/ciach/pull/5))
''';

List<String> _errors(String added, {int? pr = 7}) =>
    changelogErrors('$_base$added\n', base: _base, pr: pr);

void main() {
  test('passes an entry ending with a link to its pull request', () {
    expect(
      _errors(
        '- New entry,\n'
        '  on two lines.\n'
        '  ([#7](https://github.com/leancodepl/ciach/pull/7))',
      ),
      isEmpty,
    );
  });

  test('ignores entries the base already has', () {
    expect(changelogErrors(_base, base: _base, pr: 7), isEmpty);
  });

  test('flags an entry without a link', () {
    expect(_errors('- New entry.'), hasLength(1));
  });

  test('flags a link to an issue', () {
    expect(
      _errors('- New. ([#7](https://github.com/leancodepl/ciach/issues/7))'),
      hasLength(1),
    );
  });

  test('flags a link that is not at the end', () {
    expect(
      _errors(
        '- New ([#7](https://github.com/leancodepl/ciach/pull/7)) entry.',
      ),
      hasLength(1),
    );
  });

  test('flags a number that differs from the URL', () {
    expect(
      _errors('- New. ([#7](https://github.com/leancodepl/ciach/pull/8))'),
      hasLength(1),
    );
  });

  test('flags a link to another pull request', () {
    expect(
      _errors('- New. ([#6](https://github.com/leancodepl/ciach/pull/6))'),
      hasLength(1),
    );
  });

  test('passes an edit of an older entry, which keeps its own link', () {
    // The base has "Old entry. ([#5](…))"; this PR (#7) rewords it.
    expect(
      _errors('- Reworded. ([#5](https://github.com/leancodepl/ciach/pull/5))'),
      isEmpty,
    );
  });

  test('passes any pull request without --pr', () {
    expect(
      _errors(
        '- New. ([#6](https://github.com/leancodepl/ciach/pull/6))',
        pr: null,
      ),
      isEmpty,
    );
  });
}
