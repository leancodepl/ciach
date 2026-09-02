/// Build-time syntax highlighting.
///
/// Tokenizing is done by `syntax_highlight_lite`, the pure-Dart TextMate
/// engine behind `jaspr_content`, while the site is pre-rendered. Its scopes
/// are mapped to CSS classes here, so the browser receives finished `<span>`
/// markup and never downloads a highlighting library.
library;

import 'package:ciach_website/grammars/console_grammar.dart';
import 'package:ciach_website/grammars/json_grammar.dart';
import 'package:ciach_website/grammars/shell_grammar.dart';
import 'package:ciach_website/grammars/yaml_grammar.dart';
import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:syntax_highlight_lite/syntax_highlight_lite.dart' as sh;

enum Language {
  dart,
  yaml,
  shell,
  json,

  /// ciach's own terminal output, with shell prompts.
  console,
}

/// Registers the grammars. Call once before rendering; the Dart grammar ships
/// with the engine, the rest live in `grammars/`.
Future<void> initHighlighting() async {
  await sh.Highlighter.initialize(['dart']);
  sh.Highlighter.addLanguage(Language.yaml.name, kYamlGrammar);
  sh.Highlighter.addLanguage(Language.json.name, kJsonGrammar);
  sh.Highlighter.addLanguage(Language.shell.name, kShellGrammar);
  sh.Highlighter.addLanguage(Language.console.name, kConsoleGrammar);
}

/// Colors come from CSS classes, not from the engine's theme, so the theme is
/// empty. Its text style is required but never rendered.
final _theme = sh.HighlighterTheme.fromConfiguration(
  '{"settings": []}',
  sh.TextStyle(foreground: const sh.Color(0)),
);

final _highlighters = <Language, sh.Highlighter>{};

/// TextMate scope prefixes to CSS classes (`tk-<class>`). For each token the
/// innermost scope is tried first, longest prefix first; a scope with no
/// entry falls through to its parent, so punctuation inside a string stays a
/// string.
const _scopeClasses = <String, String>{
  'comment.block.documentation': 'doc',
  'comment': 'comment',
  'string': 'string',
  'constant.character.escape': 'string',
  'constant.numeric': 'number',
  'constant.language': 'keyword',
  'keyword.operator.pipe': 'punct',
  'keyword.operator': 'operator',
  'keyword.other.prompt': 'prompt',
  'keyword.kind': 'kind',
  'keyword': 'keyword',
  'storage.type.annotation': 'annotation',
  'storage': 'keyword',
  'variable.language': 'keyword',
  'variable.other.flag': 'flag',
  'support.class': 'type',
  'support.type.property-name': 'key',
  'entity.name.tag.path': 'path',
  'entity.name.tag': 'key',
  'entity.name.command': 'command',
  'entity.name.declaration': 'name',
  'entity.name.function': 'function',
  'entity.name.type': 'type',
  'meta.embedded.expression': 'annotation',
  'markup.inserted': 'summary',
  'markup.changed': 'ask',
  'invalid.hint': 'hint',
};

/// Highlights [source] and wraps each line in a `span.line`, which lets CSS
/// mark the 1-based [deadLines] as dead code.
List<Component> highlight(
  String source,
  Language language, {
  Set<int> deadLines = const {},
}) => [
  for (final (index, line) in highlightLines(source, language).indexed) ...[
    if (index > 0) const Component.text('\n'),
    span(classes: deadLines.contains(index + 1) ? 'line dead' : 'line', line),
  ],
];

/// Highlights [source] and returns the tokens of each line separately, for
/// callers that lay lines out themselves.
List<List<Component>> highlightLines(String source, Language language) {
  final highlighter = _highlighters.putIfAbsent(
    language,
    () => sh.Highlighter(language: language.name, theme: _theme),
  );
  final lines = <List<Component>>[<Component>[]];
  for (final (text, className) in _flatten(highlighter.highlight(source))) {
    final parts = text.split('\n');
    for (final (index, part) in parts.indexed) {
      if (index > 0) {
        lines.add(<Component>[]);
      }
      if (part.isEmpty) {
        continue;
      }
      lines.last.add(
        className == null
            ? Component.text(part)
            : span(classes: 'tk-$className', [Component.text(part)]),
      );
    }
  }
  return lines;
}

/// Walks the span tree into `(text, class)` runs, in document order.
Iterable<(String, String?)> _flatten(sh.TextSpan node) sync* {
  if (node.text case final text?) {
    yield (text, _classFor(node.scopes));
  }
  for (final child in node.children) {
    yield* _flatten(child);
  }
}

String? _classFor(List<String> scopes) {
  for (final scope in scopes.reversed) {
    final parts = scope.split('.');
    for (var length = parts.length; length > 0; length--) {
      final className = _scopeClasses[parts.take(length).join('.')];
      if (className != null) {
        return className;
      }
    }
  }
  return null;
}
