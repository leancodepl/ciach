import 'dart:io';

import 'package:args/args.dart';

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
    pr: switch (options.option('pr')) {
      final pr? => int.parse(pr),
      null => null,
    },
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
int? _linkedPr(String entry) => switch (_link.firstMatch(entry)) {
  final link? => int.parse(link[1]!),
  null => null,
};

const _pulls = 'https://github.com/leancodepl/ciach/pull';

/// A link to a pull request ending an entry, with the same number twice.
final _link = RegExp(r'\(\[#(\d+)\]\(' + RegExp.escape(_pulls) + r'/\1\)\)$');

/// The `- ` list items, each with its continuation lines.
Iterable<String> _entries(String changelog) sync* {
  final entry = StringBuffer();
  for (final line in changelog.split('\n')) {
    if (entry.isNotEmpty && line.startsWith('  ')) {
      entry.write('\n$line');
      continue;
    }
    if (entry.isNotEmpty) {
      yield entry.toString();
      entry.clear();
    }
    if (line.startsWith('- ')) {
      entry.write(line);
    }
  }
  if (entry.isNotEmpty) {
    yield entry.toString();
  }
}
