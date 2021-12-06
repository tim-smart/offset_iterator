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
    SeedCallback<T>? fallbackSeed,
    int retention = 0,
    String name = 'persist',
  }) {
    key = 'OffsetIterator_$key';
    final currentValue = _readCache(storage, cache, key, fromJson);
    final write = _writeCache(storage, cache, key, toJson);
    final seed = generateSeed(
      override: () => currentValue,
      fallback: fallbackSeed,
    );
    Option<T> prev = const None();

    return tap(
      (item) {
        Future.microtask(() {
          if (prev.isSome() &&
              equals != null &&
              equals((prev as Some).value, item)) {
            return;
          }

          write(item);
          prev = Some(item);
        });
      },
      seed: () {
        if (seed != null) prev = seed();
        return prev;
      },
      retention: retention,
      name: name,
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
    SeedCallback<IList<T>>? fallbackSeed,
    int retention = 0,
    String name = 'persistIList',
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
        name: name,
      );
}
