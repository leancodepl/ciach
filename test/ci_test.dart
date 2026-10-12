import 'package:ciach/src/cli/ci.dart';
import 'package:test/test.dart';

void main() {
  group('CiRunner.detect', () {
    test('is null outside CI', () {
      expect(CiRunner.detect(const {}), isNull);
      expect(CiRunner.detect(const {'HOME': '/home/me'}), isNull);
    });

    test('recognizes each service by its own variable', () {
      for (final runner in CiRunner.values) {
        expect(CiRunner.detect({runner.variable: 'true'}), runner);
      }
      expect(
        CiRunner.detect(const {'JENKINS_URL': 'https://ci.example.com/'}),
        CiRunner.jenkins,
      );
      expect(
        CiRunner.detect(const {'TF_BUILD': 'True'}),
        CiRunner.azurePipelines,
      );
      // Codemagic sets CI too; its own variable names it.
      expect(
        CiRunner.detect(const {'CI': 'true', 'CM_BUILD_ID': 'a1b2c3'}),
        CiRunner.codemagic,
      );
    });

    test('names the service over the conventional CI', () {
      expect(
        CiRunner.detect(const {'CI': 'true', 'GITHUB_ACTIONS': 'true'}),
        CiRunner.githubActions,
      );
      expect(CiRunner.detect(const {'CI': '1'}), CiRunner.other);
    });

    test('an empty, false or 0 variable is unset', () {
      for (final value in ['', ' ', 'false', 'FALSE', '0']) {
        expect(CiRunner.detect({'CI': value}), isNull, reason: "'$value'");
        expect(
          CiRunner.detect({'GITHUB_ACTIONS': value}),
          isNull,
          reason: "'$value'",
        );
      }
      // …unless another one says otherwise.
      expect(
        CiRunner.detect(const {'GITHUB_ACTIONS': 'false', 'CI': 'true'}),
        CiRunner.other,
      );
    });
  });

  test('the defaults are the same everywhere, bar the format', () {
    for (final runner in CiRunner.values) {
      final defaults = runner.defaults;
      expect(defaults.setExitIfChanged, isTrue, reason: runner.label);
      expect(defaults.verbose, isTrue, reason: runner.label);
      expect(defaults.showProgress, isFalse, reason: runner.label);
      // Only GitHub Actions has an annotation format.
      expect(
        defaults.format,
        runner == .githubActions ? 'github' : isNull,
        reason: runner.label,
      );
    }
  });
}
