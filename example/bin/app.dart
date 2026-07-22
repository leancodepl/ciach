import 'package:sample_pkg/callables.dart';
import 'package:sample_pkg/extensions.dart';
import 'package:sample_pkg/freezed_unions.dart';
import 'package:sample_pkg/greeting.dart';
import 'package:sample_pkg/orphans.dart';
import 'package:sample_pkg/private_ctors.dart';
import 'package:sample_pkg/shapes.dart';
import 'package:sample_pkg/unions.dart';
import 'package:sample_pkg/user.dart';
import 'package:sample_pkg/widgets.dart';

void main() {
  final user = UsedClass('root');
  user.greet();
  user.nickname = 'Rooty';
  print(user.nickname);
  registerHandlers();
  print(usedConstant);
  visitCount += 1;

  // Dog is instantiated (so both classes are used), but sound() is never
  // called. Animal.sound is therefore genuinely unused, and Dog.sound is only
  // reported when overrides are included (--overrides).
  final Animal animal = Dog();
  print(animal);
  (animal as Dog).pace(Direction.north);

  print(5.doubled());

  final sum = const Vector2(1, 2) + const Vector2(3, 4);
  print(sum.x + sum.y);

  // Constructs LiveWidget -> a real, external use, so it is never flagged.
  print(const LiveWidget());

  // References ReferencedAsTypeOnly as a *type* only (never constructs it), so
  // the class stays USED while its constructor is reported unused.
  const ReferencedAsTypeOnly? typed = null;
  print(typed);

  // Constructs LiveSignal -> a real, non-pattern use, so it is never flagged as
  // a dead union member even under --unused-union-members. Also exercises the
  // three pattern-matching sites over Signal.
  final Signal signal = LiveSignal();
  print(describeStatement(signal));
  print(describeExpression(signal));
  print(isIfCaseSignal(signal));

  // Invokes `Multiplier.call` via implicit-call syntax, which a reference
  // search can't resolve back to the declaration (like an operator), so a used
  // `call` is skipped rather than misreported.
  const multiplier = Multiplier(2);
  print(multiplier(21));

  // Private-constructor fixtures: each class is kept alive by a static
  // reference, but its private constructor is dead code and reported normally.
  // The sole zero-parameter `SoleMarker._()` additionally carries a
  // prevent-instantiation hint.
  print(SoleMarker.tag);
  print(MultiCtor.describe());
  print(ParamCtor.tag);

  // Uses `Base.fromJson` and keeps `Plain` alive, without calling any arm.
  print(decodeBase(const {'type': 'contestEvent', 'score': 1}));
  print(keepPlainAlive());
}
