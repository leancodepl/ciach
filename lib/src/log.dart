/// How ciach logs: the one way anything in the package says something in
/// passing. Import this, not `package:logging`, and declare one logger per
/// file under `ciach.`:
///
/// ```dart
/// final _log = Logger('ciach.finder');
/// ```
///
/// The log is narration. What the command produced — the findings, the
/// problems, the recovered references, a removal's outcome — is its result,
/// returned as data and rendered by `Reporter`; it never comes from the log,
/// so it does not depend on what anyone listens to.
///
/// | Level              | Means                                                          |
/// |--------------------|----------------------------------------------------------------|
/// | [Level.SEVERE]     | The command failed; carries the error when there is one. Only the CLI's top level logs it: library code throws. |
/// | [Level.WARNING]    | Needs the user's attention, but is not part of the result.   |
/// | [Level.INFO]       | What the run is doing now: its phases, files done.             |
/// | [Level.CONFIG]     | How the run is set up: config, settings, the `dart` used.      |
/// | [Level.FINE]       | What happened, in detail.                                      |
/// | [Level.FINER]/[Level.FINEST] | Finer still, such as analysis server traffic.       |
///
/// Library code never writes to stdout or stderr, and never configures
/// [Logger.root]: whoever runs ciach decides what is shown, and how. The CLI
/// shows warnings and errors always, [Level.INFO] on its progress line, and
/// everything with `--verbose`.
library;

import 'package:logging/logging.dart';

export 'package:logging/logging.dart' show Level, LogRecord, Logger;
