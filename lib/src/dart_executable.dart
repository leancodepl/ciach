import 'package:cli_util/cli_util.dart' as cli_util;
import 'package:path/path.dart' as p;

/// No `dart` to run the analysis server with; [message] names the way out.
class DartSdkNotFoundException implements Exception {
  const DartSdkNotFoundException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The `dart` that launches the analysis server: [explicit] (`--dart`), else
/// the SDK `package:cli_util` finds — the VM running this tool, or `dart` on
/// `PATH` for a compiled binary (`dart install`, `dart compile exe`), which is
/// ciach itself and must not be spawned as the server (#42).
String findDartExecutable({String? explicit}) =>
    explicit ??
    cli_util.dartExecutable ??
    (throw const DartSdkNotFoundException(
      'Could not find a Dart SDK to run the analysis server with: this is a '
      'compiled ciach, not one running under `dart`, and `dart` is not on '
      'PATH.\nPass --dart <path>, set `dart:` in ciach.yaml, or add the '
      "SDK's bin directory to PATH.",
    ));

/// Windows batch scripts (Flutter's `dart.bat`) only run through a shell.
bool executableNeedsShell(String executable) => const {
  '.bat',
  '.cmd',
}.contains(p.windows.extension(executable).toLowerCase());
