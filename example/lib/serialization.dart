// Dependency-free stand-ins exercising the serialization-hook handling:
// `toJson` is exempt by convention (jsonEncode can call it invisibly), while an
// unused `fromJson` is still reported. Scanned only by the dedicated tests (see
// test/finder_test.dart).

import 'dart:convert';

part 'serialization.freezed.dart';
part 'serialization.g.dart';

class JsonSerializable {
  const JsonSerializable();
}

class Freezed {
  const Freezed();
}

const freezed = Freezed();

/// Non-annotated: `toJson` is exempt by convention even without an annotation;
/// its `fromJson` is never invoked invisibly, so an unused one stays flagged.
class Plain {
  Plain(this.v);

  factory Plain.fromJson(Map<String, dynamic> json) => Plain(json['v'] as int);

  final int v;

  Map<String, dynamic> toJson() => <String, dynamic>{'v': v};
}

/// A visible `.toJson()` call keeps this hook used, so it is never flagged —
/// with or without `--report-tojson`.
class Visible {
  Visible(this.v);

  final int v;

  Map<String, dynamic> toJson() => <String, dynamic>{'v': v};
}

/// `toJson` returning a `List` — lists are valid JSON values, so it is exempt by
/// convention just like the `Map` case; its dead hook only shows with the flag.
class Listy {
  Listy(this.v);

  final int v;

  List<dynamic> toJson() => <dynamic>[v];
}

/// `toJson` returning a primitive `String` — also a valid JSON value, so exempt.
class Stringy {
  Stringy(this.v);

  final int v;

  String toJson() => v.toString();
}

/// Control: a `toJson` returning an unrelated domain type is not a JSON hook, so
/// an unused one stays flagged even without `--report-tojson`.
class Domainy {
  Domainy(this.v);

  final int v;

  Domainy toJson() => Domainy(v);
}

/// @JsonSerializable, to show the annotation no longer changes anything: its
/// generated `toJson` is exempt, its `fromJson` is still reported when unused.
@JsonSerializable()
class Profile {
  Profile(this.id);

  factory Profile.fromJson(Map<String, dynamic> json) =>
      _$ProfileFromJson(json);

  final int id;

  Map<String, dynamic> toJson() => _$ProfileToJson(this);
}

/// @freezed type with a generated `fromJson` nobody calls — still flagged.
@freezed
abstract class Point with _$Point {
  const factory Point(int x, int y) = _Point;

  const Point._();

  factory Point.fromJson(Map<String, dynamic> json) => _$PointFromJson(json);
}

/// Keeps the types alive. `jsonEncode` reaches `Plain`/`Point`/`Profile`
/// `toJson` by dynamic dispatch (no source-level token), while `Visible.toJson`
/// is called explicitly so the finder can resolve that one use.
String buildSerializable() => jsonEncode(<Object>[
  Plain(1),
  Visible(2).toJson(),
  Profile(3),
  const Point(2, 3),
  Listy(4),
  Stringy(5),
  Domainy(6),
]);
