/// A TextMate grammar for ciach's own terminal output, so transcripts get the
/// same treatment as real languages: file headers, findings, summaries,
/// GitHub Actions workflow commands and `-v` timestamps.
library;

import 'package:ciach_website/grammars/shell_grammar.dart';

const _kinds =
    'class|mixin|interface|enum value|enum|extension|function|method|'
    'constructor|field|property|getter|setter|variable|constant';

/// Whole-line shapes come first so their pieces are not mistaken for shell
/// tokens; prompt lines fall through to the shared shell patterns.
const kConsoleGrammar =
    '''
{
  "name": "ciach output",
  "scopeName": "source.ciach",
  "patterns": [
    {
      "name": "entity.name.tag.path.ciach",
      "match": "^[\\\\w./-]+\\\\.dart\$"
    },
    {
      "name": "constant.numeric.position.ciach",
      "match": "(?<=^\\\\s+)\\\\d+:\\\\d+(?=\\\\s)"
    },
    {
      "name": "keyword.kind.ciach",
      "match": "(?<=^\\\\s+\\\\d+:\\\\d+\\\\s+)(?:$_kinds)(?=\\\\s)"
    },
    {
      "name": "entity.name.declaration.ciach",
      "match": "(?<=^\\\\s+\\\\d+:\\\\d+\\\\s+(?:$_kinds)\\\\s+)\\\\S+"
    },
    {
      "name": "comment.visibility.ciach",
      "match": "\\\\((?:public|private)\\\\)"
    },
    {
      "name": "invalid.hint.ciach",
      "match": "(?<=\\\\((?:public|private)\\\\)\\\\s+)\\\\(.*\\\\)\$"
    },
    {
      "name": "keyword.control.annotation.ciach",
      "match": "^::(?:warning|notice|error)\\\\b"
    },
    {
      "name": "variable.other.flag.ciach",
      "match": "(?<=^::(?:warning|notice|error) )[^:]+(?=::)"
    },
    {
      "name": "entity.name.declaration.ciach",
      "match": "(?<=^::(?:warning|notice|error) [^:]+::).*\$"
    },
    {
      "name": "comment.timestamp.ciach",
      "match": "^\\\\[\\\\s*[\\\\d.]+s\\\\]"
    },
    {
      "name": "markup.inserted.summary.ciach",
      "match": "^(?:Found|Removed) .*\$"
    },
    {
      "name": "markup.changed.ask.ciach",
      "match": "^Remove .*\$"
    },
    {
      "name": "comment.note.ciach",
      "match": "^(?:Referenced only|warning:).*\$"
    },
$kShellPatterns
  ]
}''';
