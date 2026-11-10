/*
 * AI-Provenance:
 *   model: claude-fable-5-1
 *   harness: Claude Code
 *   plugins:
 *     - lean-ai-provenance
 *   skills:
 *     - mark-ai-provenance
 */

/// Checks the `## Contents` list of README.md: it links to every `##` and
/// `###` heading above the `---` rule that starts the LeanCode footer, in the
/// order of the file, and every `[text](#anchor)` link in the file names one
/// of those headings.
library;

import 'dart:io';

import 'package:collection/collection.dart';
import 'package:test/test.dart';

void main() {
  test('README.md lists every section in `## Contents`', () {
    expect(_readmeTocErrors(File('README.md').readAsStringSync()), isEmpty);
  });
}

/// What is wrong with the `## Contents` list of [readme].
List<String> _readmeTocErrors(String readme) {
  final lines = readme.split('\n');
  final headings = _headings(lines).toList();
  final contents = headings.firstWhereOrNull((h) => h.text == 'Contents');
  if (contents == null) {
    return ['No `## Contents` heading.'];
  }
  final anchors = {for (final heading in headings) _anchor(heading.text)};
  final sections = [
    for (final heading in headings)
      if (heading.line > contents.line) _anchor(heading.text),
  ];
  final listed = _listAnchors(lines, below: contents.line).toList();
  final unlisted = sections.whereNot(listed.contains);
  final dangling = lines.expand(_linkAnchors).whereNot(anchors.contains);
  return [
    for (final anchor in unlisted) 'Contents does not list #$anchor.',
    for (final anchor in dangling.toSet()) 'No heading for the link #$anchor.',
    if (unlisted.isEmpty &&
        dangling.isEmpty &&
        !const ListEquality<String>().equals(listed, sections))
      'Contents lists the sections in another order than the file.',
  ];
}

/// The `##` and `###` headings of [lines] above the `---` rule, outside
/// fenced code blocks.
Iterable<({int line, String text})> _headings(List<String> lines) sync* {
  var inFence = false;
  for (final (i, line) in lines.indexed) {
    if (line.startsWith('```')) {
      inFence = !inFence;
    } else if (inFence) {
      continue;
    } else if (line == '---') {
      return;
    } else if (_heading.firstMatch(line) case final match?) {
      yield (line: i, text: match.namedGroup('text')!);
    }
  }
}

/// The anchors that the list right [below] a heading links to, in order.
Iterable<String> _listAnchors(List<String> lines, {required int below}) sync* {
  for (final line in lines.skip(below + 1)) {
    if (line.startsWith('#')) {
      return;
    }
    yield* _linkAnchors(line);
  }
}

/// The anchors of the `[text](#anchor)` links in [line].
Iterable<String> _linkAnchors(String line) =>
    _link.allMatches(line).map((match) => match.namedGroup('anchor')!);

/// The id that GitHub and pub.dev give a heading: `Doc-only findings` gets
/// `doc-only-findings`.
String _anchor(String text) =>
    text.toLowerCase().replaceAll(_notInAnchor, '').replaceAll(' ', '-');

final _heading = RegExp(r'^##{1,2} (?<text>.+)$');
final _link = RegExp(r'\]\(#(?<anchor>[^)]+)\)');
final _notInAnchor = RegExp(r'[^\p{L}\p{N} _-]', unicode: true);
