import 'dart:typed_data';

import 'package:connect/alerts.dart';
import 'package:connect/audio_engine.dart';
import 'package:connect/name_store.dart';
import 'package:connect/protocol.dart';
import 'package:connect/relay.dart';
import 'package:connect/room_controller.dart';
import 'package:connect/room_store.dart';
import 'package:connect/talk_settings.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List tone(int samples, int amplitude) {
  final data = ByteData(samples * 2);
  for (var i = 0; i < samples; i++) {
    data.setInt16(i * 2, amplitude, Endian.little);
  }
  return data.buffer.asUint8List();
}

class FakeRelay implements Relay {
  void Function(RelayEvent event)? onEvent;
  final List<String> log = [];

  @override
  Future<void> connect(void Function(RelayEvent event) onEvent) async {
    this.onEvent = onEvent;
    log.add('connect');
  }

  @override
  void hello(String id, String name, {String? room}) =>
      log.add('hello:$name:${room ?? ''}');

  @override
  void joinRoom(String room) => log.add('join:$room');

  @override
  void watchRooms(bool watch) => log.add('rooms:$watch');

  @override
  void ptt(bool down) => log.add('ptt:$down');

  @override
  void audio(List<int> pcm) => log.add('audio:${pcm.length}');

  @override
  Future<void> close() async => log.add('close');

  void emit(RelayEvent event) => onEvent?.call(event);
}

class FakeAudio implements AudioEngine {
  bool mic = false;
  bool allow = true;
  int played = 0;
  int begins = 0;

  @override
  Future<bool> ensureMic() async => allow;

  void Function(Uint8List chunk)? onChunk;
  bool? noise;
  int starts = 0;

  bool alongside = false;

  @override
  Future<void> startMic(
    void Function(Uint8List chunk) onChunk, {
    required bool noiseCancel,
    bool alongside = false,
  }) async {
    mic = true;
    starts += 1;
    noise = noiseCancel;
    this.alongside = alongside;
    this.onChunk = onChunk;
  }

  @override
  Future<void> stopMic() async {
    mic = false;
  }

  @override
  Future<void> beginListen() async {
    begins += 1;
  }

  @override
  void play(Uint8List pcm) {
    played += pcm.length;
  }

  @override
  Future<void> stopPlay() async {}

  @override
  Future<void> dispose() async {}
}

class FakeAlerts extends NoopAlerts {
  final List<String> log = [];

  @override
  Future<void> start(String text) async => log.add('start:$text');

  @override
  Future<void> update(String text) async => log.add('update:$text');

  @override
  Future<void> stop() async => log.add('stop');
}

RoomController buildRoom({
  MemoryNameStore? names,
  FakeRelay? relay,
  FakeAudio? audio,
  FakeAlerts? alerts,
  MemoryTalkSettings? settings,
  MemoryRoomStore? rooms,
  Scheduler? schedule,
}) {
  return RoomController(
    relay: relay ?? FakeRelay(),
    audio: audio ?? FakeAudio(),
    names: names ?? MemoryNameStore(),
    settings: settings,
    rooms: rooms,
    alerts: alerts ?? FakeAlerts(),
    schedule: schedule ?? (_, _) => () {},
  );
}

Future<void> enter(RoomController room, FakeRelay relay, String name) async {
  await room.setName(name);
  relay.emit(WelcomeEvent(room.selfId!, name));
  relay.emit(RosterEvent([Person(room.selfId!, name)], null));
  await pumpEventQueue();
}

