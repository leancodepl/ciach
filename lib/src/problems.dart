import 'dart:async';
import 'dart:io';

import 'package:ciach/src/log.dart';
import 'package:ciach/src/lsp/lsp_client.dart';
import 'package:ciach/src/models.dart';
import 'package:ciach/src/paths.dart';
import 'package:pro_lsp/pro_lsp.dart' show Position;

/// Problems are the finder's to narrate: every one happens during its run.
final _log = Logger('ciach.finder');

/// The [AnalysisProblem]s of one run: part of its result, so collected as
/// data rather than read back from the log.
///
/// A run's body goes inside [collect]; anything it calls, however deep,
/// records through [recordProblem] without a collector passed down to it.
/// Each run collects its own, so runs side by side don't mix.
final class ProblemCollector {
  ProblemCollector(this.rootPath);

  /// Problem paths are made relative to this.
  final String rootPath;

  final List<AnalysisProblem> _problems = [];

  /// What was reported, in order.
  List<AnalysisProblem> get problems => List.unmodifiable(_problems);

  static final _key = Object();

  /// Runs [body] with this as where [recordProblem] records.
  Future<T> collect<T>(Future<T> Function() body) =>
      runZoned(body, zoneValues: {_key: this});
}

/// Records that [error] cost the run an answer about [path] (absolute), and
/// that the run went on as [summary] says. [position] is zero-based; [name] is
/// the declaration concerned, if any.
///
/// The problem goes to the [ProblemCollector] of the run, if any, and is
/// narrated at [Level.FINE], with the problem as the record's object.
void recordProblem(
  String summary,
  Object error, {
  required String path,
  Position? position,
  String? name,
}) {
  final collector = Zone.current[ProblemCollector._key] as ProblemCollector?;
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
    filePath: collector == null
        ? path
        : relativePosix(path, collector.rootPath),
    line: position == null ? null : position.line + 1,
    column: position == null ? null : position.character + 1,
    name: name,
  );
  collector?._problems.add(problem);
  _log.fine(problem);
}
