// GENERATED CODE - DO NOT MODIFY BY HAND
// Hand-written to mimic json_serializable output. NOT produced by build_runner.
// ignore_for_file: type=lint

part of 'serialization.dart';

Profile _$ProfileFromJson(Map<String, dynamic> json) =>
    Profile(json['id'] as int);

Map<String, dynamic> _$ProfileToJson(Profile instance) => <String, dynamic>{
  'id': instance.id,
};

_Point _$PointFromJson(Map<String, dynamic> json) =>
    _Point(json['x'] as int, json['y'] as int);

Map<String, dynamic> _$PointToJson(_Point instance) => <String, dynamic>{
  'x': instance.x,
  'y': instance.y,
};
