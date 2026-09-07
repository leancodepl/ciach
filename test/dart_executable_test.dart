import 'package:ciach/src/dart_executable.dart';
import 'package:test/test.dart';

void main() {
  // A resolver over a fake filesystem: only [files] exist.
  String? find({
    String? explicit,
    required String currentExecutable,
    Map<String, String> environment = const {},
    bool isWindows = false,
    Set<String> files = const {},
  }) => findDartExecutable(
    explicit: explicit,
    currentExecutable: currentExecutable,
    environment: environment,
    isWindows: isWindows,
    fileExists: files.contains,
  );

  group('findDartExecutable', () {
    test('--dart wins over everything, and is not checked', () {
      expect(
        find(
          explicit: '/custom/dart',
          currentExecutable: '/sdk/bin/dart',
          environment: const {'PATH': '/other/bin'},
          files: const {'/other/bin/dart'},
        ),
        '/custom/dart',
      );
    });

    test('running under the SDK VM: uses that VM, wherever the SDK is', () {
      for (final vm in [
        '/usr/lib/dart/bin/dart',
        '/Users/me/fvm/versions/3.13.0/bin/dart',
        '/opt/flutter/bin/cache/dart-sdk/bin/dart',
        '/weird/place/dart',
      ]) {
        expect(
          find(currentExecutable: vm, environment: const {'PATH': '/x'}),
          vm,
          reason: vm,
        );
      }
    });

    test('running under dart.exe on Windows, any casing', () {
      expect(
        find(
          currentExecutable: r'C:\tools\Dart-SDK\bin\Dart.EXE',
          isWindows: true,
        ),
        r'C:\tools\Dart-SDK\bin\Dart.EXE',
      );
    });

    test('a compiled binary is not the SDK: falls back to PATH (#42)', () {
      // `dart install` puts the AOT-compiled tool itself here, so spawning it
      // as the server would run ciach recursively.
      expect(
        find(
          currentExecutable: '/home/me/.local/state/Dart/install/bin/ciach',
          environment: const {
            'PATH': '/usr/local/bin:/home/me/fvm/default/bin',
          },
          files: const {'/home/me/fvm/default/bin/dart'},
        ),
        '/home/me/fvm/default/bin/dart',
      );
    });

    test('PATH is searched in order, skipping empty entries', () {
      expect(
        find(
          currentExecutable: '/app/ciach',
          environment: const {'PATH': ':/first:/second'},
          files: const {'dart', '/first/dart', '/second/dart'},
        ),
        '/first/dart',
      );
    });

    test('Windows PATH: semicolons, Path key, exe before bat', () {
      expect(
        find(
          currentExecutable: r'C:\Users\me\AppData\Local\Dart\ciach.exe',
          isWindows: true,
          environment: const {'Path': r'C:\flutter\bin;C:\dart-sdk\bin'},
          files: const {
            r'C:\flutter\bin\dart.bat',
            r'C:\dart-sdk\bin\dart.exe',
          },
        ),
        r'C:\flutter\bin\dart.bat',
      );
      expect(
        find(
          currentExecutable: r'C:\app\ciach.exe',
          isWindows: true,
          environment: const {'Path': r'C:\dart-sdk\bin'},
          files: const {
            r'C:\dart-sdk\bin\dart.exe',
            r'C:\dart-sdk\bin\dart.bat',
          },
        ),
        r'C:\dart-sdk\bin\dart.exe',
      );
    });

    test('nothing found: an error naming the binary and the way out', () {
      expect(
        () => find(
          currentExecutable: '/app/ciach',
          environment: const {'PATH': '/usr/bin'},
        ),
        throwsA(
          isA<DartSdkNotFoundException>().having(
            (e) => e.message,
            'message',
            allOf(contains('/app/ciach'), contains('--dart'), contains('PATH')),
          ),
        ),
      );
      expect(
        () => find(currentExecutable: '/app/ciach'),
        throwsA(isA<DartSdkNotFoundException>()),
        reason: 'no PATH at all',
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
