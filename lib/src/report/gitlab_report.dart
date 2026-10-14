/*
 * AI-Provenance:
 *   model: claude-fable-5-1
 *   harness: Claude Code
 *   plugins:
 *     - lean-ai-provenance
 *   skills:
 *     - mark-ai-provenance
 */

import 'dart:convert';

import 'package:ciach/src/model/finder_result.dart';
import 'package:ciach/src/report/annotations.dart';

/// A [GitLab Code Quality][] report, for a job's `codequality` artifact,
/// which GitLab shows on the merge request: a `minor` issue for each unused
/// finding and empty file, an `info` one for each doc-only one. Each
/// fingerprint hashes the finding without its line, so a finding that only
/// moved is not reported as new.
///
/// [pathPrefix] is prepended to each path, as in `githubReport`.
///
/// [GitLab Code Quality]: https://docs.gitlab.com/ci/testing/code_quality/#code-quality-report-format
String gitlabReport(FinderResult result, {String pathPrefix = '.'}) {
  const encoder = JsonEncoder.withIndent('  ');
  final seen = <String, int>{};
  final issues = <Map<String, Object?>>[];
  for (final (:check, :file, :line, column: _, :message) in annotationsOf(
    result,
    pathPrefix,
  )) {
    final key = [check.id, file, message].join('\n');
    // The occurrence tells identical findings in one file apart.
    final occurrence = seen.update(key, (n) => n + 1, ifAbsent: () => 0);
    issues.add({
      'description': message,
      'check_name': check.id,
      'fingerprint': _fingerprint('$key\n$occurrence'),
      'severity': check.notice ? 'info' : 'minor',
      'location': {
        'path': file,
        'lines': {'begin': line ?? 1},
      },
    });
  }
  return encoder.convert(issues);
}

/// A 64-bit FNV-1a hash of [key], in hex.
String _fingerprint(String key) {
  // ciach runs on the VM only, where an int holds the whole offset.
  // ignore: avoid_js_rounded_ints
  var hash = 0xcbf29ce484222325;
  for (final byte in utf8.encode(key)) {
    hash = (hash ^ byte) * 0x100000001b3;
  }
  // Unsigned, in halves: a 64-bit int with the top bit set is negative.
  return [
    hash >>> 32,
    hash & 0xffffffff,
  ].map((half) => half.toRadixString(16).padLeft(8, '0')).join();
}
