import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

abstract class LevelStore {
  Future<Map<String, double>> load();

  Future<void> save(Map<String, double> levels);
}

class MemoryLevelStore implements LevelStore {
  Map<String, double> current = {};

  @override
  Future<Map<String, double>> load() async => Map<String, double>.of(current);

  @override
  Future<void> save(Map<String, double> levels) async {
    current = Map<String, double>.of(levels);
  }
}

class PrefsLevelStore implements LevelStore {
  PrefsLevelStore(this._prefs);

  final SharedPreferences _prefs;

  static const _key = 'connect.levels';

  @override
  Future<Map<String, double>> load() async {
    final raw = _prefs.getString(_key);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      final levels = <String, double>{};
      for (final entry in decoded.entries) {
        final key = entry.key;
        final value = entry.value;
        if (key is! String || value is! num) continue;
        levels[key] = value.toDouble().clamp(0.0, 1.0);
      }
      return levels;
    } catch (_) {
      return {};
    }
  }

  @override
  Future<void> save(Map<String, double> levels) async {
    if (levels.isEmpty) {
      await _prefs.remove(_key);
      return;
    }
    await _prefs.setString(_key, jsonEncode(levels));
  }
}
