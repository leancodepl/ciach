import 'dart:io';

import 'package:cli_util/cli_util.dart' as cli_util;
import 'package:collection/collection.dart';
import 'package:path/path.dart' as p;

/// No Dart SDK to analyze with; [message] names the way out.
class DartSdkNotFoundException implements Exception {
  const DartSdkNotFoundException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The `dart` of the SDK to analyze with: [explicit] (`--dart`), else the SDK
/// `package:cli_util` finds — the VM running this tool, or `dart` on `PATH`
/// for a compiled binary (`dart install`, `dart compile exe`), whose own
/// executable is ciach rather than `dart` (#42).
String findDartExecutable({String? explicit}) =>
    explicit ??
    cli_util.dartExecutable ??
    (throw const DartSdkNotFoundException(
      'Could not find a Dart SDK to analyze with: this is a '
      'compiled ciach, not one running under `dart`, and `dart` is not on '
      'PATH.\nPass --dart <path>, set `dart:` in ciach.yaml, or add the '
      "SDK's bin directory to PATH.",
    ));

/// The root of the Dart SDK that [dartExecutable] runs: the directory above
/// its `bin/`, or for Flutter's `bin/dart`, the `bin/cache/dart-sdk` beside
/// it. For a script that runs another `dart`, such as the shim of a version
/// manager, it is the SDK of the `dart` that the script runs.
///
/// Throws a [DartSdkNotFoundException] when none of these is a Dart SDK.
String sdkPathOf(String dartExecutable) {
  final file = File(dartExecutable);
  final bin = p.dirname(
    file.existsSync() ? file.resolveSymbolicLinksSync() : dartExecutable,
  );
  return [
        p.dirname(bin),
        p.join(bin, 'cache', 'dart-sdk'),
      ].firstWhereOrNull(cli_util.isValidSdkPath) ??
      _sdkPathReportedBy(dartExecutable) ??
      (throw DartSdkNotFoundException(
        'Could not find the Dart SDK of `$dartExecutable`.\nPass --dart <path> with the `dart` of a Dart or Flutter SDK.',
      ));
}

/// Returns the SDK of the `dart` that [dartExecutable] runs, which a script
/// that it runs reports, or `null` when that isn't an SDK or the script fails.
String? _sdkPathReportedBy(String dartExecutable) {
  final dir = Directory.systemTemp.createTempSync('ciach_sdk_');
  try {
    final script = File(p.join(dir.path, 'executable.dart'))
      ..writeAsStringSync('''
import 'dart:io';

void main() => stdout.write(Platform.resolvedExecutable);
''');
    final result = Process.runSync(dartExecutable, [
      script.path,
    ], runInShell: executableNeedsShell(dartExecutable));
    final sdk = p.dirname(p.dirname('${result.stdout}'));
    return result.exitCode == 0 && cli_util.isValidSdkPath(sdk) ? sdk : null;
  } on ProcessException {
    return null;
  } finally {
    dir.deleteSync(recursive: true);
  }
}

/// Windows batch scripts (Flutter's `dart.bat`) only run through a shell.
bool executableNeedsShell(String executable) => const {
  '.bat',
  '.cmd',
}.contains(p.windows.extension(executable).toLowerCase());
