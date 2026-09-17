import 'package:ciach/src/superclasses.dart';
import 'package:test/test.dart';

void main() {
  group('parameterListShape', () {
    test('reads the shape from the parameter list text', () {
      expect(parameterListShape(null), ParameterListShape.none);
      expect(parameterListShape(''), ParameterListShape.none);
      expect(parameterListShape('()'), ParameterListShape.none);
      expect(parameterListShape('(int x)'), ParameterListShape.positional);
      expect(
        parameterListShape('(int x, [int y])'),
        ParameterListShape.positional,
      );
      expect(
        parameterListShape('([int x])'),
        ParameterListShape.optionalPositional,
      );
      expect(parameterListShape('({int? x})'), ParameterListShape.named);
      expect(
        parameterListShape('({required int x})'),
        ParameterListShape.named,
      );
      expect(parameterListShape('({super.key})'), ParameterListShape.named);
      expect(
        parameterListShape('(int x, {int? y})'),
        ParameterListShape.positional,
      );
      expect(
        parameterListShape('(int x, {required int y})'),
        ParameterListShape.positional,
      );
    });
  });
}
