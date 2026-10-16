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

import 'package:ciach/src/lsp/dart_executable.dart';
import 'package:ciach/src/lsp/exceptions.dart';
import 'package:ciach/src/lsp/outline.dart';
import 'package:ciach/src/lsp/semantic_tokens.dart';
import 'package:ciach/src/util/extensions.dart';
import 'package:ciach/src/util/log.dart';
import 'package:ciach/src/version.dart';
import 'package:pro_lsp/pro_lsp.dart' as lsp;
import 'package:stream_channel/stream_channel.dart';

/// Wire method name for the Dart analysis server's non-standard analysis-status
/// notification. It is not part of the LSP spec, so it is handled as a custom
/// notification.
const _analyzerStatusMethod = r'$/analyzerStatus';

/// Sent for every open file once `initializationOptions.outline` is set.
const _publishOutlineMethod = 'dart/textDocument/publishOutline';

/// The Dart-specific "go to super" request.
const _superMethod = 'dart/textDocument/super';

final _log = Logger('ciach.lsp');

/// A session with the Dart analysis server, spoken over LSP via `pro_lsp`.
///
/// `pro_lsp` handles JSON-RPC framing, request/response correlation, the typed
/// wire models, and the LSP lifecycle. This class adds the pieces `pro_lsp`
/// does not: spawning the server process, waiting for the Dart-specific
/// `$/analyzerStatus` idle signal, and shutting the process down cleanly.
class LspClient {
  LspClient._(this.dartExecutable, this._process, this._client);

  /// The `dart` the server was launched with.
  final String dartExecutable;

  final Process _process;
  final lsp.LspClient _client;

  final _exited = Completer<void>();

  /// Set when the server dies outside [dispose].
  AnalysisServerExitedException? _exitError;

  /// Completers waiting for the server to become idle.
  final _idleWaiters = <Completer<void>>[];

  /// True from when [initialize] adds the workspace folder until the server
  /// starts analyzing it. An idle report in between doesn't end the wait.
  bool _awaitingAnalysis = false;

  /// Whether the last `$/analyzerStatus` said that the server is analyzing.
  bool _analyzing = false;

  /// The empty directory the server starts in when [initialize] gets
  /// analysis options. [dispose] deletes it.
  Directory? _emptyRoot;

  final _outlines = <String, Outline>{};

  final _outlineWaiters = <String, Completer<Outline>>{};

  final _diagnostics = <String, List<lsp.Diagnostic>>{};

  /// The version of each open document, raised by every [didChange].
  final _versions = <String, int>{};

  /// Recent `window/logMessage` errors, oldest first.
  final _loggedErrors = <String>[];

  final _errorLogged = StreamController<void>.broadcast(sync: true);

  static const _maxLoggedErrors = 50;

  final _stderrBuffer = StringBuffer();
  bool _shuttingDown = false;

  SemanticTokensLegend _semanticTokensLegend = .empty;

  /// Everything the server wrote to stderr (useful when things go wrong).
  String get stderr => _stderrBuffer.toString();

  /// The legend for `semanticTokens` responses. Empty until [initialize].
  SemanticTokensLegend get semanticTokensLegend => _semanticTokensLegend;

  /// Spawns `<dart> language-server --protocol=lsp` and wires up the client.
  ///
  /// [dartExecutable] defaults to [findDartExecutable], which throws a
  /// [DartSdkNotFoundException] when there is no SDK to be found.
  static Future<LspClient> start({String? dartExecutable}) async {
    final executable = findDartExecutable(explicit: dartExecutable);
    final process = await Process.start(executable, [
      'language-server',
      '--protocol=lsp',
      '--client-id=ciach',
      '--client-version=$ciachVersion',
    ], runInShell: executableNeedsShell(executable));
    _log.fine('Started `$executable language-server` (pid ${process.pid}).');

    final channel = StreamChannel<List<int>>(process.stdout, process.stdin);
    final client = lsp.LspClient.fromChannel(channel);
    final wrapper = LspClient._(executable, process, client);

    final stderrDrained = process.stderr
        .transform(utf8.decoder)
        .listen(wrapper._stderrBuffer.write, onError: (_) {})
        .asFuture<void>()
        .ignoringErrors();
    // A dead server's stdin fails with a broken pipe; the exit report covers it.
    process.stdin.done.ignore();
    unawaited(() async {
      final code = await process.exitCode;
      // Can land before the last of stderr does.
      await stderrDrained;
      // Only an exit ciach didn't ask for is an error.
      if (wrapper._shuttingDown) {
        _log.fine('The analysis server exited with code $code.');
      } else {
        final error = AnalysisServerExitedException(
          executable: executable,
          exitCode: code,
          stderr: wrapper.stderr.trim(),
        );
        wrapper
          .._exitError = error
          .._failIdleWaiters(error);
      }
      wrapper._exited.complete();
    }());

    // Register before the handshake so no status notification is missed. The
    // Dart server only emits `$/analyzerStatus` after `initialized`, by which
    // point the connection state permits custom notifications.
    client.connection.registerCustomNotificationHandler(
      const _CustomMethod(_analyzerStatusMethod),
      (params, context) async => wrapper._onAnalyzerStatus(params),
    );
    client.connection.registerCustomNotificationHandler(
      const _CustomMethod(_publishOutlineMethod),
      (params, context) async => wrapper._onPublishOutline(params),
    );
    client.textDocument.onPublishDiagnostics((params, context) async {
      wrapper._diagnostics[params.uri] = params.diagnostics;
    });
    client.window.onLogMessage((params, context) async {
      if (params.type == .error) {
        wrapper._onLoggedError(params.message);
      }
    });

    return wrapper;
  }

