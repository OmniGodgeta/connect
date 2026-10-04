import 'dart:async';

import 'package:flutter/foundation.dart';

import 'alerts.dart';
import 'audio_engine.dart';
import 'config.dart';
import 'name_store.dart';
import 'protocol.dart';
import 'relay.dart';
import 'room_store.dart';
import 'talk_settings.dart';
import 'voice_gate.dart';

enum RoomPhase { needName, connecting, live, left }

typedef Cancel = void Function();
typedef Scheduler = Cancel Function(Duration delay, void Function() fn);

class RoomController extends ChangeNotifier {
  RoomController({
    required this.relay,
    required this.audio,
    required this.names,
    required this.alerts,
    TalkSettingsStore? settings,
    RoomStore? rooms,
    this.schedule = _timer,
  }) : settings = settings ?? MemoryTalkSettings(),
       rooms = rooms ?? MemoryRoomStore();

  final Relay relay;
  final AudioEngine audio;
  final NameStore names;
  final RoomAlerts alerts;
  final TalkSettingsStore settings;
  final RoomStore rooms;
  final Scheduler schedule;
  final VoiceGate _gate = VoiceGate();

  RoomPhase phase = RoomPhase.needName;
  String? selfId;
  String? name;
  String roomName = everyoneRoom;
  List<RoomInfo> availableRooms = const [RoomInfo(everyoneRoom, 0)];
  bool picking = false;
  List<Person> people = const [];
  String? speakerId;
  String? speakerName;
  String? banner;
  bool holding = false;
  bool micDenied = false;
  TalkMode mode = TalkMode.hold;
  bool noiseCancel = true;
  bool voiceMuted = false;

  bool joined = false;
  bool _haveFloor = false;
  bool _wantFloor = false;
  bool _service = false;
  bool _everLive = false;
  bool _closed = false;
  int _gen = 0;
  int _attempt = 0;
  int _micToken = 0;
  String? _listeningTo;
  Cancel? _pending;
  bool? _openNoise;
  final List<Uint8List> _pendingAudio = <Uint8List>[];

  bool get selfTalking => _haveFloor;
  bool get waitingForFloor => holding && !_haveFloor;

  String get peopleLine {
    if (phase == RoomPhase.connecting && people.isEmpty) return 'Connecting';
    if (people.length <= 1) return 'Just you in the room';
    return '${people.length} people in the room';
  }

  String get statusLine {
    if (phase == RoomPhase.connecting) return banner ?? 'Connecting…';
    if (selfTalking) return "You're talking";
    if (waitingForFloor) return 'Asking for the floor…';
    if (speakerId != null && speakerId != selfId && speakerName != null) {
      return '$speakerName is talking';
    }
    if (banner != null) return banner!;
    if (mode == TalkMode.voice) {
      return voiceMuted ? 'Voice is muted' : 'Listening for your voice';
    }
    return 'Hold to talk';
  }

  String _notificationText() {
    if (speakerId != null && speakerId != selfId && speakerName != null) {
      return '$speakerName is talking';
    }
    return 'In $roomName';
  }

  static Cancel _timer(Duration delay, void Function() fn) {
    final timer = Timer(delay, fn);
    return timer.cancel;
  }

  Future<void> boot() async {
    final saved = await names.load();
    final talk = await settings.load();
    final savedRoom = await rooms.load();
    if (_closed) return;
    mode = talk.mode;
    noiseCancel = talk.noiseCancel;
    roomName = cleanName(savedRoom) ?? everyoneRoom;
    selfId = saved.id ?? newId();
    name = saved.name;
    if (name == null) {
      phase = RoomPhase.needName;
      notifyListeners();
      return;
    }
    await join();
  }

  Future<void> setName(String raw) async {
    final cleaned = cleanName(raw);
    if (cleaned == null) {
      banner = 'Use 1 to 24 characters.';
      notifyListeners();
      return;
    }
    name = cleaned;
    selfId ??= newId();
    await names.save(selfId!, name!);
    if (_closed) return;
    banner = null;
    if (phase == RoomPhase.live || phase == RoomPhase.connecting) {
      relay.hello(selfId!, name!, room: roomName);
      notifyListeners();
      return;
    }
    await join();
  }

