/// Logging for all of ciach. Import this, not `package:logging`, and declare
/// one logger per file: `final _log = Logger('ciach.finder');`.
///
/// Results (findings, problems) are returned as data, never read from the log.
///
/// | Level                  | Use                                               |
/// |------------------------|---------------------------------------------------|
/// | [Level.SEVERE]         | The command failed. CLI only; the library throws. |
/// | [Level.WARNING]        | Needs attention, not part of the result.          |
/// | [Level.INFO]           | Progress.                                         |
/// | [Level.CONFIG]         | Settings.                                         |
/// | [Level.FINE] and finer | Detail.                                           |
///
/// Library code never prints and never configures [Logger.root].
library;

import 'package:logging/logging.dart';

export 'package:logging/logging.dart' show Level, LogRecord, Logger;