  /// Performs the `initialize` / `initialized` handshake for [rootUri].
  ///
  /// [analysisOptions] maps a path to the content the server uses instead of
  /// the file on disk, for this session only. The server reads analysis
  /// options when it sets up a folder. So with [analysisOptions], the server
  /// starts in an empty directory, gets the new content, and only then gets
  /// [rootUri].
  Future<void> initialize(
    Uri rootUri, {
    Map<String, String> analysisOptions = const {},
  }) async {
    final uri = rootUri.toString();
    final emptyRoot = analysisOptions.isEmpty
        ? null
        : _emptyRoot = Directory.systemTemp.createTempSync('ciach_root_');
    final startUri = emptyRoot?.uri.toString() ?? uri;
    final result = await _guard(
      lsp.RequestMethod.initialize.value,
      () => _client.start(
        clientInfo: const .new(name: 'ciach', version: ciachVersion),
        rootUri: startUri,
        workspaceFolders: [.new(uri: startUri, name: 'root')],
        initializationOptions: const {'outline': true},
        // Hierarchical document symbols yield nested `DocumentSymbol[]` rather
        // than flat `SymbolInformation`; semantic tokens make the server send its
        // legend. `workDoneProgress` is left unset so progress arrives via
        // `$/analyzerStatus`.
        capabilities: const .new(
          textDocument: .new(
            documentSymbol: .new(hierarchicalDocumentSymbolSupport: true),
            semanticTokens: .new(
              requests: .new(full: .bool(true)),
              tokenTypes: [],
              tokenModifiers: [],
              formats: [.relative],
            ),
          ),
        ),
      ),
    );
    _semanticTokensLegend = .fromCapabilities(result.capabilities.toJson());
    if (emptyRoot == null) {
      return;
    }
    for (final MapEntry(key: path, value: text) in analysisOptions.entries) {
      _client.server.textDocument.didOpen(
        .new(
          textDocument: .new(
            uri: File(path).uri.toString(),
            languageId: .yAML,
            version: 1,
            text: text,
          ),
        ),
      );
    }
    _awaitingAnalysis = true;
    _client.server.workspace.didChangeWorkspaceFolders(
      .new(
        event: .new(
          added: [.new(uri: uri, name: 'root')],
          removed: [.new(uri: startUri, name: 'root')],
        ),
      ),
    );
  }

  /// Runs [request]. Throws [AnalysisServerExitedException] if the server
  /// died, else [LspRequestException], filled in from the exception the
  /// server logs separately from its bare error response.
  Future<T> _guard<T>(String method, Future<T> Function() request) async {
    try {
      return await request();
    } on Object catch (e, st) {
      if (_shuttingDown) {
        rethrow;
      }
      if (e is! lsp.LspException) {
        await _exited.future.timeout(const .new(seconds: 1)).ignoringErrors();
      }
      if (_exitError case final error?) {
        throw error;
      }
      final failure = switch (e) {
        lsp.LspException(code: lsp.LspErrorCodes.unknownErrorCode) =>
          (await _takeLoggedError(e.message))?.let(
                (logged) => LspRequestException.fromLog(method, logged),
              ) ??
              LspRequestException(method, e.message),
        lsp.LspException() => LspRequestException(
          method,
          '${e.message} (error ${e.code})',
        ),
        _ => LspRequestException(method, '$e'),
      };
      Error.throwWithStackTrace(failure, st);
    }
  }

