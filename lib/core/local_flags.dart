import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'config.dart';

/// Piccoli dati salvati sul telefono (es. walkout già visto, traguardi già festeggiati).
/// In demo e nei test restano in memoria.
abstract class LocalFlags {
  Future<String?> getString(String key);
  Future<void> setString(String key, String value);
  Future<List<String>> getList(String key);
  Future<void> setList(String key, List<String> value);
}

class _DeviceFlags implements LocalFlags {
  final _prefs = SharedPreferencesAsync();

  @override
  Future<String?> getString(String key) => _prefs.getString(key);
  @override
  Future<void> setString(String key, String value) =>
      _prefs.setString(key, value);
  @override
  Future<List<String>> getList(String key) async =>
      await _prefs.getStringList(key) ?? const [];
  @override
  Future<void> setList(String key, List<String> value) =>
      _prefs.setStringList(key, value);
}

class MemoryFlags implements LocalFlags {
  final values = <String, Object>{};

  @override
  Future<String?> getString(String key) async => values[key] as String?;
  @override
  Future<void> setString(String key, String value) async => values[key] = value;
  @override
  Future<List<String>> getList(String key) async =>
      (values[key] as List<String>?) ?? const [];
  @override
  Future<void> setList(String key, List<String> value) async =>
      values[key] = List.of(value);
}

final localFlagsProvider = Provider<LocalFlags>(
  (ref) => AppConfig.isDemo ? MemoryFlags() : _DeviceFlags(),
);
