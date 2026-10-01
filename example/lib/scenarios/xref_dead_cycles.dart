// `XrefLoadedState.ready` is recovered from two sites here: a dead one first,
// then a live one. Asserted by test/finder_test.dart.

import 'package:sample_pkg/scenarios/xref_shapes.dart';

String _deadReady(XrefState state) => switch (state) {
  XrefLoadedState(ready: true) => 'ready',
  _ => 'other',
};

/// Called from bin/app.dart -> USED.
String liveReady(XrefState state) => switch (state) {
  XrefLoadedState(ready: true) => 'ready',
  _ => 'other',
};