  Future<void> join() async {
    if (name == null || selfId == null) {
      phase = RoomPhase.needName;
      notifyListeners();
      return;
    }
    joined = true;
    banner = 'Connecting…';
    phase = RoomPhase.connecting;
    notifyListeners();
    unawaited(alerts.requestNotifications());
    await _connect();
  }

  Future<void> leave() async {
    joined = false;
    picking = false;
    _gen += 1;
    _pending?.call();
    _pending = null;
    phase = RoomPhase.left;
    _dropLocalFloor();
    people = const [];
    speakerId = null;
    speakerName = null;
    banner = null;
    _service = false;
    await audio.stopMic();
    await audio.stopPlay();
    await relay.close();
    await alerts.stop();
    if (!_closed) notifyListeners();
  }

  Future<void> setMode(TalkMode next) async {
    if (mode == next || _closed) return;
    if (_wantFloor || _haveFloor) {
      _wantFloor = false;
      _haveFloor = false;
      holding = false;
      if (phase == RoomPhase.live) relay.ptt(false);
    }
    _gate.reset();
    _pendingAudio.clear();
    mode = next;
    voiceMuted = false;
    banner = null;
    await _saveTalk();
    if (!_closed) notifyListeners();
    await _kickMic();
  }

  Future<void> setNoiseCancel(bool on) async {
    if (noiseCancel == on || _closed) return;
    noiseCancel = on;
    await _saveTalk();
    if (!_closed) notifyListeners();
    await _kickMic();
  }

  Future<void> toggleVoiceMute() async {
    if (mode != TalkMode.voice || _closed) return;
    voiceMuted = !voiceMuted;
    if (voiceMuted && (_wantFloor || _haveFloor)) {
      _wantFloor = false;
      _haveFloor = false;
      holding = false;
      if (phase == RoomPhase.live) relay.ptt(false);
    }
    _gate.reset();
    _pendingAudio.clear();
    banner = null;
    notifyListeners();
    await _kickMic();
  }

  Future<void> _saveTalk() {
    return settings.save(TalkSettings(mode: mode, noiseCancel: noiseCancel));
  }

  Future<void> openRooms() async {
    if (phase != RoomPhase.live || _closed) return;
    if (_wantFloor || _haveFloor) {
      _wantFloor = false;
      _haveFloor = false;
      holding = false;
      relay.ptt(false);
    }
    _gate.reset();
    _pendingAudio.clear();
    picking = true;
    relay.watchRooms(true);
    if (!_closed) notifyListeners();
    await _kickMic();
  }

  Future<void> closeRooms() async {
    if (!picking || _closed) return;
    picking = false;
    banner = null;
    relay.watchRooms(false);
    notifyListeners();
    await _kickMic();
  }

  Future<void> joinRoom(String raw) async {
    final cleaned = cleanName(raw);
    if (cleaned == null) {
      banner = 'Use 1 to 24 characters.';
      notifyListeners();
      return;
    }
    if (phase != RoomPhase.live || _closed) return;
    if (cleaned == roomName) {
      await closeRooms();
      return;
    }
    picking = false;
    relay.watchRooms(false);
    if (_wantFloor || _haveFloor) relay.ptt(false);
    _dropLocalFloor();
    banner = 'Joining $cleaned…';
    notifyListeners();
    relay.joinRoom(cleaned);
    await _kickMic();
  }

  Future<void> hold() async {
    if (mode != TalkMode.hold) return;
    if (phase != RoomPhase.live || _wantFloor || _haveFloor) return;
    _wantFloor = true;
    holding = true;
    banner = null;
    notifyListeners();
    final allowed = await audio.ensureMic();
    if (!_wantFloor || _closed) return;
    if (!allowed) {
      _wantFloor = false;
      holding = false;
      micDenied = true;
      banner = 'Allow the microphone to talk. You can still listen.';
      notifyListeners();
      return;
    }
    relay.ptt(true);
  }

  Future<void> release() async {
    if (mode != TalkMode.hold) return;
    if (!_wantFloor && !_haveFloor) return;
    _wantFloor = false;
    _haveFloor = false;
    holding = false;
    if (phase == RoomPhase.live && !_closed) relay.ptt(false);
    if (!_closed) notifyListeners();
    await _kickMic();
  }

  bool micOn = false;

  Future<void> background() => alerts.background();

