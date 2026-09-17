import 'package:ciach/src/candidates.dart';
import 'package:ciach/src/symbols.dart';
import 'package:pro_lsp/pro_lsp.dart' show DocumentSymbol;

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
bool isToJsonHook(Candidate candidate) => switch (candidate.symbol) {
  DocumentSymbol(kind: .method, name: 'toJson', hasNoParameters: true) =>
    isJsonValueType(candidate.outline.element.returnType),
  _ => false,
};

/// Whether [returnType] (e.g. `Map<String, dynamic>?`) is a JSON value type.
bool isJsonValueType(String? returnType) {
  if (returnType == null) {
    return false;
  }
  var name = returnType.trim();
  if (name.endsWith('?')) {
    name = name.substring(0, name.length - 1).trimRight();
  }
  final typeArgs = name.indexOf('<');
  if (typeArgs >= 0) {
    name = name.substring(0, typeArgs).trimRight();
  }
  return _jsonValueTypes.contains(name);
}
