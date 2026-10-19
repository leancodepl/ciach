/*
 * AI-Provenance:
 *   model: claude-fable-5-1
 *   harness: Claude Code
 *   plugins:
 *     - lean-ai-provenance
 *   skills:
 *     - mark-ai-provenance
 */

import 'dart:io';

import 'package:markdown/markdown.dart' as md;
import 'package:test/test.dart';

/// The ids of the `h2` and `h3` headings of `content/docs.md`, as the
/// `markdown` package generates them for the page.
Set<String> _headingIds() {
  final source = File('content/docs.md').readAsStringSync();
  // The frontmatter, which jaspr_content strips before parsing.
  final body = source.split('\n---\n').skip(1).join('\n---\n');
  final nodes = md.Document(extensionSet: md.ExtensionSet.gitHubWeb)
      .parse(body);
  return {
    for (final node in nodes)
      if (node case md.Element(tag: 'h2' || 'h3', :final generatedId?))
        generatedId,
  };
}

/// Every fragment that [file] links to on the docs page, from links such as
/// `/docs#ci` and `https://ciach.leancode.co/docs#ci`.
Set<String> _linkedFragments(File file) => {
  for (final match in _fragment.allMatches(file.readAsStringSync()))
    match.namedGroup('fragment')!,
};

final _fragment = RegExp(r'/docs#(?<fragment>[\w-]+)');

/// The files that may link to the docs page: the site, its content and the
/// README.
Iterable<File> _linkingFiles() sync* {
  for (final directory in ['lib', 'content']) {
    yield* Directory(directory)
        .listSync(recursive: true)
        .whereType<File>()
        .where(
          (file) => file.path.endsWith('.dart') || file.path.endsWith('.md'),
        );
  }
  yield File('../README.md');
}

void main() {
  test('every link to a section of the docs page names a heading of `content/docs.md`', () {
    final ids = _headingIds();
    for (final file in _linkingFiles()) {
      expect(
        _linkedFragments(file),
        everyElement(isIn(ids)),
        reason: file.path,
      );
    }
  });
}
