import 'dart:io';

import 'package:args/args.dart';
import 'package:ciach/src/util/extensions.dart';
import 'package:collection/collection.dart';

/// Checks the CHANGELOG.md entries added since a base revision: each ends with
/// a link to its pull request, `([#N](https://github.com/leancodepl/ciach/pull/N))`.
///
/// Usage: `dart run tool/check_changelog.dart [--base origin/main] [--pr N]`.
/// With `--pr`, a new entry must link that pull request, unless it rewords an
/// entry of one the base already links.
Future<void> main(List<String> args) async {
  final options =
      (ArgParser()
            ..addOption('base', defaultsTo: 'origin/main')
            ..addOption('pr'))
          .parse(args);
  final base = await Process.run('git', [
    'show',
    '${options.option('base')}:CHANGELOG.md',
  ]);
  if (base.exitCode != 0) {
    stderr.write(base.stderr);
    exit(2);
  }
  final errors = changelogErrors(
    File('CHANGELOG.md').readAsStringSync(),
    base: base.stdout as String,
    pr: options.option('pr')?.let(int.parse),
  );
  if (errors.isNotEmpty) {
    stderr.writeln(errors.join('\n\n'));
    exit(1);
  }
}

/// What is wrong with the entries of [changelog] that [base] doesn't have.
List<String> changelogErrors(
  String changelog, {
  required String base,
  int? pr,
}) {
  final old = _entries(base).toSet();
  final linkedBefore = {for (final entry in old) ?_linkedPr(entry)};
  String? error(String entry) => switch (_linkedPr(entry)) {
    null =>
      'Does not end with ([#N]($_pulls/N)), N being its pull request:\n$entry',
    final linked
        when pr != null && linked != pr && !linkedBefore.contains(linked) =>
      'Links #$linked instead of #$pr:\n$entry',
    _ => null,
  };
  return [
    for (final entry in _entries(changelog))
      if (!old.contains(entry)) ?error(entry),
  ];
}

/// The pull request linked at the end of [entry].
int? _linkedPr(String entry) => _link.firstMatch(entry)?[1]!.let(int.parse);

const _pulls = 'https://github.com/leancodepl/ciach/pull';

/// A link to a pull request ending an entry, with the same number twice.
final _link = RegExp(r'\(\[#(\d+)\]\(' + RegExp.escape(_pulls) + r'/\1\)\)$');

/// The `- ` list items, each with the lines indented by two spaces that follow
/// it.
Iterable<String> _entries(String changelog) => changelog
    .split('\n')
    .splitBefore((line) => !line.startsWith('  '))
    .where((lines) => lines.first.startsWith('- '))
    .map((lines) => lines.join('\n'));
