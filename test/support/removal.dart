import 'dart:io';

import 'package:ciach/ciach.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Writes [content] to `<dir>/lib.dart`, removes [decls] from it, and returns
/// the resulting content, or `''` if the file was deleted.
String removeFrom(
  Directory dir,
  String content,
  List<UnusedDeclaration> decls,
) {
  final file = File(p.join(dir.path, 'lib.dart'))..writeAsStringSync(content);
  removeDeclarations(decls, dir.path);
  return file.existsSync() ? file.readAsStringSync() : '';
}

/// A finding in `lib.dart` whose doc comment or annotations start at
/// [docLine]:[docColumn].
UnusedDeclaration decl({
  required int startLine,
  required int startColumn,
  required int endLine,
  required int endColumn,
  SymbolKind kind = .function,
  bool isEnumValue = false,
  int? docLine,
  int? docColumn,
}) => .new(
  name: 'x',
  kind: kind,
  filePath: 'lib.dart',
  line: startLine + 1,
  column: startColumn + 1,
  isPrivate: false,
  isEnumValue: isEnumValue,
  range: (
    startLine: startLine,
    startColumn: startColumn,
    endLine: endLine,
    endColumn: endColumn,
  ),
  fullRange: (
    startLine: docLine ?? startLine,
    startColumn: docColumn ?? (docLine == null ? startColumn : 0),
    endLine: endLine,
    endColumn: endColumn,
  ),
);

/// A cheap brace-balance check so a regression that mangles a removal shows
/// up in these fast unit tests, without needing the full analyzer.
void expectBalanced(String source) {
  var depth = 0;
  for (final ch in source.split('')) {
    if (ch == '{') {
      depth++;
    }
    if (ch == '}') {
      depth--;
    }
    expect(depth, greaterThanOrEqualTo(0), reason: 'unbalanced braces');
  }
  expect(depth, 0, reason: 'unbalanced braces');
}
