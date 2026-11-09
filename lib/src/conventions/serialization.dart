import 'package:ciach/src/collect/candidates.dart';
import 'package:ciach/src/source/outline.dart';

/// Return types of a `toJson` hook.
const _jsonValueTypes = {
  'Map',
  'List',
  'String',
  'int',
  'double',
  'num',
  'bool',
  'Object',
  'dynamic',
};

/// Whether [candidate] is a `toJson()` hook: a parameterless method named
/// `toJson` returning a JSON value type. `jsonEncode` calls it without a
/// source-level reference, so it is exempt from the reference check.
bool isToJsonHook(Candidate candidate) => switch (candidate.outline.element) {
  OutlineElement(
    kind: .method,
    name: 'toJson',
    hasNoParameters: true,
    :final returnType?,
  ) =>
    // The source of the return type, like `Map<String, dynamic>?`.
    _jsonValueTypes.contains(
      returnType.split(RegExp('[<?]')).first.trimRight(),
    ),
  _ => false,
};