  void _onLoggedError(String message) {
    if (_errorLogged.isClosed) {
      return;
    }
    _loggedErrors.add(message);
    if (_loggedErrors.length > _maxLoggedErrors) {
      _loggedErrors.removeAt(0);
    }
    _errorLogged.add(null);
  }

  /// The server's log for the failed request [message]; it can arrive after
  /// the response, so this waits up to [timeout].
  Future<String?> _takeLoggedError(
    String message, {
    Duration timeout = const .new(seconds: 1),
  }) async {
    final prefix = '$message: ';
    String? take() {
      final index = _loggedErrors.indexWhere((e) => e.startsWith(prefix));
      return index < 0
          ? null
          : _loggedErrors.removeAt(index).substring(prefix.length);
    }

    final deadline = DateTime.now().add(timeout);
    while (true) {
      if (take() case final logged?) {
        return logged;
      }
      final remaining = deadline.difference(.now());
      if (remaining <= .zero) {
        return null;
      }
      try {
        await _errorLogged.stream.first.timeout(remaining);
      } on Object {
        // Timed out, or disposed.
        return take();
      }
    }
  }

  void _onAnalyzerStatus(Object? params) {
    final analyzing = _analyzing =
        params is Map && params['isAnalyzing'] == true;
    if (analyzing) {
      _awaitingAnalysis = false;
    } else if (!_awaitingAnalysis) {
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
    final waiters = [..._idleWaiters, ..._outlineWaiters.values];
    _idleWaiters.clear();
    _outlineWaiters.clear();
    for (final waiter in waiters) {
      if (!waiter.isCompleted) {
        waiter.completeError(error);
      }
    }
  }

  void _onPublishOutline(Object? params) {
    if (params case {
      'uri': final String uri,
      'outline': final Map<String, Object?> json,
    }) {
      final outline = Outline.fromJson(json);
      _outlines[uri] = outline;
      _outlineWaiters.remove(uri)?.complete(outline);
    }
  }

  /// The outline of [uri] if the server has already sent it.
  Outline? cachedOutline(Uri uri) => _outlines[uri.toString()];

  /// The outline of [uri]. Throws [LspRequestException] after [timeout].
  Future<Outline> outline(
    Uri uri, {
    Duration timeout = const .new(minutes: 2),
  }) async {
    final key = uri.toString();
    if (_outlines[key] case final outline?) {
      return outline;
    }
    if (_exitError case final error?) {
      throw error;
    }
    final completer = _outlineWaiters.putIfAbsent(key, Completer<Outline>.new);
    try {
      return await completer.future.timeout(timeout);
    } on TimeoutException {
      _outlineWaiters.remove(key);
      throw LspRequestException(
        _publishOutlineMethod,
        'no outline arrived within ${timeout.inSeconds}s',
      );
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

  /// The diagnostics that the server last published, keyed by document URI.
  Map<String, List<lsp.Diagnostic>> get diagnostics =>
      .unmodifiable(_diagnostics);

  /// Completes once the server has analyzed the content that every
  /// [didChange] so far sent; [changed] is one of the changed documents.
  ///
  /// The server answers a request only after it has taken in the changes
  /// sent before it, and it reports the analysis that they start before that
  /// answer. So after the answer, an idle server has nothing left to analyze,
  /// and an idle report that was sent before the changes is already read.
  Future<void> waitForChangesAnalyzed(Uri changed) async {
    await _guard(
      lsp.RequestMethod.foldingRange.value,
      () => _client.server.textDocument.foldingRange(
        .new(textDocument: .new(uri: changed.toString())),
      ),
    );
    if (_analyzing) {
      await waitForAnalysisComplete();
    }
  }

  /// Whether [didOpen] opened [uri].
  bool isOpen(Uri uri) => _versions.containsKey(uri.toString());

  /// Notifies the server that [uri] is open with the given [text].
  void didOpen(Uri uri, String text) {
    _versions[uri.toString()] = 1;
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

  /// Replaces the content of the open document [uri] with [text], for this
  /// session only; the file on disk doesn't change.
  void didChange(Uri uri, String text) {
    final key = uri.toString();
    _client.server.textDocument.didChange(
      .new(
        textDocument: .new(
          uri: key,
          version: _versions[key] = (_versions[key] ?? 1) + 1,
        ),
        contentChanges: [
          .textDocumentContentChangeWholeDocument(.new(text: text)),
        ],
      ),
    );
  }

  /// Returns the hierarchical document symbols for [uri].
  ///
  /// Hierarchical support is advertised in [initialize], so this is always the
  /// `DocumentSymbol[]` variant (never flat `SymbolInformation`).
  Future<List<lsp.DocumentSymbol>> documentSymbol(Uri uri) async {
    final result = await _guard(
      lsp.RequestMethod.documentSymbol.value,
      () => _client.server.textDocument.documentSymbol(
        .new(textDocument: .new(uri: uri.toString())),
      ),
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
    final result = await _guard(
      lsp.RequestMethod.references.value,
      () => _client.server.textDocument.references(
        .new(
          textDocument: .new(uri: uri.toString()),
          position: position,
          context: .new(includeDeclaration: includeDeclaration),
        ),
      ),
    );
    return result ?? const [];
  }

  /// Resolves the declaration(s) the symbol at [position] in [uri] points to,
  /// via `textDocument/definition` (forward resolution).
  Future<List<lsp.Location>> definition(Uri uri, lsp.Position position) async {
    final result = await _guard(
      lsp.RequestMethod.definition.value,
      () => _client.server.textDocument.definition(
        .new(
          textDocument: .new(uri: uri.toString()),
          position: position,
        ),
      ),
    );
    final definition = result.asDefinition;
    return definition?.asLocationList ?? [?definition?.asLocation];
  }

  /// The hover text at [position] in [uri]: the element's signature as the
  /// analyzer resolved it, then its docs. `null` when there is none.
  Future<String?> hover(Uri uri, lsp.Position position) async {
    final result = await _guard(
      lsp.RequestMethod.hover.value,
      () => _client.server.textDocument.hover(
        .new(
          textDocument: .new(uri: uri.toString()),
          position: position,
        ),
      ),
    );
    return switch (result?.contents.toJson()) {
      {'value': final String value} => value,
      Map() || null => null,
      final contents => '$contents',
    };
  }

  /// The semantic tokens of [uri], with each token's text taken from [lines].
  Future<List<SemanticToken>> semanticTokens(
    Uri uri,
    List<String> lines,
  ) async {
    final result = await _guard(
      lsp.RequestMethod.full.value,
      () => _client.server.textDocument.semanticTokensFull(
        .new(textDocument: .new(uri: uri.toString())),
      ),
    );
    return decodeSemanticTokens(
      result?.data ?? const [],
      _semanticTokensLegend,
      lines,
    );
  }

  /// The superclass, super constructor or overridden member of the element at
  /// [position] in [uri]. `null` when there is none.
  Future<lsp.Location?> superOf(Uri uri, lsp.Position position) async {
    final result = await _guard(
      _superMethod,
      () => _client.connection.sendCustomRequest(
        _superMethod,
        lsp.TextDocumentPositionParams(
          textDocument: .new(uri: uri.toString()),
          position: position,
        ).toJson(),
      ),
    );
    return switch (result) {
      final Map<String, Object?> json => lsp.Location.fromJson(json),
      _ => null,
    };
  }

  /// The members that override the member at [position] in [uri], via
  /// `textDocument/implementation`. Empty when nothing overrides it.
  Future<List<lsp.Location>> implementations(
    Uri uri,
    lsp.Position position,
  ) async {
    final result = await _guard(
      lsp.RequestMethod.implementation.value,
      () => _client.server.textDocument.implementation(
        .new(
          textDocument: .new(uri: uri.toString()),
          position: position,
        ),
      ),
    );
    final definition = result.asDefinition;
    return definition?.asLocationList ?? [?definition?.asLocation];
  }

  /// The syntax nodes enclosing each of [positions] in [uri], innermost first.
  /// `null` where the server has no answer.
  Future<List<lsp.SelectionRange?>> selectionRanges(
    Uri uri,
    List<lsp.Position> positions,
  ) async {
    if (positions.isEmpty) {
      return const [];
    }
    final result = await _guard(
      lsp.RequestMethod.selectionRange.value,
      () => _client.server.textDocument.selectionRange(
        .new(
          textDocument: .new(uri: uri.toString()),
          positions: positions,
        ),
      ),
    );
    if (result == null || result.length != positions.length) {
      return .filled(positions.length, null);
    }
    return result;
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
    await _client.close().ignoringErrors();
    try {
      await _process.exitCode.timeout(const .new(seconds: 5));
    } on TimeoutException {
      _process.kill(.sigkill);
    }
    await _errorLogged.close();
    try {
      _emptyRoot?.deleteSync(recursive: true);
    } on FileSystemException {
      // The OS cleans up the temp directory later.
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
