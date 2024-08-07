// ignore_for_file: library_prefixes

import 'dart:async';
import 'dart:convert';

import 'package:elemental/elemental.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
// ignore: implementation_imports
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
  Option<dynamic> read(String key) => const Option.none();

  @override
  Future<bool> write(String key, value) => Future.value(true);

  @override
  Future<bool> delete(String key) => Future.value(true);

  @override
  Future<bool> clear() => Future.value(true);
}

class HiveStorage implements Storage {
  HiveStorage._(this._box);

  static Future<HiveStorage> build({
    String boxName = 'offset_iterator_persist',
  }) {
    return _lock.synchronized(
        () => _instance.map((i) => Future.value(i)).getOrElse(() async {
              final hive = HiveImpl();
              final dir = await getTemporaryDirectory();
              if (!kIsWeb) hive.init(dir.path);

              final box = await hive.openBox<dynamic>(boxName);

              final instance = HiveStorage._(box);
              _instance = Option.of(instance);
              return instance;
            }));
  }

  static final _lock = Lock();
  static Option<HiveStorage> _instance = const Option.none();

  final Box<dynamic> _box;

  Future<bool> _withBox(void Function(Box<dynamic>) f) => _box.isOpen
      ? _lock.synchronized(() {
          f(_box);
          return true;
        })
      : Future.value(false);

  @override
  Option<dynamic> read(String key) =>
      _box.isOpen ? Option.fromNullable(_box.get(key)) : const Option.none();

  @override
  Future<bool> write(String key, dynamic value) =>
      _withBox((box) => box.put(key, value));

  @override
  Future<bool> delete(String key) => _withBox((box) => box.delete(key));

  @override
  Future<bool> clear() => _withBox((box) => box.clear());
}

class SharedPreferencesStorage implements Storage {
  SharedPreferencesStorage(
    this._prefs, {
    this.prefix = 'oip',
  });

  static Future<SharedPreferencesStorage> build({String prefix = 'oip'}) =>
      _lock.synchronized(() => SharedPreferences.getInstance()
          .then((p) => SharedPreferencesStorage(p, prefix: prefix)));

  static final _lock = Lock();

  final SharedPreferences _prefs;

  final String prefix;
  String _prefixKey(String key) => '${prefix}_$key';

  @override
  Option<dynamic> read(String key) => _prefs
      .getString(_prefixKey(key))
      .p(Option.fromNullable)
      .flatMapThrowable(jsonDecode);

  @override
  Future<bool> write(String key, dynamic value) =>
      _lock.synchronized(() => Option.tryCatch(() => jsonEncode(value)).match(
            () => false,
            (json) => _prefs.setString(_prefixKey(key), json),
          ));

  @override
  Future<bool> delete(String key) =>
      _lock.synchronized(() => _prefs.remove(_prefixKey(key)));

  /// No-op
  @override
  Future<bool> clear() => Future.value(false);
}
