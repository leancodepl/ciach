import 'dart:async';

/// The recent `window/logMessage` errors, oldest first. The server logs the
/// exception behind a failed request separately from its bare error
/// response, so a failure is explained by taking the log for its message.
final class LoggedErrors {
  final _errors = <String>[];

  final _added = StreamController<void>.broadcast(sync: true);

  static const _max = 50;

  /// Records [message], dropping the oldest once [_max] are kept.
  void add(String message) {
    if (_added.isClosed) {
      return;
    }
    _errors.add(message);
    if (_errors.length > _max) {
      _errors.removeAt(0);
    }
    _added.add(null);
  }

  /// The server's log for the failed request [message]; it can arrive after
  /// the response, so this waits up to [timeout].
  Future<String?> take(
    String message, {
    Duration timeout = const .new(seconds: 1),
  }) async {
    final prefix = '$message: ';
    String? take() {
      final index = _errors.indexWhere((e) => e.startsWith(prefix));
      return index < 0
          ? null
          : _errors.removeAt(index).substring(prefix.length);
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
        await _added.stream.first.timeout(remaining);
      } on Object {
        // Timed out, or closed.
        return take();
      }
    }
  }

  /// Stops recording; a pending [take] returns what has arrived.
  Future<void> close() => _added.close();
}
