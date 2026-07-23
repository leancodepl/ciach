// Dependency-free freezed stand-ins for the deser-only-arm detection; the
// finder keys off the annotation text and warms the hand-written part files.
// Scanned only by the dedicated tests (see test/finder_test.dart).

part 'freezed_unions.freezed.dart';
part 'freezed_unions.g.dart';

class Freezed {
  const Freezed({this.unionKey});
  final String? unionKey;
}

const freezed = Freezed();

/// Union whose `fromJson` is used; its arms are only ever built by the
/// generated deserializer, so before the fix they were flagged.
@Freezed(unionKey: 'type')
sealed class Base with _$Base {
  const Base._();

  const factory Base.contestEvent(int score) = ContestEvent;
  const factory Base.matchEvent(String team) = MatchEvent;

  /// Never dispatched, so genuinely dead — but statically indistinguishable, so suppressed too.
  const factory Base.deadArm(int code) = DeadArm;

  factory Base.fromJson(Map<String, dynamic> json) => _$BaseFromJson(json);
}

/// No `fromJson`, so never deserialized: its arms stay flagged.
@freezed
sealed class Standalone with _$Standalone {
  const Standalone._();

  const factory Standalone.left(int n) = StandaloneLeft;
  const factory Standalone.right(String s) = StandaloneRight;
}

/// Control: a non-annotated class, so `Plain.make` stays flagged.
class Plain {
  const Plain();

  const factory Plain.make(int v) = PlainImpl;
}

/// Uses `Base.fromJson`; referenced from bin/app.dart.
Base decodeBase(Map<String, dynamic> json) => Base.fromJson(json);

/// Keeps [Plain] alive so its dead `Plain.make` is reported on its own.
Plain keepPlainAlive() => const Plain();
