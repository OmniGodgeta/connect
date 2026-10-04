import 'dart:convert';
import 'dart:typed_data';

import 'package:shared_preferences/shared_preferences.dart';

abstract class PhotoStore {
  Future<Uint8List?> load();

  Future<void> save(Uint8List? jpeg);
}

class MemoryPhotoStore implements PhotoStore {
  Uint8List? current;

  @override
  Future<Uint8List?> load() async => current;

  @override
  Future<void> save(Uint8List? jpeg) async {
    current = jpeg;
  }
}

class PrefsPhotoStore implements PhotoStore {
  PrefsPhotoStore(this._prefs);

  final SharedPreferences _prefs;

  static const _key = 'connect.photo';

  @override
  Future<Uint8List?> load() async {
    final raw = _prefs.getString(_key);
    if (raw == null || raw.isEmpty) return null;
    try {
      final bytes = base64Decode(raw);
      if (bytes.length < 4 || bytes[0] != 0xff || bytes[1] != 0xd8) {
        return null;
      }
      return bytes;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> save(Uint8List? jpeg) async {
    if (jpeg == null || jpeg.isEmpty) {
      await _prefs.remove(_key);
      return;
    }
    await _prefs.setString(_key, base64Encode(jpeg));
  }
}