  Future<void> _connect() async {
    if (!joined || _closed) return;
    final gen = ++_gen;
    _pending?.call();
    _pending = null;
    phase = RoomPhase.connecting;
    notifyListeners();
    try {
      await relay.connect((event) {
        if (gen != _gen || _closed) return;
        _onEvent(event, gen);
      });
      if (gen != _gen || _closed) return;
      relay.hello(selfId!, name!, room: roomName);
    } catch (_) {
      if (gen != _gen || _closed) return;
      _fail(gen);
    }
  }

  void _onEvent(RelayEvent event, int gen) {
    switch (event) {
      case WelcomeEvent():
        _everLive = true;
        phase = RoomPhase.live;
        banner = null;
        _attempt = 0;
        final nextRoom = cleanName(event.room ?? '');
        if (nextRoom != null && nextRoom != roomName) {
          roomName = nextRoom;
          unawaited(rooms.save(roomName));
        }
        _pushNotification();
        notifyListeners();
        _kickMic();
      case RoomsEvent():
        if (event.rooms.isNotEmpty) availableRooms = event.rooms;
        notifyListeners();
      case RosterEvent():
        people = event.people;
        _applySpeaker(event.speakerId, _nameFor(event.speakerId));
        if (phase == RoomPhase.live) _pushNotification();
        notifyListeners();
        _kickMic();
      case FloorEvent():
        _onFloor(event);
      case TalkEvent():
        if (event.down) {
          _applySpeaker(event.id, event.name);
          if (event.id != selfId) {
            _gate.reset();
            _pendingAudio.clear();
            _wantFloor = false;
            if (!_haveFloor) holding = false;
          }
        } else if (speakerId == event.id) {
          _applySpeaker(null, null);
        }
        if (phase == RoomPhase.live) _pushNotification();
        notifyListeners();
        _kickMic();
      case AudioEvent():
        if (_listeningTo != null) audio.play(event.pcm);
      case ErrorEvent():
        banner = switch (event.code) {
          'full' => 'That room is full.',
          'rooms' => 'Too many rooms are open.',
          'room' => 'Use 1 to 24 characters.',
          _ => 'That name did not stick. Try another.',
        };
        notifyListeners();
      case DisconnectedEvent():
        picking = false;
        _dropLocalFloor();
        _fail(gen);
    }
  }

  void _onFloor(FloorEvent event) {
    if (!event.ok) {
      final wanted = _wantFloor || _haveFloor;
      _wantFloor = false;
      _haveFloor = false;
      holding = false;
      _gate.reset();
      _pendingAudio.clear();
      if (wanted) {
        if (event.reason == 'timeout') {
          banner = mode == TalkMode.voice
              ? 'Speak again in a moment.'
              : 'Let go, then hold again.';
        } else if (event.by == null || event.by!.isEmpty) {
          banner = 'Someone else is talking.';
        } else {
          banner = '${event.by} is talking.';
        }
      }
      notifyListeners();
      _kickMic();
      return;
    }
    if (!_wantFloor) {
      relay.ptt(false);
      return;
    }
    _haveFloor = true;
    banner = null;
    _listeningTo = null;
    unawaited(audio.stopPlay());
    final queued = List<Uint8List>.of(_pendingAudio);
    _pendingAudio.clear();
    for (final chunk in queued) {
      _send(chunk);
    }
    notifyListeners();
    _kickMic();
  }

  bool get _needMic {
    if (phase != RoomPhase.live || picking || _closed) return false;
    if (mode == TalkMode.hold) return _haveFloor;
    if (voiceMuted) return false;
    if (speakerId != null && speakerId != selfId && !_haveFloor) return false;
    return true;
  }

  Future<void>? _micJob;

  Future<void> _kickMic() {
    final previous = _micJob ?? Future<void>.value();
    final next = previous.catchError((Object _) {}).then((_) => _syncMic());
    _micJob = next.catchError((Object _) {});
    return _micJob!;
  }

