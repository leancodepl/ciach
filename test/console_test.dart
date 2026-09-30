import 'package:ciach/src/cli/console.dart';
import 'package:ciach/src/log.dart';
import 'package:test/test.dart';

void main() {
  late StringBuffer out;
  late StringBuffer err;
  late Level rootLevel;

  setUp(() {
    out = .new();
    err = .new();
    rootLevel = Logger.root.level;
  });

  tearDown(() => Logger.root.level = rootLevel);

  Console console({
    bool ansi = false,
    int? width,
    List<String> answers = const [],
    bool interactive = true,
  }) {
    final pending = [...answers];
    return .new(
      out: out,
      err: err,
      outSupportsAnsi: ansi,
      errSupportsAnsi: ansi,
      width: width,
      interactive: interactive,
      readLine: () => pending.isEmpty ? null : pending.removeAt(0),
    );
  }

  LogRecord record(String message, [Level level = .INFO]) =>
      .new(level, message, 'ciach.finder');

  test('the result goes to stdout, the log to stderr', () {
    console()
      ..output('findings')
      ..log(record('broken', .SEVERE))
      ..log(record('odd', .WARNING));
    expect(out.toString(), 'findings\n');
    expect(err.toString(), 'error: broken\nwarning: odd\n');
  });

  test('shows warnings and errors only, until configured otherwise', () {
    final c = console()
      ..log(record('Opening'))
      ..log(record('detail', .FINE));
    expect(err.toString(), isEmpty);
    expect(c.level, Level.WARNING);
    expect(Logger.root.level, Level.WARNING);
  });

  test('configure sets the level the root logs at', () {
    final c = console()..configure(progress: true);
    expect(c.level, Level.INFO);
    expect(Logger.root.level, Level.INFO);
    c.configure(verbose: true);
    expect(c.level, Level.ALL);
    expect(Logger.root.level, Level.ALL);
  });

  test('styles each stream as configured', () {
    final c = console(ansi: true);
    expect(c.outStyle.enabled, isTrue);
    c.configure(color: false);
    expect(c.outStyle.enabled, isFalse);
    expect(c.errStyle.enabled, isFalse);
  });

  test('attach routes every record the root lets through', () async {
    final c = console()..configure(verbose: true);
    final subscription = c.attach();
    addTearDown(subscription.cancel);
    Logger('ciach.lsp').finest('deep');
    await pumpEventQueue();
    expect(err.toString(), contains('deep'));
  });

  group('progress', () {
    test('overwrites one line, and clears it before anything else', () {
      const first = 'Checking references for 12 declarations…';
      const second = '[1/3] lib/a.dart';
      console()
        ..configure(progress: true)
        ..log(record(first))
        ..log(record('detail', .FINE))
        ..log(record(second))
        ..output('findings');
      expect(
        err.toString(),
        // Padding blanks the rest of the longer first line.
        '\r$first'
        '\r$second${' ' * (first.length - second.length)}'
        '\r${' ' * second.length}\r',
      );
      expect(out.toString(), 'findings\n');
    });

    test('clears with an escape where styling is on', () {
      console(ansi: true)
        ..configure(progress: true)
        ..log(record('Opening'))
        ..clearProgress();
      expect(err.toString(), endsWith('\r\x1b[2K'));
    });

    test('is cut to the terminal width', () {
      console(width: 10)
        ..configure(progress: true)
        ..log(record('0123456789abc'));
      expect(err.toString(), '\r01234567…');
    });

    test('gives way to verbose', () {
      console()
        ..configure(progress: true, verbose: true)
        ..log(record('Opening'));
      expect(
        err.toString(),
        matches(RegExp(r'^\[ +\d+\.\ds\] \[finder\]  Opening\n$')),
      );
    });
  });

  group('confirm', () {
    test('asks on stderr, after the preamble, and reads the answer', () {
      final c = console(answers: ['y']);
      expect(c.confirm('Remove 2?', preamble: 'findings'), isTrue);
      expect(err.toString(), 'findings\nRemove 2? [y/N] ');
      expect(out.toString(), isEmpty);
    });

    test('anything but yes is a no', () {
      final c = console(answers: ['', 'nope']);
      expect(c.confirm('Remove?'), isFalse);
      expect(c.confirm('Remove?'), isFalse);
      expect(c.confirm('Remove?'), isFalse);
    });
  });
}
