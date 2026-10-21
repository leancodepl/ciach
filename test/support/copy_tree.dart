/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

import 'dart:io';

import 'package:path/path.dart' as p;

/// Copies [from] into [to], `.dart_tool` included.
void copyTree(Directory from, Directory to) {
  for (final entity in from.listSync(recursive: true, followLinks: false)) {
    final relative = p.relative(entity.path, from: from.path);
    final target = p.join(to.path, relative);
    if (entity is Directory) {
      Directory(target).createSync(recursive: true);
    } else if (entity is File) {
      File(target).parent.createSync(recursive: true);
      entity.copySync(target);
    }
  }
}