  Future<void> _syncMic() async {
    final want = _needMic;
    if (want && micOn && _openNoise == noiseCancel) return;
    if (!want && !micOn) return;
    final token = ++_micToken;
    if (micOn) {
      micOn = false;
      _openNoise = null;
      await audio.stopMic();
    }
    if (token != _micToken || _closed || !_needMic) return;
    final allowed = await audio.ensureMic();
    if (token != _micToken || _closed || !_needMic) return;
    if (!allowed) {
      micDenied = true;
      banner = 'Allow the microphone to talk. You can still listen.';
      if (mode == TalkMode.voice) voiceMuted = true;
      notifyListeners();
      return;
    }
    try {
      await audio.startMic(
        (chunk) => _onChunk(token, chunk),
        noiseCancel: noiseCancel,
      );
    } catch (_) {
      if (token != _micToken || _closed) return;
      micOn = false;
      banner = 'The microphone did not start.';
      if (_haveFloor || _wantFloor) {
        _haveFloor = false;
        _wantFloor = false;
        holding = false;
        relay.ptt(false);
      }
      notifyListeners();
      return;
    }
    if (token != _micToken || !_needMic) {
      await audio.stopMic();
      return;
    }
    micOn = true;
    _openNoise = noiseCancel;
  }

  void _onChunk(int token, Uint8List chunk) {
    if (token != _micToken || _closed) return;
    if (mode == TalkMode.hold) {
      if (_haveFloor) _send(chunk);
      return;
    }
    final decision = _gate.push(chunk);
    if (decision.justOpened) {
      _wantFloor = true;
      holding = true;
      banner = null;
      _pendingAudio.addAll(decision.burst);
      _trimPending();
      relay.ptt(true);
      notifyListeners();
      return;
    }
    if (decision.open || decision.justClosed) {
      if (_haveFloor) {
        _send(chunk);
      } else if (_wantFloor) {
        _pendingAudio.add(Uint8List.fromList(chunk));
        _trimPending();
      }
    }
    if (decision.justClosed) _finishVoice();
  }

  void _finishVoice() {
    final had = _wantFloor || _haveFloor;
    _wantFloor = false;
    _haveFloor = false;
    holding = false;
    _pendingAudio.clear();
    if (had && phase == RoomPhase.live && !_closed) relay.ptt(false);
    if (!_closed) notifyListeners();
  }

  void _send(Uint8List pcm) {
    for (final frame in pcmFrames(pcm)) {
      relay.audio(Uint8List.fromList(frame));
    }
  }

  void _trimPending() {
    var bytes = 0;
    for (final chunk in _pendingAudio) {
      bytes += chunk.length;
    }
    final cap = ConnectConfig.sampleRate * 2;
    while (_pendingAudio.length > 1 && bytes > cap) {
      bytes -= _pendingAudio.removeAt(0).length;
    }
  }

  void _applySpeaker(String? id, String? speaker) {
    speakerId = id;
    speakerName = speaker;
    if (id == null || id == selfId) {
      if (_listeningTo != null) {
        _listeningTo = null;
        unawaited(audio.stopPlay());
      }
      return;
    }
    if (_listeningTo == id) return;
    _listeningTo = id;
    unawaited(audio.beginListen());
  }

  String? _nameFor(String? id) {
    if (id == null) return null;
    for (final person in people) {
      if (person.id == id) return person.name;
    }
    return speakerId == id ? speakerName : null;
  }

  void _dropLocalFloor() {
    _wantFloor = false;
    _haveFloor = false;
    holding = false;
    _micToken += 1;
    _openNoise = null;
    _gate.reset();
    _pendingAudio.clear();
    _listeningTo = null;
    speakerId = null;
    speakerName = null;
    if (micOn) {
      micOn = false;
      unawaited(audio.stopMic());
    }
    unawaited(audio.stopPlay());
  }

  void _fail(int gen) {
    phase = RoomPhase.connecting;
    banner = _everLive
        ? 'Reconnecting. Tailscale has to be on, and this PC has to be awake.'
        : "Can't reach the room. Tailscale has to be on, and this PC has to be awake.";
    notifyListeners();
    _scheduleRetry(gen);
  }

  void _scheduleRetry(int gen) {
    if (!joined || _closed) return;
    _pending?.call();
    final step = _attempt.clamp(0, 4);
    _attempt += 1;
    const waits = <int>[1, 2, 4, 8, 10];
    _pending = schedule(Duration(seconds: waits[step]), () {
      if (gen != _gen || !joined || _closed) return;
      unawaited(_connect());
    });
  }

  void _pushNotification() {
    final text = _notificationText();
    if (_service) {
      unawaited(alerts.update(text));
    } else {
      _service = true;
      unawaited(alerts.start(text));
    }
  }

  @override
  void dispose() {
    _closed = true;
    joined = false;
    _gen += 1;
    _pending?.call();
    unawaited(relay.close());
    unawaited(audio.dispose());
    unawaited(alerts.stop());
    super.dispose();
  }
}
