// Consumer for the cross-library reference-recovery fixtures. Imports the
// analytics API and the shape types, but NOT xref_event.dart — the dot-shorthand
// below resolves through the parameter's context type without that import.

import 'package:sample_pkg/xref_analytics.dart';
import 'package:sample_pkg/xref_shapes.dart';

// The ONLY references to XrefLoadedState.hasActive and XrefLoadedState.ready —
// a cross-file object pattern.
String describeShape(XrefState state) => switch (state) {
  XrefLoadedState(hasActive: true, ready: true) => 'both',
  _ => 'other',
};

// The ONLY reference to XrefEvent.signOut — a cross-library dot-shorthand.
void emitSignOut(XrefAnalytics analytics) => analytics.logEvent(.signOut);
