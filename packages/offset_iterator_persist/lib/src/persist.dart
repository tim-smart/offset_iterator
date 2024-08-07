// ignore_for_file: library_prefixes

import 'package:elemental/elemental.dart';
import 'package:offset_iterator/offset_iterator.dart';
import 'package:offset_iterator_persist/src/storage.dart';

Option<T> _readCache<T>(
  Storage storage,
  Map<String, dynamic>? cache,
  String key,
  T Function(Object?) fromJson,
) {
  if (cache != null && cache.containsKey(key)) return cache[key];

  final data = storage.read(key).flatMapThrowable(fromJson);
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
        storage.write(key, toJson(value));
      } catch (_) {}
      cache?[key] = Option.of(value);
    };

bool iListSublistEquality<T>(IList<T> prev, IList<T> next) {
  final prevLength = prev.length;
  final nextLength = next.length;

  if (prevLength == nextLength) {
    return prev == next;
  } else if (next.isEmpty || prevLength < nextLength) {
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
    bool? cancelOnError,
    bool bubbleCancellation = true,
  }) {
    final currentValue = _readCache(storage, cache, key, fromJson);
    final write = _writeCache(storage, cache, key, toJson);
    final seed = currentValue.match(
      () => generateSeed(fallback: fallbackSeed),
      (v) => () => Option.of(v),
    );
    Option<T> prev = const None();

    return tap(
      (item) {
        Future.microtask(() {
          if (prev is Some &&
              equals != null &&
              equals((prev as Some).value, item)) {
            return;
          }

          write(item);
          prev = Option.of(item);
        });
      },
      seed: () {
        if (seed != null) prev = seed();
        return prev;
      },
      retention: retention,
      name: name,
      cancelOnError: cancelOnError,
      bubbleCancellation: bubbleCancellation,
    );
  }

  OffsetIterator<T> cache({
    required String key,
    required Map<String, dynamic> cache,
    bool Function(T prev, T next)? equals,
    SeedCallback<T>? fallbackSeed,
    int retention = 0,
    String name = 'cache',
    bool? cancelOnError,
    bool bubbleCancellation = true,
  }) =>
      persist(
        cache: cache,
        storage: NullStorage(),
        key: key,
        fromJson: (val) => null as T,
        toJson: (p0) => null,
        fallbackSeed: fallbackSeed,
        retention: retention,
        name: name,
        equals: equals,
        cancelOnError: cancelOnError,
        bubbleCancellation: bubbleCancellation,
      );
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
    bool? cancelOnError,
    bool bubbleCancellation = true,
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
        cancelOnError: cancelOnError,
        bubbleCancellation: bubbleCancellation,
      );

  OffsetIterator<IList<T>> cacheIList({
    required String key,
    required Map<String, dynamic> cache,
    SeedCallback<IList<T>>? fallbackSeed,
    int retention = 0,
    String name = 'cacheIList',
    bool? cancelOnError,
    bool bubbleCancellation = true,
  }) =>
      this.cache(
        key: key,
        cache: cache,
        equals: iListSublistEquality,
        fallbackSeed: fallbackSeed,
        retention: retention,
        name: name,
        cancelOnError: cancelOnError,
        bubbleCancellation: bubbleCancellation,
      );
}
