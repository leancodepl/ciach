import 'package:ciach/src/cli/log_format.dart';
import 'package:ciach/src/log.dart';
import 'package:test/test.dart';

void main() {
  const plain = LogFormatter();
  const styled = LogFormatter(style: .new(enabled: true));
  const elapsed = Duration(milliseconds: 1234);

  LogRecord record(
    Level level,
    String message, {
    String logger = 'ciach.finder',
    Object? error,
  }) => .new(level, message, logger, error, .empty);

  String line(LogFormatter f, Level level, String message) =>
      f.line(record(level, message), elapsed);

  test('labels errors and warnings; leaves the rest as said', () {
    expect(line(plain, .SEVERE, 'broken'), 'error: broken\n');
    expect(line(plain, .WARNING, 'odd'), 'warning: odd\n');
    expect(line(plain, .INFO, 'Opening'), 'Opening\n');
    expect(line(plain, .CONFIG, 'color: auto'), 'color: auto\n');
    expect(line(plain, .FINEST, 'deep'), 'deep\n');
  });

  test('colors each level', () {
    expect(
      line(styled, .SEVERE, 'broken'),
      '\x1b[1m\x1b[31merror:\x1b[39m\x1b[22m broken\n',
    );
    expect(
      line(styled, .WARNING, 'odd'),
      '\x1b[1m\x1b[33mwarning:\x1b[39m\x1b[22m odd\n',
    );
    expect(line(styled, .INFO, 'Opening'), 'Opening\n');
    expect(line(styled, .CONFIG, 'x'), '\x1b[35mx\x1b[39m\n');
    expect(line(styled, .FINE, 'x'), '\x1b[2mx\x1b[22m\n');
    expect(line(styled, .FINER, 'x'), '\x1b[2mx\x1b[22m\n');
  });

  test('a severe record carrying an error says all there is about it', () {
    final text = plain.line(
      record(.SEVERE, 'ciach stopped.', error: RangeError('Index')),
      elapsed,
    );
    expect(text, startsWith('error: Internal error: RangeError'));
    expect(text, contains('This is a bug in ciach'));
    expect(text, endsWith('Run with -v for the stack trace.\n'));
  });

  test('verbose stamps the time and names the area talking', () {
    const verbose = LogFormatter(verbose: true);
    expect(
      verbose.line(record(.INFO, 'Opening'), elapsed),
      '[  1.2s] [finder]  Opening\n',
    );
    expect(
      verbose.line(record(.FINE, 'Started', logger: 'ciach.lsp'), elapsed),
      '[  1.2s] [lsp]     Started\n',
    );
    expect(
      verbose.line(record(.INFO, 'x', logger: 'other'), elapsed),
      '[  1.2s] [other]   x\n',
    );
  });

  test('the progress line is dim', () {
    expect(styled.progress('Opening'), '\x1b[2mOpening\x1b[22m');
  });
}
