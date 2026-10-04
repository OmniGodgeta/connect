import 'package:shared_preferences/shared_preferences.dart';

import 'protocol.dart';

abstract class RoomStore {
  Future<String> load();

  Future<void> save(String room);
}

class MemoryRoomStore implements RoomStore {
  String current = everyoneRoom;

  @override
  Future<String> load() async => current;

  @override
  Future<void> save(String room) async {
    current = room;
  }
}

class PrefsRoomStore implements RoomStore {
  PrefsRoomStore(this._prefs);

  final SharedPreferences _prefs;

  static const key = 'connect.room';

  @override
  Future<String> load() async => _prefs.getString(key) ?? everyoneRoom;

  @override
  Future<void> save(String room) async {
    await _prefs.setString(key, room);
  }
}
