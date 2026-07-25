// Deliberately does NOT import xref_event.dart — the dot-shorthand below
// resolves through the parameter's context type without that import.

import 'package:sample_pkg/xref_analytics.dart';
import 'package:sample_pkg/xref_shapes.dart';

String describeShape(XrefState state) => switch (state) {
  XrefLoadedState(hasActive: true, ready: true) => 'both',
  _ => 'other',
};

void emitSignOut(XrefAnalytics analytics) => analytics.logEvent(.signOut);
