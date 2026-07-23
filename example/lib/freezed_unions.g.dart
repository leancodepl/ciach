// GENERATED CODE - DO NOT MODIFY BY HAND
// Hand-written to mimic json_serializable output (not produced by build_runner).
// ignore_for_file: type=lint

part of 'freezed_unions.dart';

// Builds concretes directly; `deadArm` is deliberately absent from the dispatch.
Base _$BaseFromJson(Map<String, dynamic> json) =>
    switch (json['type'] as String) {
      'contestEvent' => _$ContestEventFromJson(json),
      'matchEvent' => _$MatchEventFromJson(json),
      _ => throw ArgumentError('unknown Base type: ${json['type']}'),
    };

ContestEvent _$ContestEventFromJson(Map<String, dynamic> json) =>
    ContestEvent(json['score'] as int);

MatchEvent _$MatchEventFromJson(Map<String, dynamic> json) =>
    MatchEvent(json['team'] as String);
