import 'package:shared_preferences/shared_preferences.dart';

class SavedIdentity {
  const SavedIdentity({this.id, this.name});

  final String? id;
  final String? name;
}

abstract class NameStore {
  Future<SavedIdentity> load();

  Future<void> save(String id, String name);
}

class MemoryNameStore implements NameStore {
  String? id;
  String? name;

  @override
  Future<SavedIdentity> load() async => SavedIdentity(id: id, name: name);

  @override
  Future<void> save(String id, String name) async {
    this.id = id;
    this.name = name;
  }
}

class PrefsNameStore implements NameStore {
  PrefsNameStore(this._prefs);

  final SharedPreferences _prefs;

  static const _idKey = 'connect.id';
  static const _nameKey = 'connect.name';

  @override
  Future<SavedIdentity> load() async {
    return SavedIdentity(id: _prefs.getString(_idKey), name: _prefs.getString(_nameKey));
  }

  @override
  Future<void> save(String id, String name) async {
    await _prefs.setString(_idKey, id);
    await _prefs.setString(_nameKey, name);
  }
}
