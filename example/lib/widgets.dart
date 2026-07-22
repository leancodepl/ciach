// Flutter-free stand-ins for the StatefulWidget / State pairing, so the
// dead-widget detection can be exercised without a Flutter dependency. The
// finder keys off the textual `State<Widget>` shape, so the stand-in must be
// named exactly `State` for the pairing to be recognised.
//
// Scanned only by the dedicated widget tests (excluded from the default-run
// assertions); see test/finder_test.dart.

/// Stand-in for Flutter's `State<T>`. USED via the `State<...>` pairings below.
abstract class State<T> {}

/// A fully dead StatelessWidget-style class: never constructed or referenced.
/// Its only "reference" is its own unnamed constructor declaration, so before
/// the dead-class detection it slipped through as used. Detected as a dead
/// CLASS (`DeadLeafWidget`); the `DeadLeafWidget.new` constructor is not
/// reported separately.
class DeadLeafWidget {
  const DeadLeafWidget();
}

/// A fully dead StatefulWidget: never used, and kept "referenced" only by its
/// own constructor, its `createState` return type, and its paired
/// `State<DeadStatefulWidget>` subclass. Detected as a dead CLASS. The paired
/// [_DeadStatefulWidgetState] is removed together with it (otherwise
/// `State<DeadStatefulWidget>` would dangle), but is not reported on its own.
///
/// `createState` here is a plain method; on a real Flutter widget it carries
/// an override annotation and is skipped. The class-level detection is what is
/// under test.
class DeadStatefulWidget {
  const DeadStatefulWidget();

  State<DeadStatefulWidget> createState() => _DeadStatefulWidgetState();
}

class _DeadStatefulWidgetState extends State<DeadStatefulWidget> {}

/// A live widget-style class: constructed from bin/app.dart, so it is USED and
/// must never be flagged — even though, like the dead ones, it is "referenced"
/// by its own constructor declaration.
class LiveWidget {
  const LiveWidget();
}
