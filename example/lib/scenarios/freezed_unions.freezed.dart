// GENERATED CODE - DO NOT MODIFY BY HAND
// Hand-written to mimic freezed output (not produced by build_runner).
// ignore_for_file: type=lint

part of 'freezed_unions.dart';

mixin _$Base {}

class ContestEvent extends Base {
  const ContestEvent(this.score) : super._();
  final int score;
}

class MatchEvent extends Base {
  const MatchEvent(this.team) : super._();
  final String team;
}

class DeadArm extends Base {
  const DeadArm(this.code) : super._();
  final int code;
}

mixin _$Standalone {}

class StandaloneLeft extends Standalone {
  const StandaloneLeft(this.n) : super._();
  final int n;
}

class StandaloneRight extends Standalone {
  const StandaloneRight(this.s) : super._();
  final String s;
}

class PlainImpl extends Plain {
  const PlainImpl(this.v) : super();
  final int v;
}
