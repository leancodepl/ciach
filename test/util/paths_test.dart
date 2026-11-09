/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

import 'dart:io';

import 'package:ciach/src/util/paths.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  final root = p.rootPrefix(p.current);
  final a = p.join(root, 'a');
  final ab = p.join(a, 'b');

  group('dirAndAncestors', () {
    test('lists the directory, then each one above it up to the root', () {
      expect(dirAndAncestors(ab), [ab, a, root]);
    });

    test('lists only the root for the root', () {
      expect(dirAndAncestors(root), [root]);
    });
  });

  group('dirContains', () {
    test('holds for the directory itself and for the paths below it', () {
      expect(dirContains(a, a), isTrue);
      expect(dirContains(a, ab), isTrue);
      expect(dirContains(root, ab), isTrue);
    });

    test('fails for a parent and for a sibling that shares a prefix', () {
      expect(dirContains(ab, a), isFalse);
      expect(dirContains(ab, p.join(a, 'bc')), isFalse);
    });
  });

  group('commonAncestor', () {
    test('is the directory that contains the others', () {
      expect(commonAncestor([ab, a]), a);
      expect(commonAncestor([a, ab]), a);
    });

    test('is the nearest directory above siblings', () {
      expect(commonAncestor([ab, p.join(a, 'c')]), a);
    });

    test('is the directory itself when it is the only one', () {
      expect(commonAncestor([ab]), ab);
    });
  });

  group('isRepositoryRoot', () {
    late Directory dir;

    setUp(() => dir = Directory.systemTemp.createTempSync('ciach_paths_'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('holds for a directory with a `.git` directory, as in a clone', () {
      Directory(p.join(dir.path, '.git')).createSync();
      expect(isRepositoryRoot(dir.path), isTrue);
    });

    test('holds for a directory with a `.git` file, as in a submodule', () {
      File(p.join(dir.path, '.git')).writeAsStringSync('gitdir: ../.git');
      expect(isRepositoryRoot(dir.path), isTrue);
    });

    test('fails for a directory without a `.git`', () {
      expect(isRepositoryRoot(dir.path), isFalse);
    });
  });
}
