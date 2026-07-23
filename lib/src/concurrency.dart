/*
 * AI-Provenance:
 *   model: claude-opus-4-8
 *   harness: Claude Code
 *   plugins:
 *     - lean-ai-provenance
 *   skills:
 *     - mark-ai-provenance
 */

import 'dart:async';

/// Runs [fn] over [items] with at most [concurrency] futures in flight,
/// preserving input order in the returned list.
Future<List<R>> mapPooled<T, R>(
  List<T> items,
  int concurrency,
  Future<R> Function(T) fn,
) async {
  final results = List<R?>.filled(items.length, null);
  var next = 0;

  Future<void> worker() async {
    while (true) {
      final index = next++;
      if (index >= items.length) {
        return;
      }
      results[index] = await fn(items[index]);
    }
  }

  final workerCount = concurrency < items.length ? concurrency : items.length;
  await List.generate(workerCount, (_) => worker()).wait;
  return results.cast<R>();
}
