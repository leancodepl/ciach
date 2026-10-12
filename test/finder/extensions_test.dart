@Timeout(Duration(minutes: 5))
library;

import 'package:ciach/src/models.dart';
import 'package:pro_lsp/pro_lsp.dart' show SymbolKind;
import 'package:test/test.dart';

import '../support/finder.dart';

void main() {
  setUpFixture();

  const extensionFixture = [
    'lib/scenarios/extensions_emptied.dart',
    'lib/scenarios/extensions_emptied_uses.dart',
  ];

  group('dead extensions', () {
    Future<FinderResult> runExtensions() => runScenario(extensionFixture);

    Future<Set<String>> byKind(SymbolKind kind) async => qualifiedNames(
      (await runScenario(extensionFixture, kinds: {kind})).unused,
    );

    test("reports exactly the fixture's dead declarations", () async {
      final result = await runExtensions();
      expect(qualifiedNames(result.unused), {
        'DeadHelpers',
        'LiveHelpers.stale',
        'extension on String',
        'ShownHelpers.shownButUnused',
        'Hollow',
        'extension on List<T>',
        'extension on T',
        'DeadMeters',
        'DeadMeters.scaled',
        'SelfMeters',
        'SelfMeters.next',
        'useEmptiedExtensions',
      });
    });

    test('an extension whose every member is dead is reported as the '
        'extension, not its members', () async {
      final result = await runExtensions();
      final decl = findByQualified(result, 'DeadHelpers');
      expect(decl, isNotNull, reason: 'nothing calls either member');
      expect(decl!.kind, SymbolKind.namespace);
      expect(decl.kind.label, 'extension');
      expect(decl.removalBlocked, isFalse);
      expect(findByQualified(result, 'DeadHelpers.first'), isNull);
      expect(findByQualified(result, 'DeadHelpers.second'), isNull);
    });

    test('an extension with a live member is never reported, even though '
        'nothing names it', () async {
      final result = await runExtensions();
      expect(findByQualified(result, 'LiveHelpers'), isNull);
      final stale = findByQualified(result, 'LiveHelpers.stale');
      expect(stale, isNotNull);
      expect(stale!.kind, SymbolKind.method);
    });

    test('an unnamed extension is reported whole as `extension on <type>`, '
        'its members unqualified', () async {
      final result = await runExtensions();
      final decl = findByQualified(result, 'extension on String');
      expect(decl, isNotNull);
      expect(decl!.kind, SymbolKind.namespace);
      expect(decl.column, 1);
      expect(findByQualified(result, 'shoutedOnce'), isNull);
      expect(
        findByQualified(result, 'extension on String.shoutedOnce'),
        isNull,
      );
    });

    test('an extension named in a `show` stays; only its dead member is '
        'reported', () async {
      final result = await runExtensions();
      expect(findByQualified(result, 'ShownHelpers'), isNull);
      expect(findByQualified(result, 'ShownHelpers.shownButUnused'), isNotNull);
    });

    test('an extension with no members and no references is dead', () async {
      final result = await runExtensions();
      expect(findByQualified(result, 'Hollow'), isNotNull);
    });

    test('an unnamed extension is found when its type parameters stand where '
        'a name would', () async {
      final result = await runExtensions();
      for (final qualified in const [
        'extension on List<T>',
        'extension on T',
      ]) {
        final decl = findByQualified(result, qualified);
        expect(decl, isNotNull, reason: '$qualified is dead');
        expect(decl!.kind, SymbolKind.namespace);
        expect(decl.column, 1);
      }
      // Reported whole, so the members are not findings of their own.
      expect(findByQualified(result, 'firstOrNothing'), isNull);
      expect(findByQualified(result, 'deadNested'), isNull);
    });

    test('an extension type is a type: dead when nothing names it, reported '
        'whole with its members, like a dead class', () async {
      final result = await runExtensions();
      final decl = findByQualified(result, 'DeadMeters');
      expect(decl, isNotNull);
      expect(decl!.kind, SymbolKind.struct);
      expect(decl.kind.label, 'extension type');
      expect(decl.removalBlocked, isFalse);
      expect(findByQualified(result, 'DeadMeters.scaled'), isNotNull);
    });

    test(
      'an extension type referenced only from its own body is dead',
      () async {
        final result = await runExtensions();
        expect(findByQualified(result, 'SelfMeters'), isNotNull);
      },
    );

    test('an extension type named as a type is never reported', () async {
      final result = await runExtensions();
      expect(findByQualified(result, 'Meters'), isNull);
    });

    test('`-k extension-type` selects the extension types on their own, which '
        '`-k extension` does not', () async {
      expect(await byKind(.struct), {'DeadMeters', 'SelfMeters'});
      expect(
        await byKind(.namespace),
        isNot(contains(anyOf('DeadMeters', 'SelfMeters'))),
      );
    });

    test('`-k extension` alone keeps an extension whose members were never '
        'checked, reporting only a member-less one', () async {
      // Unchecked members can't be proven dead; `Hollow` has none.
      expect(await byKind(.namespace), {'Hollow'});
    });

    test('without extension candidates (`-k method`) the members are reported '
        'on their own', () async {
      final result = await runScenario(
        extensionFixture,
        kinds: const {.method},
      );
      expect(qualifiedNames(result.unused), {
        'DeadHelpers.first',
        'DeadHelpers.second',
        'LiveHelpers.stale',
        'shoutedOnce',
        'shoutedTwice',
        'ShownHelpers.shownButUnused',
      });
    });
  });
}
