import 'package:ciach/ciach.dart' show AnalysisProblem;
import 'package:ciach/src/cli/console.dart';
import 'package:ciach/src/style.dart';
import 'package:logging/logging.dart';
import 'package:test/test.dart';

void main() {
  late StringBuffer out;
  late StringBuffer err;

  setUp(() {
    out = StringBuffer();
    err = StringBuffer();
  });

  Console console({
    bool progress = false,
    bool verbose = false,
    Style style = Style.plain,
    int? width,
  }) => Console(
    out: out,
    err: err,
    errStyle: style,
    progress: progress,
    verbose: verbose,
    width: width,
  );

  LogRecord record(String message, [Level level = Level.INFO]) =>
      LogRecord(level, message, 'ciach.finder');

  test('the report goes to stdout, the log to stderr', () {
    console()
      ..report('findings\n')
      ..log(record('broken', Level.SEVERE))
      ..log(record('odd', Level.WARNING));
    expect(out.toString(), 'findings\n');
    expect(err.toString(), 'error: broken\nwarning: odd\n');
  });

  test('labels are styled on a stream that takes it', () {
    console(
      style: const Style(enabled: true),
    ).log(record('broken', Level.SEVERE));
    expect(err.toString(), '\x1b[1m\x1b[31merror:\x1b[39m\x1b[22m broken\n');
  });

  test('a severe record carrying an error says all there is about it', () {
    console().log(
      LogRecord(
        Level.SEVERE,
        'The run stopped.',
        'ciach.cli',
        RangeError('Index out of range'),
        StackTrace.empty,
      ),
    );
    expect(err.toString(), startsWith('error: Internal error: RangeError'));
    expect(err.toString(), contains('This is a bug in ciach'));
  });

  test('an analysis problem is left to the report, unless verbose', () {
    const problem = AnalysisProblem(
      summary: 'Could not read.',
      cause: 'Gone',
      filePath: 'lib/a.dart',
    );
    LogRecord problemRecord() => LogRecord(
      Level.WARNING,
      '$problem',
      'ciach.problems',
      null,
      null,
      null,
      problem,
    );

    console().log(problemRecord());
    expect(err.toString(), isEmpty);

    console(verbose: true).log(problemRecord());
    expect(err.toString(), contains('warning: lib/a.dart: Could not read.'));
  });

  group('progress', () {
    test('overwrites one line, and clears it before anything else', () {
      const first = 'Checking references for 12 declarations…';
      const second = '[1/3] lib/a.dart';
      console(progress: true)
        ..log(record(first))
        ..log(record('detail', Level.FINE))
        ..log(record(second))
        ..report('findings\n');
      expect(
        err.toString(),
        // The second pads over what is left of the first; clearing it then
        // only has its own length to blank.
        '\r$first'
        '\r$second${' ' * (first.length - second.length)}'
        '\r${' ' * second.length}\r',
      );
      expect(out.toString(), 'findings\n');
    });

    test('clears with an escape where styling is on', () {
      console(progress: true, style: const Style(enabled: true))
        ..log(record('Opening'))
        ..clearProgress();
      expect(err.toString(), endsWith('\r\x1b[2K'));
    });

    test('leaves detail to --verbose', () {
      console(progress: true).log(record('detail', Level.FINE));
      expect(err.toString(), isEmpty);
    });

    test('is cut to the terminal width', () {
      console(progress: true, width: 10).log(record('0123456789abc'));
      expect(err.toString(), '\r01234567…');
    });
  });

  test('verbose stamps every record, warnings included', () {
    console(verbose: true)
      ..log(record('Opening'))
      ..log(record('odd', Level.WARNING));
    expect(
      err.toString(),
      matches(
        RegExp(r'^\[ +\d+\.\ds\] Opening\n\[ +\d+\.\ds\] warning: odd\n$'),
      ),
    );
  });

  test('says nothing unless asked to', () {
    console().log(record('Opening'));
    expect(err.toString(), isEmpty);
  });

  test('asks for the records it shows', () {
    expect(console().level, Level.WARNING);
    expect(console(progress: true).level, Level.INFO);
    expect(console(verbose: true).level, Level.FINE);
  });
}
