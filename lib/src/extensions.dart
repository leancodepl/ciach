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
