import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:universal_web/js_interop.dart';
import 'package:universal_web/web.dart' as web;

/// Starts the dead-code animation on `#[targetId]` the first time it scrolls
/// into view.
///
/// Without JavaScript the target shows its end state (struck, faded lines).
/// With it, hydration first arms the target so nothing is struck yet, and
/// the animation plays once the block is on screen.
@client
class DemoTrigger extends StatefulComponent {
  const DemoTrigger({required this.targetId, super.key});

  final String targetId;

  @override
  State<DemoTrigger> createState() => _DemoTriggerState();
}

class _DemoTriggerState extends State<DemoTrigger> {
  web.IntersectionObserver? _observer;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) {
      return;
    }
    final target = web.document.getElementById(component.targetId);
    if (target == null) {
      return;
    }
    target.classList.add('armed');
    _observer = web.IntersectionObserver(
      ((
            JSArray<web.IntersectionObserverEntry> entries,
            web.IntersectionObserver _,
          ) {
            for (final entry in entries.toDart) {
              if (entry.isIntersecting) {
                target.classList.add('play');
                _observer?.disconnect();
                return;
              }
            }
          })
          .toJS,
      web.IntersectionObserverInit(threshold: 0.35.toJS),
    )..observe(target);
  }

  @override
  void dispose() {
    _observer?.disconnect();
    super.dispose();
  }

  @override
  Component build(BuildContext context) => const span(classes: 'sr-only', []);
}
