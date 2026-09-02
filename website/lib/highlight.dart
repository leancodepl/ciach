/// A tiny build-time syntax highlighter.
///
/// Runs on the server while the site is pre-rendered, so the browser receives
/// finished `<span>` markup and never downloads a highlighting library.
library;

import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

enum Language { dart, yaml, shell, console, json }

/// Highlights [source] line by line. Each line becomes a `span.line`, which
/// lets CSS number lines and mark the ones listed in [deadLines] (1-based) as
/// dead code.
List<Component> highlight(
  String source,
  Language language, {
  Set<int> deadLines = const {},
}) {
  final lines = source.split('\n');
  return [
    for (final (index, line) in lines.indexed) ...[
      if (index > 0) const Component.text('\n'),
      span(
        classes: deadLines.contains(index + 1) ? 'line dead' : 'line',
        _tokenizeLine(line, language),
      ),
    ],
  ];
}

class _Rule {
  _Rule(String pattern, this.className) : pattern = RegExp(pattern);

  final RegExp pattern;

  /// `null` renders the match as plain text, useful for consuming indentation.
  final String? className;
}

const _dartKeywords = [
  'abstract', 'as', 'assert', 'async', 'await', 'base', 'break', 'case', //
  'catch', 'class', 'const', 'continue', 'covariant', 'default', 'deferred',
  'do', 'dynamic', 'else', 'enum', 'export', 'extends', 'extension',
  'external', 'factory', 'false', 'final', 'finally', 'for', 'Function',
  'get', 'hide', 'if', 'implements', 'import', 'in', 'interface', 'is',
  'late', 'library', 'mixin', 'new', 'null', 'on', 'operator', 'part',
  'required', 'rethrow', 'return', 'sealed', 'set', 'show', 'static',
  'super', 'switch', 'sync', 'this', 'throw', 'true', 'try', 'typedef',
  'var', 'void', 'when', 'while', 'with', 'yield',
];

final _dartRules = [
  _Rule(r'///.*', 'doc'),
  _Rule('//.*', 'comment'),
  _Rule(r"'(?:[^'\\]|\\.)*'", 'string'),
  _Rule(r'"(?:[^"\\]|\\.)*"', 'string'),
  _Rule(r'@[A-Za-z_]\w*', 'annotation'),
  _Rule('\\b(?:${_dartKeywords.join('|')})\\b', 'keyword'),
  _Rule(r'\b[A-Z][A-Za-z0-9_]*\b', 'type'),
  _Rule(r'\b\d+(?:\.\d+)?\b', 'number'),
  _Rule(r'\b[a-z_]\w*(?=\()', 'function'),
];

final _yamlRules = [
  _Rule('#.*', 'comment'),
  _Rule(r'(?<=^\s*|^\s*- )[\w.-]+(?=\s*:(?:\s|$))', 'key'),
  _Rule(r"'(?:[^'\\]|\\.)*'", 'string'),
  _Rule(r'"(?:[^"\\]|\\.)*"', 'string'),
  _Rule(r'\$\{\{.*?\}\}', 'annotation'),
  _Rule(r'\b(?:true|false|on|off|yes|no)\b', 'keyword'),
  _Rule(r'\b\d+(?:\.\d+)?\b', 'number'),
  _Rule(r'(?<=\s|^)--?[\w-]+', 'flag'),
];

final _shellRules = [
  _Rule(r'^\$(?=\s)', 'prompt'),
  _Rule('#.*', 'comment'),
  _Rule(r'(?<=^\$\s+)[\w./-]+', 'command'),
  _Rule(r'(?<=^\$\s+[\w./-]+\s+)(?:run|pub|global|activate|add)\b', 'command'),
  _Rule(r"'(?:[^'\\]|\\.)*'", 'string'),
  _Rule(r'"(?:[^"\\]|\\.)*"', 'string'),
  _Rule(r'(?<=\s)--?[\w-]+', 'flag'),
  _Rule(r'(?<=\s)\|(?=\s)', 'punct'),
];

