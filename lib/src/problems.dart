import 'dart:async';
import 'dart:io';

import 'package:ciach/src/lsp/lsp_client.dart';
import 'package:ciach/src/models.dart';
import 'package:ciach/src/paths.dart';
import 'package:logging/logging.dart';
import 'package:pro_lsp/pro_lsp.dart' show Position;

final _log = Logger('ciach.problems');

/// The [AnalysisProblem]s of one run.
///
/// A run's body goes inside [collect]; anything it calls, however deep,
/// records through [reportProblem] without a sink passed down to it. Each
/// run collects its own, so runs side by side don't mix.
final class ProblemLog {
  ProblemLog(this.rootPath);

  /// Problem paths are made relative to this.
  final String rootPath;

  final List<AnalysisProblem> _problems = [];

  /// What was reported, in order.
  List<AnalysisProblem> get problems => List.unmodifiable(_problems);

  static final _key = Object();

  /// Runs [body] with this as where [reportProblem] records.
  Future<T> collect<T>(Future<T> Function() body) =>
      runZoned(body, zoneValues: {_key: this});
}

/// Records that [error] cost the run an answer about [path] (absolute), and
/// that the run went on as [summary] says. [position] is zero-based; [name] is
/// the declaration concerned, if any.
///
/// The problem goes to the [ProblemLog] collecting it, if any, and is logged
/// as a [Level.WARNING] whose object it is.
void reportProblem(
  String summary,
  Object error, {
  required String path,
  Position? position,
  String? name,
}) {
  final log = Zone.current[ProblemLog._key] as ProblemLog?;
  final (cause, detail) = switch (error) {
    LspRequestException(:final message, :final detail) => (message, detail),
    FileSystemException(:final message, :final osError) => (
      osError?.message ?? message,
      null,
    ),
    _ => ('$error', null),
  };
  final problem = AnalysisProblem(
    summary: summary,
    cause: cause,
    detail: detail,
    filePath: log == null ? path : relativePosix(path, log.rootPath),
    line: position == null ? null : position.line + 1,
    column: position == null ? null : position.character + 1,
    name: name,
  );
  log?._problems.add(problem);
  _log.warning(problem);
}
