import 'dart:async';

import 'package:ciach/src/dart_executable.dart';
import 'package:cli_util/cli_util.dart' show environmentOverridesKey;
import 'package:test/test.dart';

// The search itself is package:cli_util's; this covers only what ciach adds.
void main() {
  group('findDartExecutable', () {
    test('--dart wins, unchecked', () {
      expect(findDartExecutable(explicit: '/custom/dart'), '/custom/dart');
    });

    test('nothing found: an error pointing at --dart', () {
      // A compiled binary with no `dart` anywhere on PATH.
      expect(
        () => runZoned(
          findDartExecutable,
          zoneValues: {
            environmentOverridesKey: {
              'PATH': '',
              '_DART_RESOLVED_EXECUTABLE': '/app/bin/ciach',
            },
          },
        ),
        throwsA(
          isA<DartSdkNotFoundException>().having(
            (e) => e.message,
            'message',
            allOf(contains('--dart'), contains('PATH')),
          ),
        ),
      );
    });
  });

  test('executableNeedsShell: only Windows batch scripts', () {
    expect(executableNeedsShell(r'C:\flutter\bin\dart.bat'), isTrue);
    expect(executableNeedsShell(r'C:\x\dart.CMD'), isTrue);
    expect(executableNeedsShell(r'C:\dart-sdk\bin\dart.exe'), isFalse);
    expect(executableNeedsShell('/usr/bin/dart'), isFalse);
  });
}
