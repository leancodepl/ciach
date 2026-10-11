// The default variant: the analysis server resolves every use to it.

bool get conditionalIsWeb => false;

// Unused on every platform -> flagged here and in the web variant.
bool get conditionalDeadOnBoth => false;

class ConditionalPlatform {
  String label() => 'io'.shout();
}

extension on String {
  String shout() => toUpperCase();
}
