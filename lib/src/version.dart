/*
 * AI-Provenance:
 *   model: claude-opus-5
 *   harness: Claude Code
 *   plugins:
 *     - lean-ai-provenance
 *   skills:
 *     - mark-ai-provenance
 */

/// The published version of ciach, as `--version` and the `--help` header
/// report it.
///
/// A compiled or globally activated binary has no `pubspec.yaml` to read at
/// run time, so the version is a constant here and `test/version_test.dart`
/// fails if a release bumps `pubspec.yaml` without it.
const ciachVersion = '0.4.2';
