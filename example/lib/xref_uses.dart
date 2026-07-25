// Deliberately does NOT import xref_event.dart — the dot-shorthand below
// resolves through the parameter's context type without that import.

import 'package:sample_pkg/xref_analytics.dart';
import 'package:sample_pkg/xref_shapes.dart';

String describeShape(XrefState state) => switch (state) {
  XrefLoadedState(hasActive: true, ready: true) => 'both',
  _ => 'other',
};

class Emitter {
  Emitter(this._analytics);
  final XrefAnalytics _analytics;

  // The enclosing method's name collides with the enum value it references via
  // a dot-shorthand, which is when find-references drops the cross-library use.
  void signOut() => _analytics.logEvent(.signOut);
}
