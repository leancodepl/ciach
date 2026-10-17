/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

/// Returns [name] without its leading underscores, as `items` for `_items`,
/// or `null` when [name] has only underscores, as `__` has.
String? withoutLeadingUnderscores(String name) =>
    _afterUnderscores.firstMatch(name)?.namedGroup('name');

final _afterUnderscores = RegExp('^_*(?<name>[^_].*)');
