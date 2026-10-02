import 'package:ciach/src/candidates.dart';
import 'package:ciach/src/paths.dart';

/// gen-l10n's template Dart file and the ARB file its messages come from,
/// both POSIX, relative to the package root.
typedef Translations = ({String dartFile, String arbFile});

/// The [Translations] [candidate] is declared in, if any. Its findings are
/// report-only: the message lives in the ARB file, and gen-l10n would
/// regenerate a removed one.
Translations? translationsOf(
  Candidate candidate,
  List<Translations> translations,
  String rootPath,
) {
  final path = relativePosix(candidate.path, rootPath);
  for (final t in translations) {
    if (t.dartFile == path) {
      return t;
    }
  }
  return null;
}
