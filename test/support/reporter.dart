import 'package:ciach/ciach.dart';

/// A run that found [unused], with the counts and timing the reports show.
FinderResult resultWith(
  List<UnusedDeclaration> unused, {
  List<UnusedDeclaration> docOnly = const [],
  List<RecoveredReference> recoveredReferences = const [],
  List<AnalysisProblem> problems = const [],
}) => .new(
  unused: unused,
  docOnly: docOnly,
  filesScanned: 3,
  declarationsChecked: 10,
  elapsed: const .new(seconds: 1),
  recoveredReferences: recoveredReferences,
  problems: problems,
);

/// A recovered reference, every field defaulted.
RecoveredReference warning({
  String name = 'baz',
  String? container = 'A',
  String filePath = 'lib/a.dart',
  int line = 4,
  int column = 7,
  String usageFilePath = 'lib/b.dart',
  int usageLine = 9,
  int usageColumn = 2,
}) => .new(
  name: name,
  container: container,
  filePath: filePath,
  line: line,
  column: column,
  usageFilePath: usageFilePath,
  usageLine: usageLine,
  usageColumn: usageColumn,
);

/// An analysis problem, every field defaulted.
AnalysisProblem problem({
  String summary = 'Could not find the references; kept.',
  String cause = 'Null check operator used on a null value',
  String filePath = 'lib/a.dart',
  int? line = 3,
  int? column = 5,
  String? name = 'A.foo',
  String? detail = '#0      Foo.bar',
}) => .new(
  summary: summary,
  cause: cause,
  filePath: filePath,
  line: line,
  column: column,
  name: name,
  detail: detail,
);

/// A finding, every field defaulted, whose range covers its name.
UnusedDeclaration decl({
  String name = 'foo',
  SymbolKind kind = .function,
  String filePath = 'lib/a.dart',
  int line = 3,
  int column = 5,
  bool isPrivate = false,
  String? container,
  bool removalBlocked = false,
  String? hint,
  List<DeadReferrer> onlyReferencedFrom = const [],
}) => .new(
  name: name,
  kind: kind,
  filePath: filePath,
  line: line,
  column: column,
  isPrivate: isPrivate,
  container: container,
  removalBlocked: removalBlocked,
  hint: hint,
  onlyReferencedFrom: onlyReferencedFrom,
  range: (
    startLine: line - 1,
    startColumn: column - 1,
    endLine: line - 1,
    endColumn: column - 1 + name.length,
  ),
);

/// Dead referrers for a finding's `onlyReferencedFrom`.
const rootReferrer = (qualifiedName: '_root', filePath: 'lib/a.dart', line: 1);
const otherReferrer = (
  qualifiedName: '_other',
  filePath: 'lib/b.dart',
  line: 7,
);
