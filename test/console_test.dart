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

  test('the report goes to stdout, everything else to stderr', () {
    console()
      ..report('findings\n')
      ..error('broken')
      ..warning('odd');
    expect(out.toString(), 'findings\n');
    expect(err.toString(), 'error: broken\nwarning: odd\n');
  });

  test('labels are styled on a stream that takes it', () {
    console(style: const Style(enabled: true)).error('broken');
    expect(err.toString(), '\x1b[1m\x1b[31merror:\x1b[39m\x1b[22m broken\n');
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

    test('leaves detail to --verbose, and warnings to the report', () {
      console(progress: true)
        ..log(record('detail', Level.FINE))
        ..log(record('problem', Level.WARNING));
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
      ..log(record('problem', Level.WARNING));
    expect(
      err.toString(),
      matches(RegExp(r'^\[ +\d+\.\ds\] Opening\n\[ +\d+\.\ds\] problem\n$')),
    );
  });

  test('says nothing unless asked to', () {
    console().log(record('Opening'));
    expect(err.toString(), isEmpty);
  });

  test('listens to the level it shows, under the logger it is given', () async {
    final level = Logger.root.level;
    addTearDown(() => Logger.root.level = level);
    final subscription = console(verbose: true).listen(Logger('ciach'));
    addTearDown(subscription.cancel);

    Logger('ciach.finder').fine('mine');
    Logger('other').info('not mine');
    Logger('ciach.finder').finer('too fine');
    await pumpEventQueue();

    expect(
      err.toString(),
      allOf(contains('mine'), isNot(contains('not mine'))),
    );
    expect(err.toString(), isNot(contains('too fine')));
  });
}
