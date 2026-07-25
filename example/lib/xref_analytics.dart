// Fixture for cross-library reference recovery (issue #25). Provides the
// context-typed API a dot-shorthand resolves against, and one normal reference.

import 'package:sample_pkg/xref_event.dart';

class XrefAnalytics {
  void logEvent(XrefEvent event) => print(event);
}

// A normal, imported reference -> keeps XrefEvent.signIn used.
const XrefEvent xrefControl = XrefEvent.signIn;
