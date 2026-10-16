/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

import 'package:ciach/src/lsp/exceptions.dart';
import 'package:ciach/src/lsp/lsp_client.dart';
import 'package:ciach/src/util/concurrency.dart';
import 'package:pro_lsp/pro_lsp.dart' show Location, Position;

/// Where the name at each of [lookups] resolves to, by lookup; [positionOf]
/// gives a lookup's document and position. A name that the server can't
/// resolve proves no use, so it resolves to nothing.
Future<Map<T, List<Location>>> definitionsOrEmpty<T>(
  LspClient client,
  Iterable<T> lookups,
  ({Uri uri, Position position}) Function(T lookup) positionOf,
  int concurrency,
) async {
  final ordered = lookups.toList();
  final definitions = await mapPooled(ordered, concurrency, (lookup) async {
    final (:uri, :position) = positionOf(lookup);
    try {
      return await client.definition(uri, position);
    } on LspRequestException {
      return const <Location>[];
    }
  });
  return .fromIterables(ordered, definitions);
}