void main() {
  test('a blank name stays on the name step', () async {
    final room = buildRoom();
    await room.boot();
    expect(room.phase, RoomPhase.needName);
    await room.setName('   ');
    expect(room.phase, RoomPhase.needName);
    expect(room.banner, isNotNull);
  });

  test('hold waits for the floor, then the mic opens', () async {
    final relay = FakeRelay();
    final audio = FakeAudio();
    final room = buildRoom(relay: relay, audio: audio);
    await enter(room, relay, 'Eric');
    expect(room.phase, RoomPhase.live);
    expect(room.people.single.name, 'Eric');

    await room.hold();
    expect(relay.log, contains('ptt:true'));
    expect(audio.mic, isFalse);

    relay.emit(const FloorEvent(true, null));
    await pumpEventQueue();
    expect(audio.mic, isTrue);
    expect(room.selfTalking, isTrue);

    await room.release();
    expect(audio.mic, isFalse);
    expect(relay.log, contains('ptt:false'));
  });

  test('someone else talking blocks the mic and plays their audio', () async {
    final relay = FakeRelay();
    final audio = FakeAudio();
    final room = buildRoom(relay: relay, audio: audio);
    await enter(room, relay, 'Eric');

    relay.emit(const TalkEvent('alex0001', 'Alex', true));
    relay.emit(AudioEvent(Uint8List.fromList([1, 2, 0, 0])));
    await pumpEventQueue();
    expect(audio.begins, 1);
    expect(audio.played, 4);
    expect(room.statusLine, 'Alex is talking');

    await room.hold();
    relay.emit(const FloorEvent(false, 'Alex'));
    await pumpEventQueue();
    expect(audio.mic, isFalse);
    expect(room.holding, isFalse);
    expect(room.banner, 'Alex is talking.');
  });

  test('a saved name joins on boot and a drop schedules a retry', () async {
    final names = MemoryNameStore()
      ..id = 'abc12345abc12345'
      ..name = 'Eric';
    final relay = FakeRelay();
    late void Function() retry;
    final room = buildRoom(
      names: names,
      relay: relay,
      schedule: (delay, fn) {
        retry = fn;
        return () {};
      },
    );
    await room.boot();
    expect(relay.log.first, 'connect');
    relay.emit(WelcomeEvent(room.selfId!, 'Eric'));
    expect(room.phase, RoomPhase.live);

    relay.emit(const DisconnectedEvent(null));
    expect(room.phase, RoomPhase.connecting);
    retry();
    await pumpEventQueue();
    expect(relay.log.where((entry) => entry == 'connect').length, 2);
  });

  test(
    'voice waits for the floor, then keeps the mic open after silence',
    () async {
      final relay = FakeRelay();
      final audio = FakeAudio();
      final names = MemoryNameStore()
        ..id = 'abc12345abc12345'
        ..name = 'Eric';
      final settings = MemoryTalkSettings()
        ..current = const TalkSettings(mode: TalkMode.voice);
      final room = buildRoom(
        names: names,
        relay: relay,
        audio: audio,
        settings: settings,
      );
      await room.boot();
      relay.emit(WelcomeEvent(room.selfId!, 'Eric'));
      relay.emit(RosterEvent([Person(room.selfId!, 'Eric')], null));
      await pumpEventQueue();
      expect(audio.mic, isTrue);
      expect(audio.noise, isTrue);
      expect(room.statusLine, 'Listening for your voice');

      audio.onChunk!(tone(8000, 8000));
      expect(relay.log, contains('ptt:true'));
      expect(relay.log.where((entry) => entry.startsWith('audio:')), isEmpty);

      relay.emit(const FloorEvent(true, null));
      await pumpEventQueue();
      expect(
        relay.log.where((entry) => entry.startsWith('audio:')),
        isNotEmpty,
      );
      expect(room.selfTalking, isTrue);

      audio.onChunk!(tone(48000, 0));
      expect(relay.log, contains('ptt:false'));
      expect(audio.mic, isTrue);
      expect(room.selfTalking, isFalse);
    },
  );

  test('someone else talking closes the voice mic', () async {
    final relay = FakeRelay();
    final audio = FakeAudio();
    final names = MemoryNameStore()
      ..id = 'abc12345abc12345'
      ..name = 'Eric';
    final settings = MemoryTalkSettings()
      ..current = const TalkSettings(mode: TalkMode.voice);
    final room = buildRoom(
      names: names,
      relay: relay,
      audio: audio,
      settings: settings,
    );
    await room.boot();
    relay.emit(WelcomeEvent(room.selfId!, 'Eric'));
    await pumpEventQueue();
    expect(audio.mic, isTrue);

    relay.emit(const TalkEvent('alex0001', 'Alex', true));
    await pumpEventQueue();
    expect(audio.mic, isFalse);
    expect(room.statusLine, 'Alex is talking');
  });

  test('turning noise cancelling off reopens the mic without it', () async {
    final relay = FakeRelay();
    final audio = FakeAudio();
    final names = MemoryNameStore()
      ..id = 'abc12345abc12345'
      ..name = 'Eric';
    final settings = MemoryTalkSettings()
      ..current = const TalkSettings(mode: TalkMode.voice);
    final room = buildRoom(
      names: names,
      relay: relay,
      audio: audio,
      settings: settings,
    );
    await room.boot();
    relay.emit(WelcomeEvent(room.selfId!, 'Eric'));
    await pumpEventQueue();
    expect(audio.noise, isTrue);
    final starts = audio.starts;

    await room.setNoiseCancel(false);
    expect(audio.noise, isFalse);
    expect(audio.mic, isTrue);
    expect(audio.starts, starts + 1);
    expect(settings.current.noiseCancel, isFalse);
  });

  test('creating a room joins it and remembers the name', () async {
    final relay = FakeRelay();
    final store = MemoryRoomStore();
    final names = MemoryNameStore()
      ..id = 'abc12345abc12345'
      ..name = 'Eric';
    final room = buildRoom(names: names, relay: relay, rooms: store);
    await room.boot();
    relay.emit(WelcomeEvent(room.selfId!, 'Eric', room: everyoneRoom));
    relay.emit(RosterEvent([Person(room.selfId!, 'Eric')], null));
    await pumpEventQueue();
    expect(relay.log, contains('hello:Eric:Everyone'));

    await room.openRooms();
    expect(room.picking, isTrue);
    expect(relay.log, contains('rooms:true'));

    await room.joinRoom('   ');
    expect(room.picking, isTrue);
    expect(room.banner, 'Use 1 to 24 characters.');

    await room.joinRoom('Cabin');
    expect(room.picking, isFalse);
    expect(relay.log, contains('join:Cabin'));
    expect(room.roomName, everyoneRoom);

    relay.emit(const ErrorEvent('rooms'));
    await pumpEventQueue();
    expect(room.roomName, everyoneRoom);
    expect(room.statusLine, 'Too many rooms are open.');

    relay.emit(WelcomeEvent(room.selfId!, 'Eric', room: 'Cabin'));
    relay.emit(
      const RoomsEvent([RoomInfo(everyoneRoom, 0), RoomInfo('Cabin', 1)]),
    );
    await pumpEventQueue();
    expect(room.roomName, 'Cabin');
    expect(store.current, 'Cabin');
    expect(room.availableRooms.last.people, 1);
  });

  test('minimizing listens for voice and opening restores hold', () async {
    final relay = FakeRelay();
    final audio = FakeAudio();
    final settings = MemoryTalkSettings();
    final names = MemoryNameStore()
      ..id = 'abc12345abc12345'
      ..name = 'Eric';
    final room = buildRoom(
      names: names,
      relay: relay,
      audio: audio,
      settings: settings,
    );
    await room.boot();
    relay.emit(WelcomeEvent(room.selfId!, 'Eric', room: everyoneRoom));
    relay.emit(RosterEvent([Person(room.selfId!, 'Eric')], null));
    await pumpEventQueue();
    expect(room.mode, TalkMode.hold);
    expect(audio.mic, isFalse);

    await room.enterBackground();
    expect(room.inBackground, isTrue);
    expect(room.mode, TalkMode.voice);
    expect(room.voiceMuted, isFalse);
    expect(audio.mic, isTrue);
    expect(audio.alongside, isTrue);
    expect(settings.current.mode, TalkMode.hold);

    await room.leaveBackground();
    expect(room.inBackground, isFalse);
    expect(room.mode, TalkMode.hold);
    expect(audio.mic, isFalse);
    expect(settings.current.mode, TalkMode.hold);
  });

  test('minimizing unmutes voice and opening mutes it again', () async {
    final relay = FakeRelay();
    final audio = FakeAudio();
    final settings = MemoryTalkSettings()
      ..current = const TalkSettings(mode: TalkMode.voice);
    final names = MemoryNameStore()
      ..id = 'abc12345abc12345'
      ..name = 'Eric';
    final room = buildRoom(
      names: names,
      relay: relay,
      audio: audio,
      settings: settings,
    );
    await room.boot();
    relay.emit(WelcomeEvent(room.selfId!, 'Eric', room: everyoneRoom));
    await pumpEventQueue();
    await room.toggleVoiceMute();
    expect(room.voiceMuted, isTrue);
    expect(audio.mic, isFalse);

    await room.enterBackground();
    expect(room.voiceMuted, isFalse);
    expect(audio.mic, isTrue);

    await room.leaveBackground();
    expect(room.mode, TalkMode.voice);
    expect(room.voiceMuted, isTrue);
    expect(audio.mic, isFalse);
  });

  test('another person speaking moves their picture with the voice', () async {
    final relay = FakeRelay();
    final room = buildRoom(relay: relay);
    await enter(room, relay, 'Eric');
    relay.emit(const TalkEvent('alex0001', 'Alex', true));
    relay.emit(AudioEvent(tone(2400, 14000)));
    expect(room.speakerName, 'Alex');
    expect(room.voice.value.bass, greaterThan(0.4));
    expect(room.voice.value.quiet, isFalse);
  });
}
