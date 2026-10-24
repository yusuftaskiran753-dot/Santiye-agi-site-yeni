import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Cihazda kalıcı veri saklama (JSON). Bozuk kayıtlar sessizce yok sayılır.
class LocalStore {
  LocalStore(this.prefs);

  final SharedPreferences prefs;

  bool has(String key) => prefs.containsKey(key);

  List<Map<String, dynamic>> readMaps(String key) {
    final raw = prefs.getString(key);
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw) as List;
      return [
        for (final e in list)
          if (e is Map) Map<String, dynamic>.from(e),
      ];
    } catch (_) {
      return [];
    }
  }

  Future<void> writeMaps(String key, Iterable<Map<String, dynamic>> items) =>
      prefs.setString(key, jsonEncode(items.toList()));

  Map<String, dynamic>? readMap(String key) {
    final raw = prefs.getString(key);
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> writeMap(String key, Map<String, dynamic> value) => prefs.setString(key, jsonEncode(value));

  List<String> readStrings(String key) => prefs.getStringList(key) ?? const <String>[];

  Future<void> writeStrings(String key, Iterable<String> values) => prefs.setStringList(key, values.toList());

  Future<void> remove(String key) => prefs.remove(key);

  /// [prefix] ile başlayan tüm anahtarları siler ([keep] hariç).
  Future<void> clearPrefix(String prefix, {Set<String> keep = const {}}) async {
    for (final key in prefs.getKeys().toList()) {
      if (key.startsWith(prefix) && !keep.contains(key)) await prefs.remove(key);
    }
  }
}
