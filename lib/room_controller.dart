import 'dart:async';

import 'package:flutter/foundation.dart';

import 'alerts.dart';
import 'audio_engine.dart';
import 'name_store.dart';
import 'protocol.dart';
import 'relay.dart';

enum RoomPhase { needName, connecting, live, left }

typedef Cancel = void Function();
typedef Scheduler = Cancel Function(Duration delay, void Function() fn);

class RoomController extends ChangeNotifier {
  RoomController({
    required this.relay,
    required this.audio,
    required this.names,
    required this.alerts,
    this.schedule = _timer,
  });

  final Relay relay;
  final AudioEngine audio;
  final NameStore names;
  final RoomAlerts alerts;
  final Scheduler schedule;

  RoomPhase phase = RoomPhase.needName;
  String? selfId;
  String? name;
  List<Person> people = const [];
  String? speakerId;
  String? speakerName;
  String? banner;
  bool holding = false;
  bool micDenied = false;

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
    return 'Hold to talk';
  }

  String _notificationText() {
    if (speakerId != null && speakerId != selfId && speakerName != null) {
      return '$speakerName is talking';
    }
    return 'In the room';
  }

  static Cancel _timer(Duration delay, void Function() fn) {
    final timer = Timer(delay, fn);
    return timer.cancel;
  }

  Future<void> boot() async {
    final saved = await names.load();
    if (_closed) return;
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
      relay.hello(selfId!, name!);
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
    _gen += 1;
    _pending?.call();
    _pending = null;
    _dropLocalFloor();
    phase = RoomPhase.left;
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

  Future<void> hold() async {
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
    if (!_wantFloor && !_haveFloor) return;
    _wantFloor = false;
    _haveFloor = false;
    holding = false;
    _micToken += 1;
    final stopMic = micOn;
    micOn = false;
    if (stopMic) await audio.stopMic();
    if (phase == RoomPhase.live && !_closed) relay.ptt(false);
    if (!_closed) notifyListeners();
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
      relay.hello(selfId!, name!);
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
        _pushNotification();
        notifyListeners();
      case RosterEvent():
        people = event.people;
        _applySpeaker(event.speakerId, _nameFor(event.speakerId));
        if (phase == RoomPhase.live) _pushNotification();
        notifyListeners();
      case FloorEvent():
        _onFloor(event);
      case TalkEvent():
        if (event.down) {
          _applySpeaker(event.id, event.name);
        } else if (speakerId == event.id) {
          _applySpeaker(null, null);
        }
        if (phase == RoomPhase.live) _pushNotification();
        notifyListeners();
      case AudioEvent():
        if (_listeningTo != null) audio.play(event.pcm);
      case ErrorEvent():
        banner = 'That name did not stick. Try another.';
        notifyListeners();
      case DisconnectedEvent():
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
      _micToken += 1;
      if (micOn) {
        micOn = false;
        unawaited(audio.stopMic());
      }
      if (wanted) {
        banner = event.reason == 'timeout'
            ? 'Let go, then hold again.'
            : (event.by == null || event.by!.isEmpty)
            ? 'Someone else is talking.'
            : '${event.by} is talking.';
      }
      notifyListeners();
      return;
    }
    if (!_wantFloor) {
      relay.ptt(false);
      return;
    }
    _haveFloor = true;
    banner = null;
    micOn = true;
    _listeningTo = null;
    unawaited(audio.stopPlay());
    notifyListeners();
    unawaited(_openMic());
  }

  Future<void> _openMic() async {
    final token = _micToken;
    try {
      await audio.startMic((chunk) {
        if (_haveFloor && token == _micToken) relay.audio(chunk);
      });
    } catch (_) {
      if (token != _micToken || _closed) return;
      _haveFloor = false;
      _wantFloor = false;
      holding = false;
      micOn = false;
      relay.ptt(false);
      banner = 'The microphone did not start.';
      notifyListeners();
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
