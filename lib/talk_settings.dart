import 'package:shared_preferences/shared_preferences.dart';

enum TalkMode { hold, voice }

class TalkSettings {
  const TalkSettings({this.mode = TalkMode.hold, this.noiseCancel = true});

  final TalkMode mode;
  final bool noiseCancel;

  TalkSettings copyWith({TalkMode? mode, bool? noiseCancel}) {
    return TalkSettings(
      mode: mode ?? this.mode,
      noiseCancel: noiseCancel ?? this.noiseCancel,
    );
  }
}

abstract class TalkSettingsStore {
  Future<TalkSettings> load();

  Future<void> save(TalkSettings settings);
}

class MemoryTalkSettings implements TalkSettingsStore {
  TalkSettings current = const TalkSettings();

  @override
  Future<TalkSettings> load() async => current;

  @override
  Future<void> save(TalkSettings settings) async {
    current = settings;
  }
}

class PrefsTalkSettings implements TalkSettingsStore {
  PrefsTalkSettings(this._prefs);

  final SharedPreferences _prefs;

  static const modeKey = 'connect.talk';
  static const noiseKey = 'connect.noise';

  @override
  Future<TalkSettings> load() async {
    final mode = _prefs.getString(modeKey) == 'voice'
        ? TalkMode.voice
        : TalkMode.hold;
    return TalkSettings(
      mode: mode,
      noiseCancel: _prefs.getBool(noiseKey) ?? true,
    );
  }

  @override
  Future<void> save(TalkSettings settings) async {
    await _prefs.setString(
      modeKey,
      settings.mode == TalkMode.voice ? 'voice' : 'hold',
    );
    await _prefs.setBool(noiseKey, settings.noiseCancel);
  }
}
