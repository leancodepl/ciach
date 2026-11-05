/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

import 'package:ciach/src/conventions/entry_points.dart';
import 'package:ciach/src/conventions/resolved_declaration.dart';
import 'package:ciach/src/lsp/outline.dart';
import 'package:ciach/src/lsp/semantic_tokens.dart';
import 'package:pro_lsp/pro_lsp.dart' show SymbolKind;
import 'package:test/test.dart';

import '../support/declarations.dart';

void main() {
  final rule = PigeonInputEntryPoint(files: const ['pigeons/messages.dart']);

  /// A top-level declaration in the input file, of the [outlineKind] and
  /// with the [keywords] before its name, annotated with each of
  /// [annotations].
  ResolvedDeclaration declaration(
    OutlineKind outlineKind, {
    Set<String> keywords = const {},
    List<String> annotations = const [],
    String path = 'pigeons/messages.dart',
  }) => .new(
    relativePath: path,
    symbol: symbol('Message', kind: .class$),
    outlineKind: outlineKind,
    keywords: keywords,
    leadingMetadata: [
      for (final annotation in annotations)
        SemanticToken(
          line: 0,
          character: 1,
          length: annotation.length,
          type: 'class',
          modifiers: const {'annotation'},
          text: annotation,
        ),
    ],
  );

  test('selects a class without `abstract`, such as a data class', () {
    for (final keywords in [
      {'class'},
      {'sealed', 'class'},
      {'final', 'class'},
    ]) {
      expect(
        rule.matches(declaration(.class$, keywords: keywords)),
        isTrue,
        reason: 'for $keywords',
      );
    }
  });

  test('selects an abstract class only with a Pigeon API annotation', () {
    expect(
      {
        for (final annotation in [
          'HostApi',
          'FlutterApi',
          'EventChannelApi',
          'ProxyApi',
          'Deprecated',
          null,
        ])
          annotation: rule.matches(
            declaration(
              .class$,
              keywords: const {'abstract', 'class'},
              annotations: [?annotation],
            ),
          ),
      },
      {
        'HostApi': true,
        'FlutterApi': true,
        'EventChannelApi': true,
        'ProxyApi': true,
        'Deprecated': false,
        null: false,
      },
    );
  });

  test('selects an enum and a `const` top-level variable', () {
    expect(
      (
        rule.matches(declaration(.enum$, keywords: const {'enum'})),
        rule.matches(declaration(.topLevelVariable, keywords: const {'const'})),
      ),
      (true, true),
    );
  });

  test('leaves out what Pigeon skips', () {
    for (final (kind, keywords) in [
      (OutlineKind.topLevelVariable, const <String>{}),
      (OutlineKind.topLevelVariable, const {'final'}),
      (OutlineKind.function, const <String>{}),
      (OutlineKind.mixin, const {'mixin'}),
      (OutlineKind.classTypeAlias, const {'class'}),
      (OutlineKind.typeAlias, const {'typedef'}),
      (OutlineKind.functionTypeAlias, const {'typedef'}),
      (OutlineKind.extension, const {'extension'}),
      (OutlineKind.extensionType, const {'extension', 'type'}),
    ]) {
      expect(
        rule.matches(declaration(kind, keywords: keywords)),
        isFalse,
        reason: 'for $kind with $keywords',
      );
    }
  });

  test('selects a declaration that `@ConfigurePigeon` annotates', () {
    for (final kind in [OutlineKind.function, OutlineKind.class$]) {
      expect(
        rule.matches(
          declaration(
            kind,
            keywords: const {'abstract', 'class'},
            annotations: const ['ConfigurePigeon'],
          ),
        ),
        isTrue,
        reason: 'for $kind',
      );
    }
  });

  test('selects nothing outside the input files', () {
    expect(
      rule.matches(
        declaration(.class$, keywords: const {'class'}, path: 'lib/a.dart'),
      ),
      isFalse,
    );
  });

  test('keeps every member of a type that it selects, private ones too', () {
    final members = EntryPoints([
      rule,
    ]).keptMembersOf(declaration(.class$, keywords: const {'class'}));
    expect(
      [
        for (final (name, kind) in [
          ('text', SymbolKind.field),
          ('_cache', SymbolKind.field),
          ('send', SymbolKind.method),
          ('Message', SymbolKind.constructor),
        ])
          members.any(
            (kept) => kept.selection.includes(symbol(name, kind: kind)),
          ),
      ],
      [true, true, true, true],
    );
  });

  test('selects no member by itself', () {
    expect(
      rule.matches(
        declarationAt(
          'pigeons/messages.dart',
          symbol('text', kind: .field),
          'Message',
        ),
      ),
      isFalse,
    );
  });
}
