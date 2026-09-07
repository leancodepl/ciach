import 'dart:io';

import 'package:path/path.dart' as p;

/// Thrown when no `dart` executable to launch the analysis server with could be
/// found. [message] is written for the user and names the way out.
class DartSdkNotFoundException implements Exception {
  const DartSdkNotFoundException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Locates the `dart` executable that launches the analysis server.
///
/// Tried in order:
///
/// 1. [explicit], the user's `--dart` / `dart:` setting, taken as is.
/// 2. The Dart VM running this tool, when there is one — `dart run ciach`,
///    `dart pub global run`, `dart test`. It is recognised by name: the SDK's VM
///    is always called `dart` (`dart.exe` on Windows), wherever the SDK lives
///    (fvm, asdf, Homebrew, a Flutter SDK's `bin/cache/dart-sdk`, …). A
///    compiled binary — `dart compile exe`, `dart build cli`, `dart install` —
///    is the program itself, named after the tool, and is deliberately *not*
///    treated as an SDK: spawning it as the server would run ciach recursively
///    and fail. ([#42](https://github.com/leancodepl/ciach/issues/42))
/// 3. `dart` on `PATH`, as the user's shell would find it. On Windows also
///    `dart.exe`, `dart.bat` and `dart.cmd`.
///
/// Throws a [DartSdkNotFoundException] when none of these yields anything.
///
/// The optional parameters replace the running process's environment, for
/// tests; production callers pass none of them.
String findDartExecutable({
  String? explicit,
  String? currentExecutable,
  Map<String, String>? environment,
  bool? isWindows,
  bool Function(String path)? fileExists,
}) {
  if (explicit != null) {
    return explicit;
  }

  final windows = isWindows ?? Platform.isWindows;
  final exists = fileExists ?? (path) => File(path).existsSync();

  final running = currentExecutable ?? Platform.resolvedExecutable;
  if (_isNamedDart(running, windows: windows)) {
    return running;
  }

  final env = environment ?? Platform.environment;
  final onPath = _searchPath(env, windows: windows, exists: exists);
  if (onPath != null) {
    return onPath;
  }

  throw DartSdkNotFoundException(
    'Could not find the Dart SDK to run the analysis server with.\n'
    'This is a compiled ciach binary ($running), not one running under '
    '`dart`, and there is no `dart` on PATH.\n'
    'Pass --dart <path-to-dart>, set `dart: <path>` in ciach.yaml, or put '
    "the SDK's bin directory on PATH.",
  );
}

/// Whether [executable] is the SDK's VM going by its file name.
bool _isNamedDart(String executable, {required bool windows}) {
  if (windows) {
    final name = p.windows.basename(executable).toLowerCase();
    return name == 'dart' || name == 'dart.exe';
  }
  return p.posix.basename(executable) == 'dart';
}

/// The first `dart` found on the environment's `PATH`, or null.
String? _searchPath(
  Map<String, String> environment, {
  required bool windows,
  required bool Function(String path) exists,
}) {
  // Windows keys are case-insensitive; `Path` is the usual spelling there.
  final path = windows
      ? environment.entries
            .where((e) => e.key.toUpperCase() == 'PATH')
            .map((e) => e.value)
            .firstOrNull
      : environment['PATH'];
  if (path == null || path.isEmpty) {
    return null;
  }

  final context = windows ? p.windows : p.posix;
  final names = windows
      ? const ['dart.exe', 'dart.bat', 'dart.cmd', 'dart']
      : const ['dart'];

  for (final dir in path.split(windows ? ';' : ':')) {
    // An empty entry means the current directory; too surprising to honour.
    if (dir.isEmpty) {
      continue;
    }
    for (final name in names) {
      final candidate = context.join(dir, name);
      if (exists(candidate)) {
        return candidate;
      }
    }
  }
  return null;
}

/// Whether [executable] needs a shell to run: a Windows batch script cannot be
/// started directly, and Flutter ships its `dart` as one.
bool executableNeedsShell(String executable) {
  final ext = p.windows.extension(executable).toLowerCase();
  return ext == '.bat' || ext == '.cmd';
}
