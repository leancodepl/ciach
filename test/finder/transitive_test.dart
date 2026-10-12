@Timeout(Duration(minutes: 5))
library;

import 'dart:io';

import 'package:ciach/src/finder.dart';
import 'package:ciach/src/log.dart';
import 'package:ciach/src/models.dart';
import 'package:ciach/src/remover.dart';
import 'package:pro_lsp/pro_lsp.dart' show SymbolKind;
import 'package:test/test.dart';

import '../support/finder.dart';

void main() {
  setUpFixture();

  group('transitive (opt-in --transitive)', () {
    const fixture = ['lib/scenarios/transitive.dart'];

    Future<FinderResult> runTransitive({bool transitive = true}) =>
        runScenario(fixture, transitive: transitive);

    DeadReferrer asOwner(FinderResult result, String qualified) {
      final decl = findByQualified(result, qualified)!;
      return (
        qualifiedName: decl.qualifiedName,
        filePath: decl.filePath,
        line: decl.line,
      );
    }

    test('flag OFF: only what nothing references is reported', () async {
      final result = await runTransitive(transitive: false);
      expect(qualifiedNames(result.unused), {
        '_deadRoot',
        '_secondDeadRoot',
        'Lone.only',
        'Token.fromJson',
      });
      expect(qualifiedNames(result.docOnly), {'_docLinkedFromDead'});
      expect(
        result.unused.map((d) => d.onlyReferencedFrom),
        everyElement(isEmpty),
      );
    });

    test('flag ON: what only dead code referenced is reported too, each '
        'naming the finding it hangs on, and so are dead cycles', () async {
      final result = await runTransitive();
      expect(qualifiedNames(result.unused), {
        '_ping',
        '_pong',
        '_Chicken',
        '_Egg',
        '_deadRoot',
        '_secondDeadRoot',
        'Lone.only',
        '_onlyFromDeadRoot',
        '_deeper',
        '_sharedByDeadRoots',
        '_docLinkedFromDead',
        '_DeadHolder',
        'Odometer._deadReading',
        'Odometer._scale',
        'Token.fromJson',
        'Token.new',
      });
      expect(qualifiedNames(result.docOnly), isEmpty);

      List<DeadReferrer> via(String name) =>
          findByQualified(result, name)!.onlyReferencedFrom;
      expect(via('_deadRoot'), isEmpty, reason: 'dead in its own right');
      expect(via('Lone.only'), isEmpty);
      expect(via('_onlyFromDeadRoot'), [asOwner(result, '_deadRoot')]);
      expect(via('_deeper'), [asOwner(result, '_onlyFromDeadRoot')]);
      expect(via('_docLinkedFromDead'), [asOwner(result, '_deadRoot')]);
      expect(via('_DeadHolder'), [asOwner(result, '_deadRoot')]);
      expect(via('Odometer._deadReading'), [asOwner(result, '_deadRoot')]);
      expect(via('Odometer._scale'), [
        asOwner(result, 'Odometer._deadReading'),
      ]);
      // Referenced from two dead declarations: both are named, in source
      // order, not just whichever reference the server reported first.
      expect(via('_sharedByDeadRoots'), [
        asOwner(result, '_deadRoot'),
        asOwner(result, '_secondDeadRoot'),
      ]);
    });

    test('flag ON: a finding a group guard would block later stays '
        'removable, and the rounds settle', () async {
      final messages = <String>[];
      final logging = Logger.root.onRecord
          .where((r) => r.loggerName == 'ciach.finder')
          .listen((r) => messages.add(r.message));
      addTearDown(logging.cancel);
      final result = await runScenario(fixture, transitive: true);
      expect(messages, isNot(contains(startsWith('Stopping after'))));
      // Removable in round one, while `Token.new` was still used.
      expect(
        findByQualified(result, 'Token.fromJson')!.removalBlocked,
        isFalse,
      );
      // Dead once `fromJson` is, but the last constructor of a live class with
      // a final field, so it stays.
      final ctor = findByQualified(result, 'Token.new')!;
      expect(ctor.removalBlocked, isTrue);
      expect(ctor.onlyReferencedFrom, [asOwner(result, 'Token.fromJson')]);
    });

    test("flag ON: a dead class's members go with it, unreported", () async {
      final result = await runTransitive();
      final holder = findByQualified(result, '_DeadHolder');
      expect(holder, isNotNull);
      expect(holder!.kind, SymbolKind.class$);
      expect(holder.removalBlocked, isFalse);
      for (final member in ['_', 'make', 'value', '_seed']) {
        expect(
          findByQualified(result, '_DeadHolder.$member'),
          isNull,
          reason: '$member is removed with the class',
        );
      }
    });

    test('flag ON: a report-only finding stays, and keeps what it alone '
        'references', () async {
      final result = await runTransitive();
      final only = findByQualified(result, 'Lone.only');
      expect(only, isNotNull);
      expect(only!.removalBlocked, isTrue, reason: 'would empty the enum');
      expect(findByQualified(result, '_loneArg'), isNull);
    });

    test('flag ON: each member of a dead cycle names the others', () async {
      final result = await runTransitive();
      List<DeadReferrer> via(String name) =>
          findByQualified(result, name)!.onlyReferencedFrom;
      expect(via('_ping'), [asOwner(result, '_pong')]);
      expect(via('_pong'), [asOwner(result, '_ping')]);
      expect(via('_Chicken'), [asOwner(result, '_Egg')]);
      expect(via('_Egg'), [asOwner(result, '_Chicken')]);
      expect(findByQualified(result, '_Chicken.lay'), isNull);
      expect(findByQualified(result, '_Egg.hatch'), isNull);
    });

    test(
      'flag ON: a live anchor keeps its chain, and a cycle it enters',
      () async {
        final result = await runTransitive();
        for (final name in [
          'transitiveAnchor',
          '_usedByLive',
          '_liveCycle',
          '_liveCycleBack',
        ]) {
          expect(findByQualified(result, name), isNull, reason: name);
        }
      },
    );

    test(
      'flag ON: after --remove, a second run has nothing left to remove',
      () async {
        final copy = Directory.systemTemp.createTempSync('ciach_transitive_');
        addTearDown(() => copy.deleteSync(recursive: true));
        copyTree(Directory(fixturePath), copy);
        Future<FinderResult> run() => Ciach(
          .new(rootPath: copy.path, includeGlobs: fixture, transitive: true),
        ).run();

        final first = await run();
        expect(
          qualifiedNames(first.unused),
          containsAll(['_ping', '_Chicken']),
        );
        removeDeclarations(first.unused, copy.path);

        final second = await run();
        expect(
          qualifiedNames(second.unused.where((d) => !d.removalBlocked)),
          isEmpty,
        );
        expect(qualifiedNames(second.docOnly), isEmpty);
      },
    );
  });
}
