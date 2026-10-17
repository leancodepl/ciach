/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 *   plugins:
 *     - lean-ai-provenance
 *   skills:
 *     - mark-ai-provenance
 */

/// Reads the calls that a function makes into the pipeline directories of
/// `lib/src/`, from ciach's resolved source, without running it.
///
/// A call into another file of a pipeline directory becomes a [Call], and the
/// calls that the callee makes become its children, up to [maxDepth] files
/// deep. A call to a function in the same file, such as a private helper or
/// a local function, adds that function's calls in its place.
library;

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:path/path.dart' as p;

/// The directories of `lib/src/` whose functions are steps of a scan. The
/// others hold data (`model/`), source text and the tokens of it (`source/`),
/// the server connection (`lsp/`) or helpers (`util/`), and calls into them
/// are left out.
const pipelineDirectories = {
  'workspace',
  'conventions',
  'project_config',
  'collect',
  'fetch',
  'settle',
};

/// How many files deep the calls are followed from the starting function.
const maxDepth = 2;

/// A call that a scan makes into a pipeline directory.
final class Call({
  /// The callee, such as `Settler.settle` or `discoverDartFilesSplit`.
  required final String name,

  /// The directory of `lib/src/` that declares the callee, such as `settle`.
  required final String directory,

  /// The source of the `if` conditions and loops around the call, from the
  /// outermost in, such as `if (options.transitive)` or `in a loop`.
  required final List<String> conditions,

  /// The calls that the callee makes.
  required final List<Call> children,
});

/// Returns the calls that the method [methodName] of the class [className] in
/// [path] makes. [packageRoot] is the absolute path of the ciach package.
Future<List<Call>> callsFrom({
  required String packageRoot,
  required String path,
  required String className,
  required String methodName,
}) async {
  final sourceRoot = p.join(packageRoot, 'lib', 'src');
  final collection = AnalysisContextCollection(includedPaths: [sourceRoot]);
  final bodies = <Element, FunctionBody>{};
  for (final context in collection.contexts) {
    for (final file in context.contextRoot.analyzedFiles()) {
      if (!file.endsWith('.dart')) {
        continue;
      }
      if (await context.currentSession.getResolvedUnit(file)
          case final ResolvedUnitResult unit) {
        unit.unit.accept(_BodyIndex(bodies));
      }
    }
  }

  final start = bodies.entries.firstWhere(
    (entry) =>
        entry.key.name == methodName &&
        entry.key.enclosingElement?.name == className &&
        _pathOf(entry.key) == path,
  );
  return _CallReader(bodies, sourceRoot).read(start.key, start.value, 0);
}

String? _pathOf(Element element) =>
    element.firstFragment.libraryFragment?.source.fullName;

/// Collects the body of each function, method and constructor.
final class _BodyIndex(final Map<Element, FunctionBody> bodies)
    extends RecursiveAstVisitor<void> {
  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {
    if (node.declaredFragment?.element case final element?) {
      bodies[element] = node.functionExpression.body;
    }
    super.visitFunctionDeclaration(node);
  }

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    if (node.declaredFragment?.element case final element?) {
      bodies[element] = node.body;
    }
    super.visitMethodDeclaration(node);
  }

  @override
  void visitConstructorDeclaration(ConstructorDeclaration node) {
    if (node.declaredFragment?.element case final element?) {
      bodies[element] = node.body;
    }
    super.visitConstructorDeclaration(node);
  }
}

final class _CallReader(
  final Map<Element, FunctionBody> bodies,
  final String sourceRoot,
) {
  /// The functions whose calls are being read, so that recursion stops.
  final _reading = <Element>{};

  List<Call> read(Element function, FunctionBody body, int depth) {
    if (!_reading.add(function)) {
      return const [];
    }
    final visitor = _CallVisitor(this, _pathOf(function), depth);
    body.accept(visitor);
    _reading.remove(function);
    return visitor.calls;
  }

  /// The directory of `lib/src/` that declares [element], or `null` outside
  /// `lib/src/`.
  String? directoryOf(Element element) {
    final path = _pathOf(element);
    if (path == null || !p.isWithin(sourceRoot, path)) {
      return null;
    }
    return p.split(p.relative(path, from: sourceRoot)).first;
  }
}

final class _CallVisitor(
  final _CallReader reader,
  final String? path,
  final int depth,
) extends RecursiveAstVisitor<void> {
  final calls = <Call>[];
  final _conditions = <String>[];

  @override
  void visitMethodInvocation(MethodInvocation node) {
    // The receiver and the arguments run before the call.
    super.visitMethodInvocation(node);
    if (node.methodName.element case final ExecutableElement element) {
      _called(element.baseElement);
    }
  }

  @override
  void visitIfStatement(IfStatement node) {
    node.expression.accept(this);
    _under('if (${node.expression.toSource()})', node.thenStatement);
    _under('unless (${node.expression.toSource()})', node.elseStatement);
  }

  @override
  void visitIfElement(IfElement node) {
    node.expression.accept(this);
    _under('if (${node.expression.toSource()})', node.thenElement);
    _under('unless (${node.expression.toSource()})', node.elseElement);
  }

  @override
  void visitConditionalExpression(ConditionalExpression node) {
    node.condition.accept(this);
    _under('if (${node.condition.toSource()})', node.thenExpression);
    _under('unless (${node.condition.toSource()})', node.elseExpression);
  }

  @override
  void visitForStatement(ForStatement node) => _under('in a loop', node.body);

  @override
  void visitWhileStatement(WhileStatement node) =>
      _under('in a loop', node.body);

  void _under(String condition, AstNode? node) {
    if (node == null) {
      return;
    }
    _conditions.add(condition);
    node.accept(this);
    _conditions.removeLast();
  }

  void _called(Element callee) {
    final body = reader.bodies[callee];
    if (body == null) {
      return;
    }
    // A function of the same file adds its calls in its place, under the
    // conditions of the call.
    if (_pathOf(callee) == path) {
      for (final call in reader.read(callee, body, depth)) {
        calls.add(
          Call(
            name: call.name,
            directory: call.directory,
            conditions: [..._conditions, ...call.conditions],
            children: call.children,
          ),
        );
      }
      return;
    }
    final directory = reader.directoryOf(callee);
    if (directory == null || !pipelineDirectories.contains(directory)) {
      return;
    }
    calls.add(
      Call(
        name: [
          if (callee.enclosingElement case InterfaceElement(:final name?)) name,
          callee.name,
        ].join('.'),
        directory: directory,
        conditions: [..._conditions],
        children: depth + 1 < maxDepth
            ? reader.read(callee, body, depth + 1)
            : const [],
      ),
    );
  }
}
