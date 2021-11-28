import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:fpdart/fpdart.dart';
import 'package:hive/hive.dart';
import 'package:hive/src/hive_impl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:synchronized/synchronized.dart';

abstract class Storage {
  Option<dynamic> read(String key);
  Future<bool> write(String key, dynamic value);
  Future<bool> delete(String key);
  Future<bool> clear();
}

class NullStorage implements Storage {
  @override
  Option<dynamic> read(String key) => none();

  @override
  Future<bool> write(String key, value) => Future.value(true);

  @override
  Future<bool> delete(String key) => Future.value(true);

  @override
  Future<bool> clear() => Future.value(true);
}

class HiveStorage implements Storage {
  HiveStorage._(this._box);

  static Future<HiveStorage> build() {
    return _lock.synchronized(
        () => _instance.map((i) => Future.value(i)).getOrElse(() async {
              final hive = HiveImpl();
              final dir = await getTemporaryDirectory();
              if (!kIsWeb) hive.init(dir.path);

              final box = await hive.openBox<dynamic>('persisted_bloc_stream');

              final instance = HiveStorage._(box);
              _instance = some(instance);
              return instance;
            }));
  }

  static final _lock = Lock();
  static Option<HiveStorage> _instance = none();

  final Box<dynamic> _box;

  Future<bool> _withBox(void Function(Box<dynamic>) f) => _box.isOpen
      ? _lock.synchronized(() {
          f(_box);
          return true;
        })
      : Future.value(false);

  @override
  Option<dynamic> read(String key) =>
      _box.isOpen ? optionOf(_box.get(key)) : none();

  @override
  Future<bool> write(String key, dynamic value) =>
      _withBox((box) => box.put(key, value));

  @override
  Future<bool> delete(String key) => _withBox((box) => box.delete(key));

  @override
  Future<bool> clear() => _withBox((box) => box.clear());
}

class SharedPreferencesStorage implements Storage {
  SharedPreferencesStorage._(this._prefs);

  static Future<SharedPreferencesStorage> build() =>
      _lock.synchronized(() => SharedPreferences.getInstance()
          .then((p) => SharedPreferencesStorage._(p)));

  static final _lock = Lock();

  final SharedPreferences _prefs;

  String _prefixKey(String key) => 'pbs_$key';

  @override
  Option<dynamic> read(String key) => optionOf(_prefs.get(_prefixKey(key)));

  @override
  Future<bool> write(String key, dynamic value) =>
      _lock.synchronized(() => _prefs.setString(_prefixKey(key), value));

  @override
  Future<bool> delete(String key) =>
      _lock.synchronized(() => _prefs.remove(_prefixKey(key)));

  /// No-op
  @override
  Future<bool> clear() => Future.value(false);
}
