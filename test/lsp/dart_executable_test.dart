import 'dart:async';
import 'dart:io';

import 'package:ciach/src/lsp/dart_executable.dart';
import 'package:cli_util/cli_util.dart' show environmentOverridesKey;
import 'package:path/path.dart' as p;
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

  group('sdkPathOf', () {
    late Directory tempDir;

    // Resolved, since `sdkPathOf` resolves links and the temporary directory
    // of macOS is behind one.
    setUp(
      () => tempDir = .new(
        Directory.systemTemp
            .createTempSync('ciach_sdk_path_')
            .resolveSymbolicLinksSync(),
      ),
    );
    tearDown(() => tempDir.deleteSync(recursive: true));

    /// Creates the files at [paths] in the temporary directory.
    void create(List<String> paths) {
      for (final path in paths) {
        File(p.join(tempDir.path, path)).createSync(recursive: true);
      }
    }

    /// Creates a Dart SDK at [root] in the temporary directory.
    void createSdk(String root) => create([
      '$root/bin/dart',
      '$root/lib/_internal/allowed_experiments.json',
      '$root/version',
    ]);

    test(
      "the SDK of a Dart SDK's `bin/dart` is the directory above `bin/`",
      () {
        createSdk('dart-sdk');

        expect(
          sdkPathOf(p.join(tempDir.path, 'dart-sdk', 'bin', 'dart')),
          p.join(tempDir.path, 'dart-sdk'),
        );
      },
    );

    test(
      "the SDK of Flutter's `bin/dart` is `bin/cache/dart-sdk` beside it",
      () {
        create(['flutter/bin/dart']);
        createSdk('flutter/bin/cache/dart-sdk');

        expect(
          sdkPathOf(p.join(tempDir.path, 'flutter', 'bin', 'dart')),
          p.join(tempDir.path, 'flutter', 'bin', 'cache', 'dart-sdk'),
        );
      },
    );

    test('a link to `dart` leads to the SDK of the file that it links to', () {
      createSdk('dart-sdk');
      final link = Link(p.join(tempDir.path, 'links', 'dart'))
        ..createSync(
          p.join(tempDir.path, 'dart-sdk', 'bin', 'dart'),
          recursive: true,
        );

      expect(sdkPathOf(link.path), p.join(tempDir.path, 'dart-sdk'));
    });

    test(
      'a script that runs another `dart`, such as a shim, leads to the SDK of that `dart`',
      () {
        final shim = File(p.join(tempDir.path, 'shims', 'dart'))
          ..createSync(recursive: true)
          ..writeAsStringSync(
            '#!/bin/sh\nexec "${Platform.resolvedExecutable}" "\$@"\n',
          );
        Process.runSync('chmod', ['+x', shim.path]);

        expect(sdkPathOf(shim.path), sdkPathOf(Platform.resolvedExecutable));
      },
      testOn: '!windows',
    );

    test('a `dart` outside every SDK: an error pointing at --dart', () {
      create(['tools/bin/dart']);

      expect(
        () => sdkPathOf(p.join(tempDir.path, 'tools', 'bin', 'dart')),
        throwsA(
          isA<DartSdkNotFoundException>().having(
            (e) => e.message,
            'message',
            contains('--dart'),
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
