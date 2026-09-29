import 'package:ciach/src/style.dart';
import 'package:test/test.dart';

void main() {
  const on = Style(enabled: true);

  test('plain leaves text alone', () {
    expect(Style.plain.error('error:'), 'error:');
    expect(Style.plain.hint('x'), 'x');
  });

  test('styles reset only what they set, so they nest', () {
    expect(on.bold('x'), '\x1b[1mx\x1b[22m');
    expect(on.error('x'), '\x1b[1m\x1b[31mx\x1b[39m\x1b[22m');
    expect(
      on.hint('a ${on.cyan('b')} c'),
      '\x1b[2ma \x1b[36mb\x1b[39m c\x1b[22m',
    );
  });

  test('empty text gets no escapes', () {
    expect(on.bold(''), '');
  });

  group('shouldStyle', () {
    bool decide({bool? color, bool ansi = true, String? noColor}) =>
        Style.shouldStyle(
          color: color,
          supportsAnsiEscapes: ansi,
          environment: {'NO_COLOR': ?noColor},
        );

    test('follows the stream when nobody asked', () {
      expect(decide(), isTrue);
      expect(decide(ansi: false), isFalse);
    });

    test('NO_COLOR turns auto off, but not an explicit --color', () {
      expect(decide(noColor: '1'), isFalse);
      expect(decide(noColor: ''), isTrue);
      expect(decide(color: true, noColor: '1'), isTrue);
    });

    test('--color and --no-color win over the stream', () {
      expect(decide(color: true, ansi: false), isTrue);
      expect(decide(color: false), isFalse);
    });
  });
}
