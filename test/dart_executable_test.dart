import 'dart:async';
import 'dart:io';

import 'package:ciach/src/dart_executable.dart';
import 'package:cli_util/cli_util.dart' show environmentOverridesKey;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  // Runs [body] as if this process were [executable] in [environment].
  T asProcess<T>(
    String executable,
    Map<String, String> environment,
    T Function() body,
  ) => runZoned(
    body,
    zoneValues: {
      environmentOverridesKey: {
        ...environment,
        '_DART_RESOLVED_EXECUTABLE': executable,
      },
    },
  );

  final vm = Platform.resolvedExecutable;
  final sdkBin = p.dirname(vm);

  group('findDartExecutable', () {
    test('--dart wins, unchecked', () {
      expect(findDartExecutable(explicit: '/custom/dart'), '/custom/dart');
    });

    test('under the SDK VM: that VM', () {
      expect(asProcess(vm, {'PATH': ''}, findDartExecutable), vm);
    });

    test('a compiled binary is not the SDK: dart from PATH (#42)', () {
      expect(
        asProcess('/app/bin/ciach', {'PATH': sdkBin}, findDartExecutable),
        p.join(sdkBin, Platform.isWindows ? 'dart.exe' : 'dart'),
      );
    });

    test('nothing found: an error pointing at --dart', () {
      expect(
        () => asProcess('/app/bin/ciach', {'PATH': ''}, findDartExecutable),
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
