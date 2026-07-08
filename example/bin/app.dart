import 'package:sample_pkg/extensions.dart';
import 'package:sample_pkg/greeting.dart';
import 'package:sample_pkg/shapes.dart';
import 'package:sample_pkg/user.dart';

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
}
