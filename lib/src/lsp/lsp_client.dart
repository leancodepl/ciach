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
import 'dart:convert';
import 'dart:io';

import 'package:pro_lsp/pro_lsp.dart' as lsp;
import 'package:stream_channel/stream_channel.dart';

/// Wire method name for the Dart analysis server's non-standard analysis-status
/// notification. It is not part of the LSP spec, so it is handled as a custom
/// notification.
const _analyzerStatusMethod = r'$/analyzerStatus';

/// A session with the Dart analysis server, spoken over LSP via `pro_lsp`.
///
/// `pro_lsp` handles JSON-RPC framing, request/response correlation, the typed
/// wire models, and the LSP lifecycle. This class adds the pieces `pro_lsp`
/// does not: spawning the server process, waiting for the Dart-specific
/// `$/analyzerStatus` idle signal, and shutting the process down cleanly.
class LspClient {
  LspClient._(this._process, this._client);

  final Process _process;
  final lsp.LspClient _client;

  /// Completers waiting for the server to become idle.
  final _idleWaiters = <Completer<void>>[];

  final _stderrBuffer = StringBuffer();
  bool _shuttingDown = false;

  /// Everything the server wrote to stderr (useful when things go wrong).
  String get stderr => _stderrBuffer.toString();

  /// Spawns `<dart> language-server --protocol=lsp` and wires up the client.
  ///
  /// [dartExecutable] defaults to the Dart VM currently running this tool, so
  /// the analysis server always matches the SDK the user invoked us with.
  static Future<LspClient> start({String? dartExecutable}) async {
    final executable = dartExecutable ?? Platform.resolvedExecutable;
    final process = await Process.start(executable, [
      'language-server',
      '--protocol=lsp',
      '--client-id=ciach',
      '--client-version=1.0.0',
    ]);

    final channel = StreamChannel<List<int>>(process.stdout, process.stdin);
    final client = lsp.LspClient.fromChannel(channel);
    final wrapper = LspClient._(process, client);

    process.stderr
        .transform(utf8.decoder)
        .listen(wrapper._stderrBuffer.write, onError: (_) {});
    unawaited(
      process.exitCode.then((code) {
        if (!wrapper._shuttingDown) {
          wrapper._failIdleWaiters(
            StateError(
              'Language server exited unexpectedly (code $code).\n'
              '${wrapper.stderr}',
            ),
          );
        }
      }),
    );

    // Register before the handshake so no status notification is missed. The
    // Dart server only emits `$/analyzerStatus` after `initialized`, by which
    // point the connection state permits custom notifications.
    client.connection.registerCustomNotificationHandler(
      const _CustomMethod(_analyzerStatusMethod),
      (params, context) async => wrapper._onAnalyzerStatus(params),
    );

    return wrapper;
  }

  /// Performs the `initialize` / `initialized` handshake for [rootUri].
  Future<void> initialize(Uri rootUri) async {
    final uri = rootUri.toString();
    await _client.start(
      clientInfo: const .new(name: 'ciach', version: '1.0.0'),
      rootUri: uri,
      workspaceFolders: [.new(uri: uri, name: 'root')],
      // Advertise hierarchical document symbols so the server returns
      // `DocumentSymbol[]` (with children) rather than flat `SymbolInformation`.
      // `window.workDoneProgress` is deliberately left unset so the server
      // reports analysis progress via `$/analyzerStatus`.
      capabilities: const .new(
        textDocument: .new(
          documentSymbol: .new(hierarchicalDocumentSymbolSupport: true),
        ),
      ),
    );
  }

  void _onAnalyzerStatus(Object? params) {
    final analyzing = params is Map && params['isAnalyzing'] == true;
    if (!analyzing) {
      final waiters = List.of(_idleWaiters);
      _idleWaiters.clear();
      for (final waiter in waiters) {
        if (!waiter.isCompleted) {
          waiter.complete();
        }
      }
    }
  }

  void _failIdleWaiters(Object error) {
    final waiters = List.of(_idleWaiters);
    _idleWaiters.clear();
    for (final waiter in waiters) {
      if (!waiter.isCompleted) {
        waiter.completeError(error);
      }
    }
  }

  /// Completes once the server has finished a background analysis pass.
  ///
  /// Resolves on the next `$/analyzerStatus { isAnalyzing: false }`. A generous
  /// [timeout] guards against ever hanging if the server never reports idle.
  Future<void> waitForAnalysisComplete({
    Duration timeout = const .new(minutes: 10),
  }) {
    final completer = Completer<void>();
    _idleWaiters.add(completer);
    final timer = Timer(timeout, () {
      if (!completer.isCompleted) {
        _idleWaiters.remove(completer);
        completer.complete();
      }
    });
    return completer.future.whenComplete(timer.cancel);
  }

  /// Notifies the server that [uri] is open with the given [text].
  void didOpen(Uri uri, String text) {
    _client.server.textDocument.didOpen(
      .new(
        textDocument: .new(
          uri: uri.toString(),
          languageId: .dart,
          version: 1,
          text: text,
        ),
      ),
    );
  }

  /// Returns the hierarchical document symbols for [uri].
  ///
  /// Hierarchical support is advertised in [initialize], so this is always the
  /// `DocumentSymbol[]` variant (never flat `SymbolInformation`).
  Future<List<lsp.DocumentSymbol>> documentSymbol(Uri uri) async {
    final result = await _client.server.textDocument.documentSymbol(
      .new(textDocument: .new(uri: uri.toString())),
    );
    if (result.isNull) {
      return const [];
    }
    return result.asDocumentSymbolList ?? const [];
  }

  /// Returns all references to the symbol at [position] within [uri].
  ///
  /// When [includeDeclaration] is false (the default), the declaration site
  /// itself is excluded, so an empty result means "never referenced".
  Future<List<lsp.Location>> references(
    Uri uri,
    lsp.Position position, {
    bool includeDeclaration = false,
  }) async {
    final result = await _client.server.textDocument.references(
      .new(
        textDocument: .new(uri: uri.toString()),
        position: position,
        context: .new(includeDeclaration: includeDeclaration),
      ),
    );
    return result ?? const [];
  }

  /// Gracefully shuts the server down and terminates the process.
  Future<void> dispose() async {
    _shuttingDown = true;
    try {
      await _client.server.general.shutdown(timeout: const .new(seconds: 5));
      _client.server.general.exit();
    } on Object {
      // Best effort — fall through to closing and killing the process.
    }
    await _client.close().catchError((_) {});
    final exited = await _process.exitCode
        .timeout(const .new(seconds: 5))
        .then((_) => true)
        .catchError((_) => false);
    if (!exited) {
      _process.kill(.sigkill);
    }
  }
}

/// Minimal [lsp.LSPMethod] implementation for a custom (non-spec) method,
/// identified purely by its wire name.
class _CustomMethod implements lsp.LSPMethod {
  const _CustomMethod(this.value);

  @override
  final String value;
}
