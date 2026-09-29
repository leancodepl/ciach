import 'package:ciach/src/cli/log_format.dart';
import 'package:ciach/src/log.dart';
import 'package:ciach/src/style.dart';
import 'package:test/test.dart';

void main() {
  const plain = LogFormatter();
  const styled = LogFormatter(style: Style(enabled: true));
  const elapsed = Duration(milliseconds: 1234);

  LogRecord record(
    Level level,
    String message, {
    String logger = 'ciach.finder',
    Object? error,
  }) => LogRecord(level, message, logger, error, StackTrace.empty);

  String line(LogFormatter f, Level level, String message) =>
      f.line(record(level, message), elapsed);

  test('labels errors and warnings; leaves the rest as said', () {
    expect(line(plain, Level.SEVERE, 'broken'), 'error: broken\n');
    expect(line(plain, Level.WARNING, 'odd'), 'warning: odd\n');
    expect(line(plain, Level.INFO, 'Opening'), 'Opening\n');
    expect(line(plain, Level.CONFIG, 'color: auto'), 'color: auto\n');
    expect(line(plain, Level.FINEST, 'deep'), 'deep\n');
  });

  test('colors each level', () {
    expect(
      line(styled, Level.SEVERE, 'broken'),
      '\x1b[1m\x1b[31merror:\x1b[39m\x1b[22m broken\n',
    );
    expect(
      line(styled, Level.WARNING, 'odd'),
      '\x1b[1m\x1b[33mwarning:\x1b[39m\x1b[22m odd\n',
    );
    expect(line(styled, Level.INFO, 'Opening'), 'Opening\n');
    expect(line(styled, Level.CONFIG, 'x'), '\x1b[35mx\x1b[39m\n');
    expect(line(styled, Level.FINE, 'x'), '\x1b[2mx\x1b[22m\n');
    expect(line(styled, Level.FINER, 'x'), '\x1b[2mx\x1b[22m\n');
  });

  test('a severe record carrying an error says all there is about it', () {
    final text = plain.line(
      record(Level.SEVERE, 'ciach stopped.', error: RangeError('Index')),
      elapsed,
    );
    expect(text, startsWith('error: Internal error: RangeError'));
    expect(text, contains('This is a bug in ciach'));
    expect(text, endsWith('Run with -v for the stack trace.\n'));
  });

  test('verbose stamps the time and names the area talking', () {
    const verbose = LogFormatter(verbose: true);
    expect(
      verbose.line(record(Level.INFO, 'Opening'), elapsed),
      '[  1.2s] [finder]  Opening\n',
    );
    expect(
      verbose.line(record(Level.FINE, 'Started', logger: 'ciach.lsp'), elapsed),
      '[  1.2s] [lsp]     Started\n',
    );
    expect(
      verbose.line(record(Level.INFO, 'x', logger: 'other'), elapsed),
      '[  1.2s] [other]   x\n',
    );
  });

  test('the progress line is dim', () {
    expect(styled.progress('Opening'), '\x1b[2mOpening\x1b[22m');
  });
}
