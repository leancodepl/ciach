import 'package:ciach/src/candidates.dart';
import 'package:ciach/src/paths.dart';
import 'package:collection/collection.dart';

/// The Dart file gen-l10n generates from the template ARB file, and that ARB
/// file. Both are POSIX paths relative to the package root.
typedef Translations = ({String dartFile, String arbFile});

/// The [Translations] whose Dart file declares [candidate], if any. Such a
/// finding is report-only: the message is defined in the ARB file, so gen-l10n
/// would generate it again if it were removed from the Dart file.
Translations? translationsOf(
  Candidate candidate,
  List<Translations> translations,
  String rootPath,
) {
  final path = relativePosix(candidate.path, rootPath);
  return translations.firstWhereOrNull((t) => t.dartFile == path);
}
