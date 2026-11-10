/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

import 'package:ciach/src/util/extensions.dart';
import 'package:test/test.dart';

void main() {
  test('`withoutTypeArguments` drops the type arguments of a type name', () {
    expect('Map<String, List<int>>'.withoutTypeArguments, 'Map');
    expect('Story <T>'.withoutTypeArguments, 'Story');
    expect('Story'.withoutTypeArguments, 'Story');
  });
}
