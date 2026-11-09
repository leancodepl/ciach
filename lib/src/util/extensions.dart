/*
 * AI-Provenance:
 *   model: claude-opus-4-8
 *   harness: Claude Code
 *   plugins:
 *     - lean-ai-provenance
 *   skills:
 *     - mark-ai-provenance
 */

extension Let<T extends Object> on T {
  /// [transform] applied to this, for chaining after `?.`.
  R let<R>(R Function(T it) transform) => transform(this);
}