final _jsonRules = [
  _Rule(r'"(?:[^"\\]|\\.)*"(?=\s*:)', 'key'),
  _Rule(r'"(?:[^"\\]|\\.)*"', 'string'),
  _Rule(r'\b(?:true|false|null)\b', 'keyword'),
  _Rule(r'-?\b\d+(?:\.\d+)?\b', 'number'),
];

final _rules = {
  Language.dart: _dartRules,
  Language.yaml: _yamlRules,
  Language.shell: _shellRules,
  Language.json: _jsonRules,
};

final _findingLine = RegExp(
  r'^(\s+)(\d+:\d+)(\s+)'
  '(class|mixin|interface|enum value|enum|extension|function|method|'
  'constructor|field|property|getter|setter|variable|constant)'
  r'(\s+)(\S+)(\s+)\((public|private)\)(.*)$',
);
final _pathLine = RegExp(r'^[\w./-]+\.dart$');
final _annotationLine = RegExp(r'^(::(?:warning|notice|error)) ([^:]*)::(.*)$');
final _verboseLine = RegExp(r'^(\[\s*[\d.]+s\])(.*)$');

List<Component> _tokenizeLine(String line, Language language) {
  if (language == Language.console) {
    return _consoleLine(line);
  }
  return _tokenizeWith(line, _rules[language]!);
}

List<Component> _tokenizeWith(String line, List<_Rule> rules) {
  final out = <Component>[];
  final plain = StringBuffer();
  var index = 0;

  void flush() {
    if (plain.isNotEmpty) {
      out.add(Component.text(plain.toString()));
      plain.clear();
    }
  }

  outer:
  while (index < line.length) {
    for (final rule in rules) {
      final match = rule.pattern.matchAsPrefix(line, index);
      if (match != null && match.end > index) {
        flush();
        final text = match[0]!;
        if (rule.className case final className?) {
          out.add(span(classes: 'tk-$className', [Component.text(text)]));
        } else {
          out.add(Component.text(text));
        }
        index = match.end;
        continue outer;
      }
    }
    plain.write(line[index]);
    index++;
  }
  flush();
  return out;
}

/// Terminal transcripts mix a shell prompt with ciach's own output, so they
/// are matched whole-line against the shapes ciach prints.
List<Component> _consoleLine(String line) {
  if (line.startsWith(r'$ ')) {
    return _tokenizeWith(line, _shellRules);
  }
  if (_findingLine.firstMatch(line) case final match?) {
    return [
      Component.text(match[1]!),
      span(classes: 'tk-number', [Component.text(match[2]!)]),
      Component.text(match[3]!),
      span(classes: 'tk-kind', [Component.text(match[4]!)]),
      Component.text(match[5]!),
      span(classes: 'tk-name', [Component.text(match[6]!)]),
      Component.text(match[7]!),
      span(classes: 'tk-vis', [Component.text('(${match[8]})')]),
      if (match[9]!.isNotEmpty)
        span(classes: 'tk-hint', [Component.text(match[9]!)]),
    ];
  }
  if (_annotationLine.firstMatch(line) case final match?) {
    return [
      span(classes: 'tk-keyword', [Component.text(match[1]!)]),
      const Component.text(' '),
      span(classes: 'tk-flag', [Component.text(match[2]!)]),
      const span(classes: 'tk-punct', [Component.text('::')]),
      span(classes: 'tk-name', [Component.text(match[3]!)]),
    ];
  }
  if (_verboseLine.firstMatch(line) case final match?) {
    return [
      span(classes: 'tk-comment', [Component.text(match[1]!)]),
      Component.text(match[2]!),
    ];
  }
  if (_pathLine.hasMatch(line)) {
    return [
      span(classes: 'tk-path', [Component.text(line)]),
    ];
  }
  if (line.startsWith('Found ') || line.startsWith('Removed ')) {
    return [
      span(classes: 'tk-summary', [Component.text(line)]),
    ];
  }
  if (line.startsWith('Remove ')) {
    return [
      span(classes: 'tk-ask', [Component.text(line)]),
    ];
  }
  if (line.startsWith('Referenced only') || line.startsWith('warning:')) {
    return [
      span(classes: 'tk-comment', [Component.text(line)]),
    ];
  }
  return [Component.text(line)];
}
