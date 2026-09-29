import 'dart:async';
import 'dart:io';

import 'package:ciach/src/log.dart';
import 'package:ciach/src/lsp/lsp_client.dart';
import 'package:ciach/src/models.dart';
import 'package:ciach/src/paths.dart';
import 'package:pro_lsp/pro_lsp.dart' show Position;

final _log = Logger('ciach.finder');

/// Collects the [AnalysisProblem]s of one run. Code inside [collect] reports
/// through [recordProblem]; concurrent runs stay separate.
final class ProblemCollector {
  ProblemCollector(this.rootPath);

  /// Problem paths are relative to this.
  final String rootPath;

  final List<AnalysisProblem> _problems = [];

  /// The problems, in order.
  List<AnalysisProblem> get problems => List.unmodifiable(_problems);

  static final _key = Object();

  /// Runs [body], collecting what it records.
  Future<T> collect<T>(Future<T> Function() body) =>
      runZoned(body, zoneValues: {_key: this});
}

/// Records a problem at [path] (absolute; [position] zero-based) for the
/// current run, and logs it at [Level.FINE].
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
