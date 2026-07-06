import 'package:sample_pkg/sample.dart';

void main() {
  final user = UsedClass('root');
  user.greet();
  registerHandlers();
  print(usedConstant);

  // Dog is instantiated (so both classes are used), but sound() is never
  // called. Animal.sound is therefore genuinely unused, and Dog.sound is only
  // reported when overrides are included (--overrides).
  final Animal animal = Dog();
  print(animal);
}
