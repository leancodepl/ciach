import 'package:ciach/src/style.dart';
import 'package:test/test.dart';

void main() {
  const on = Style(enabled: true);

  test('plain leaves text alone', () {
    expect(Style.plain.errorLabel('error:'), 'error:');
    expect(Style.plain.note('x'), 'x');
  });

  test('roles reset only what they set, so they nest', () {
    expect(on.path('x'), '\x1b[1mx\x1b[22m');
    expect(on.errorLabel('x'), '\x1b[1m\x1b[31mx\x1b[39m\x1b[22m');
    expect(
      on.note('a ${on.kind('b')} c'),
      '\x1b[2ma \x1b[36mb\x1b[39m c\x1b[22m',
    );
  });

  test('empty text gets no escapes', () {
    expect(on.heading(''), '');
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
