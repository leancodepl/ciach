/*
 * AI-Provenance:
 *   model: claude-opus-4-8
 *   harness: Claude Code
 *   plugins:
 *     - lean-ai-provenance
 *   skills:
 *     - mark-ai-provenance
 */

extension StringExtensions on String {
  int? indexOfOrNull(Pattern pattern, [int start = 0]) =>
      switch (indexOf(pattern, start)) {
        -1 => null,
        final index => index,
      };
}

extension FutureExtensions on Future<void> {
  /// Completes when this future does, discarding any error it completes with.
  Future<void> ignoringErrors() async {
    try {
      await this;
    } on Object {
      // Deliberately ignored.
    }
  }
}
