import 'dart:convert';

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

extension PersistExtension<T> on OffsetIterator<T, dynamic> {
  OffsetIterator<T, int> persist({
    required Storage storage,
    required String key,
    required Object? Function(T) toJson,
    required T Function(Object?) fromJson,
    Map<String, dynamic>? cache,
  }) {
    key = 'OffsetIterator_$key';
    final seed = _readCache(storage, cache, key, fromJson);

    return tap(
      _writeCache(storage, cache, key, toJson),
      seed: seed.toNullable(),
    );
  }
}
