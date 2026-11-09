/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

part of 'unit_outline.dart';

/// Collects the outlines of the local functions in a body, and of the
/// `test(...)` and `group(...)` calls, with the outlines inside each group.
final class _BodyOutlines extends RecursiveAstVisitor<void> {
  _BodyOutlines(this._builder);

  final _OutlineBuilder _builder;
  final outlines = <Outline>[];

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) =>
      outlines.add(_builder._function(node));

  /// Adds a call of a test or group function. Like the analysis server, it
  /// skips the arguments of a call that resolves to no function or method,
  /// such as a call of a function that doesn't exist.
  @override
  void visitMethodInvocation(MethodInvocation node) {
    switch (node.methodName.element) {
      case final ExecutableElement element when _isGroup(element):
        final group = _BodyOutlines(_builder);
        node.argumentList.accept(group);
        outlines.add(_call(node, .unitTestGroup, group.outlines));
      case final ExecutableElement element when _isTest(element):
        outlines.add(_call(node, .unitTestTest, const []));
      case ExecutableElement():
        super.visitMethodInvocation(node);
    }
  }

  /// The outline of the test or group call [node], named after the function
  /// that it calls.
  Outline _call(MethodInvocation node, OutlineKind kind, List<Outline> inside) {
    final range = node.range;
    return .new(
      element: .new(
        kind: kind,
        name: node.methodName.name,
        range: node.methodName.range,
      ),
      range: range,
      codeRange: range,
      children: inside,
    );
  }

  /// Whether [element] is annotated `@isTestGroup`, or is `group` from a
  /// library whose file name ends with `test.dart`.
  static bool _isGroup(ExecutableElement element) =>
      element.metadata.hasIsTestGroup || _isTestFunction(element, 'group');

  /// Whether [element] is annotated `@isTest`, or is `test` from a library
  /// whose file name ends with `test.dart`.
  static bool _isTest(ExecutableElement element) =>
      element.metadata.hasIsTest || _isTestFunction(element, 'test');

  static bool _isTestFunction(ExecutableElement element, String name) =>
      switch (element) {
        TopLevelFunctionElement(:final library) =>
          element.name == name &&
              library.firstFragment.source.fullName.endsWith('test.dart'),
        _ => false,
      };
}
