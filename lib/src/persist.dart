import 'dart:convert';

import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:fpdart/fpdart.dart';
import 'package:offset_iterator/offset_iterator.dart';
import 'package:offset_iterator/src/offset_iterator.dart';
import 'package:offset_iterator/src/storage.dart';

Option<T> _readCache<T>(
  Storage storage,
  Map<String, dynamic>? cache,
  String key,
  T Function(Object?) fromJson,
) {
  if (cache != null && cache.containsKey(key)) return cache[key];

  final data = storage
      .read(key)
      .flatMap((json) => Option.tryCatch(() => fromJson(jsonDecode(json))));
  cache?[key] = data;
  return data;
}

void Function(T) _writeCache<T>(
  Storage storage,
  Map<String, dynamic>? cache,
  String key,
  Object? Function(T) toJson,
) =>
    (value) {
      try {
        storage.write(key, jsonEncode(toJson(value)));
      } catch (_) {}
      cache?[key] = some(value);
    };

bool iListSublistEquality<T>(IList<T> prev, IList<T> next) {
  final prevLength = prev.length;
  final nextLength = next.length;

  if (prevLength == nextLength) {
    return prev == next;
  } else if (prevLength < nextLength) {
    return false;
  }

  return prev.sublist(0, nextLength) == next;
}

extension PersistExtension<T> on OffsetIterator<T> {
  OffsetIterator<T> persist({
    required Storage storage,
    Map<String, dynamic>? cache,
    required String key,
    bool Function(T prev, T next)? equals,
    required Object? Function(T) toJson,
    required T Function(Object?) fromJson,
  }) {
    key = 'OffsetIterator_$key';
    final seed = _readCache(storage, cache, key, fromJson);

    return tap(
      _writeCache(storage, cache, key, toJson),
      seed: seed.toNullable(),
    );
  }
}

extension PersistIListExtension<T> on OffsetIterator<IList<T>> {
  OffsetIterator<IList<T>> persistIList({
    required Storage storage,
    Map<String, dynamic>? cache,
    required String key,
    required Object? Function(T) toJson,
    required T Function(Object?) fromJson,
  }) {
    key = 'OffsetIterator_$key';
    final seed = _readCache(
      storage,
      cache,
      key,
      (json) => IList.fromJson(json, fromJson),
    );
    final write = _writeCache<IList<T>>(
      storage,
      cache,
      key,
      (l) => l.toJson(toJson),
    );

    return distinct(
      equals: iListSublistEquality,
      seed: seed.toNullable(),
    ).tap(write);
  }
}
