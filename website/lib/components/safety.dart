import 'package:ciach_website/components/code_block.dart';
import 'package:ciach_website/components/section.dart';
import 'package:ciach_website/highlight.dart';
import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

class _Skip {
  const _Skip(this.what, this.why, this.flag);

  final String what;
  final String why;
  final String? flag;
}

const _skips = [
  _Skip('main', 'The entry point is never unused.', null),
  _Skip(
    '@override members',
    'Often reached polymorphically or by a framework (build, initState, ==, …), '
        'which a name-based search misses.',
    '--overrides',
  ),
  _Skip(
    'Operator overloads',
    'The server doesn’t resolve a + b back to the declaration, so a used '
        'operator would be flagged every time.',
    '--operators',
  ),
  _Skip(
    'call methods',
    'Implicit-call syntax obj(…) is unresolvable the same way.',
    null,
  ),
  _Skip(
    "@pragma('vm:entry-point')",
    'Reachable from native code or reflection.',
    null,
  ),
  _Skip(
    'Generated files',
    'By filename convention (*.g.dart, *.freezed.dart, …) and the GENERATED CODE '
        'banner. Still opened during analysis, so a declaration used only from a '
        '.g.dart isn’t misreported.',
    '--generated',
  ),
  _Skip(
    'toJson()',
    'jsonEncode(obj) calls it by dynamic dispatch, leaving no source-level reference.',
    '--report-tojson',
  ),
  _Skip('Type parameters', 'Always “used” within their scope.', null),
  _Skip(
    'dartdoc [Xxx] links',
    'Not a code reference: reported as doc-only instead of hidden.',
    null,
  ),
];

const _docOnly = '''
lib/greeting.dart
  15:6  function  danglingFunction  (public)

Referenced only from doc comments — not counted as unused, never removed:
lib/greeting.dart
  40:6  function  docOnlyMentioned  (public)''';

class Safety extends StatelessComponent {
  const Safety({super.key});

  @override
  Component build(BuildContext context) {
    return Section(
      id: 'safety',
      eyebrow: 'Safety',
      heading: 'Sharp, but it knows when to hold back.',
      lead:
          'Each default skip is a known source of false positives. The flag '
          'in the last column opts back in, at that cost.',
      children: [
        div(classes: 'table-wrap', [
          table(classes: 'skips', [
            const caption(classes: 'sr-only', [
              Component.text('What ciach skips by default and why'),
            ]),
            const thead([
              tr([
                th(attributes: {'scope': 'col'}, [Component.text('Skipped')]),
                th(attributes: {'scope': 'col'}, [Component.text('Why')]),
                th(
                  attributes: {'scope': 'col'},
                  [Component.text('Opt back in')],
                ),
              ]),
            ]),
            tbody([
              for (final skip in _skips)
                tr([
                  th(
                    attributes: const {'scope': 'row'},
                    [
                      code([Component.text(skip.what)]),
                    ],
                  ),
                  td([Component.text(skip.why)]),
                  td([
                    if (skip.flag case final flag?)
                      code(classes: 'flag', [Component.text(flag)])
                    else
                      const span(classes: 'muted', [Component.text('—')]),
                  ]),
                ]),
            ]),
          ]),
        ]),
        const div(classes: 'safety-grid', [
          div(classes: 'card', [
            h3([Component.text('Doc-only findings')]),
            p([
              Component.text(
                'A dartdoc [Xxx] link resolves to a real declaration, so the '
                'analysis server counts it as a reference — but a comment '
                'mentioning something isn’t code calling it. Declarations with '
                'no code references are reported separately in every format, '
                'never count toward the exit code and are never removed.',
              ),
            ]),
            CodeBlock(code: _docOnly, language: Language.console, copyText: ''),
          ]),
          div(classes: 'card', [
            h3([Component.text('Known limitations, stated up front')]),
            p([
              Component.text(
                'This is a static, reference-based heuristic. Review the diff '
                'rather than deleting blindly, and keep these in mind:',
              ),
            ]),
            ul(classes: 'checklist', [
              li([
                Component.text(
                  'A library package’s public API is legitimately unused from '
                  'inside the package. Prefer --no-public there, or treat public '
                  'findings as advisory.',
                ),
              ]),
              li([
                Component.text(
                  'Reflection, dynamic invocation and names referenced only from '
                  'generated code you excluded are invisible to a reference search.',
                ),
              ]),
              li([
                Component.text(
                  'Entry points other than main — isolate entry points, plugin '
                  "registrants — need excluding or @pragma('vm:entry-point').",
                ),
              ]),
              li([
                Component.text(
                  'A package that doesn’t analyze cleanly yields incomplete '
                  'references. Run pub get and fix errors first.',
                ),
              ]),
            ]),
          ]),
        ]),
      ],
    );
  }
}
