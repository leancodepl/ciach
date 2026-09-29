import 'package:ciach/src/lsp/lsp_client.dart';
import 'package:pro_lsp/pro_lsp.dart' show Position;

/// Records that [error] cost the run an answer about [path] (absolute), and
/// that the run went on as [summary] says. [position] is zero-based; [name] is
/// the declaration concerned, if any.
typedef ProblemReporter =
    void Function(
      String summary,
      LspRequestException error, {
      required String path,
      Position? position,
      String? name,
    });
