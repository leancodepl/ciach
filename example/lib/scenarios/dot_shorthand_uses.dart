// Uses for the dot-shorthand fixture: every reference to a declaration in
// scenarios/dot_shorthands.dart is a `.name` shorthand, never the long
// `Weight.value`/`Palette.member` form. Each helper covers one context a
// shorthand is allowed in. Expected findings are asserted by
// test/finder_test.dart; keep in sync.

import 'package:sample_pkg/scenarios/dot_shorthands.dart';

/// The single public entry point: every helper below hangs off it, so the file
/// contributes no findings of its own beyond this function.
void exerciseDotShorthands() {
  _arguments();
  _initializersAndReturns();
  _literals();
  _patterns();
  _conditionals();
  _constContexts();
  _assignmentAndTypeArguments();
  _staticHeads();
  _nestedConstructors();
  // The same-file shorthand, and the annotated helper's own annotation.
  print(sameFileWeight);
  _annotated();
}

// -- Argument positions -------------------------------------------------------

void _arguments() {
  _describe(.positional);
  _describeNamed(weight: .named);
}

String _describe(Weight weight) => weight.name;

String _describeNamed({required Weight weight}) => weight.name;

// -- Initializers, returns, yields --------------------------------------------

void _initializersAndReturns() {
  const Weight local = .variableInit;
  print([local, _Holder().weight, _arrow(), _block(), _sync().first]);
  print(_async());
}

class _Holder {
  final Weight weight = .fieldInit;
}

Weight _arrow() => .arrowReturn;

Weight _block() {
  return .blockReturn;
}

Future<Weight> _async() async => .asyncReturn;

Iterable<Weight> _sync() sync* {
  yield .yielded;
}

// -- Collection, record, and map literals -------------------------------------

void _literals() {
  const list = <Weight>[.listElement];
  const set = <Weight>{.setElement};
  const map = <Weight, Weight>{.mapKey: .mapValue};
  const (Weight, String) record = (.recordField, 'record');
  print([list, set, map, record]);
}

// -- Patterns -----------------------------------------------------------------

void _patterns() {
  final weight = _arrow();
  switch (weight) {
    case .switchCase:
      print('switch case');
    default:
      print('other');
  }
  print(switch (weight) {
    .switchArm => 'switch arm',
    _ => 'other',
  });
  if (weight case .ifCase) {
    print('if-case');
  }
}

/// A constant pattern whose constant is a static field, not an enum value.
void _constantPattern(Palette palette) {
  if (palette case .patternField) {
    print('pattern-field pattern');
  }
}

// -- Operators and conditionals -----------------------------------------------

void _conditionals() {
  final weight = _arrow();
  print(weight == .equality);
  final Weight branched = weight.index.isEven ? .ternaryThen : .ternaryElse;
  const Weight? absent = null;
  const Weight fallback = absent ?? .ifNull;
  print([branched, fallback]);
}

// -- Constant contexts --------------------------------------------------------

void _constContexts() {
  _defaulted();
  const marker = Marker(.constArg);
  print(marker.weight);
}

void _defaulted({Weight weight = .paramDefault}) => print(weight);

@Marker(.annotationArg)
void _annotated() => print('annotated');

// -- Assignment, and a context type from an inferred type argument ------------

void _assignmentAndTypeArguments() {
  var weight = _arrow();
  weight = .assignment;
  print([weight, ...List<Weight>.filled(1, .typeArgument)]);
}

// -- Static, constructor, and enum-static heads -------------------------------

void _staticHeads() {
  final Tier tier = .standard;
  final Palette unnamedCtor = .new('unnamed');
  final Palette namedCtor = .of('named');
  const Palette staticField = .constField;
  final Palette staticGetter = .getter;
  final Palette staticMethod = .parse('parsed');
  // A shorthand whose arguments are themselves shorthands — see
  // _nestedConstructors for the constructor flavor.
  final Palette nested = .blend(.nestedFirst, .nestedSecond);
  // A shorthand head followed by a further selector, and by a cascade.
  final Palette chained = .chainSeed.brightened();
  final Palette cascaded = .cascadeSeed..brightened();
  final Box<int> box = .filled(1);
  _constantPattern(staticMethod);
  print([
    tier,
    unnamedCtor,
    namedCtor,
    staticField,
    staticGetter,
    staticMethod,
    nested,
    chained,
    cascaded,
    box.value,
  ]);
}

// -- Nested constructor shorthands --------------------------------------------

void _nestedConstructors() {
  // Three unnamed heads in one expression, each a different class's
  // constructor: `Layer.new`, then `Depth.new`, then `Tint.new`. Nothing but
  // the context type says which is which.
  final Layer nestedUnnamed = .new(.new(.new(1)));
  // A named constructor nested in a static-method shorthand.
  final Palette nestedNamed = .tinted(.step(2));
  print([nestedUnnamed.depth.tint.level, nestedNamed]);
  // The type is referenced, but no shorthand ever constructs it.
  _typeOnly(null);
}

void _typeOnly(DeadLayer? layer) => print(layer);
