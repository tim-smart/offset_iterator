import 'dart:convert';

import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:fpdart/fpdart.dart';
import 'package:offset_iterator/offset_iterator.dart';
import 'package:offset_iterator_persist/src/storage.dart';

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
    T? fallbackSeed,
    int? retention,
  }) {
    key = 'OffsetIterator_$key';
    final seed = _readCache(storage, cache, key, fromJson);
    final write = _writeCache(storage, cache, key, toJson);
    T? prev = seed.toNullable() ?? fallbackSeed;

    return tap(
      (item) {
        Future.microtask(() {
          if (prev != null && equals != null && equals(prev!, item)) return;
          write(item);
          prev = item;
        });
      },
      seed: prev,
      retention: retention,
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
    IList<T>? fallbackSeed,
    int? retention,
  }) =>
      persist(
        storage: storage,
        cache: cache,
        key: key,
        equals: iListSublistEquality,
        toJson: (l) => l.toJson(toJson),
        fromJson: (json) => IList.fromJson(json, fromJson),
        fallbackSeed: fallbackSeed,
        retention: retention,
      );
}
