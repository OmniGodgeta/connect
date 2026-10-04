import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

class Person {
  const Person(this.id, this.name);

  final String id;
  final String name;
}

/// The room a hello joins when it does not name one. The relay always lists it.
const everyoneRoom = 'Everyone';

class RoomInfo {
  const RoomInfo(this.name, this.people);

  final String name;
  final int people;
}

sealed class RelayEvent {
  const RelayEvent();
}

class WelcomeEvent extends RelayEvent {
  const WelcomeEvent(this.id, this.name, {this.room});

  final String id;
  final String name;
  final String? room;
}

class RoomsEvent extends RelayEvent {
  const RoomsEvent(this.rooms);

  final List<RoomInfo> rooms;
}

class RosterEvent extends RelayEvent {
  const RosterEvent(this.people, this.speakerId);

  final List<Person> people;
  final String? speakerId;
}

class FloorEvent extends RelayEvent {
  const FloorEvent(this.ok, this.by, {this.reason});

  final bool ok;
  final String? by;
  final String? reason;
}

class TalkEvent extends RelayEvent {
  const TalkEvent(this.id, this.name, this.down);

  final String id;
  final String name;
  final bool down;
}

class AudioEvent extends RelayEvent {
  const AudioEvent(this.pcm);

  final Uint8List pcm;
}

class PhotoEvent extends RelayEvent {
  const PhotoEvent(this.id, this.jpeg);

  final String id;

  /// Empty means the person cleared their picture.
  final Uint8List jpeg;
}

class ErrorEvent extends RelayEvent {
  const ErrorEvent(this.code);

  final String code;
}

class DisconnectedEvent extends RelayEvent {
  const DisconnectedEvent(this.error);

  final Object? error;
}

/// Trims, collapses whitespace, and keeps 1 to 24 characters.
String? cleanName(String raw) {
  final name = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
  final count = name.runes.length;
  if (count < 1 || count > 24) return null;
  if (name.runes.any((rune) => rune < 32)) return null;
  return name;
}

String newId() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

RelayEvent? eventFromMessage(Object message) {
  if (message is Uint8List) return AudioEvent(message);
  if (message is List<int>) return AudioEvent(Uint8List.fromList(message));
  if (message is String) return parseEvent(message);
  return null;
}

RelayEvent? parseEvent(String raw) {
  Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } catch (_) {
    return null;
  }
  if (decoded is! Map) return null;
  final type = decoded['t'];
  switch (type) {
    case 'welcome':
      final id = decoded['id'];
      final name = decoded['name'];
      if (id is String && name is String) {
        return WelcomeEvent(id, name, room: _string(decoded['room']));
      }
    case 'rooms':
      return RoomsEvent(_rooms(decoded['rooms']));
    case 'roster':
      return RosterEvent(
        _people(decoded['people']),
        _string(decoded['speaker']),
      );
    case 'floor':
      final ok = decoded['ok'];
      if (ok is bool) {
        return FloorEvent(
          ok,
          _string(decoded['by']),
          reason: _string(decoded['reason']),
        );
      }
    case 'talk':
      final id = decoded['id'];
      final name = decoded['name'];
      final down = decoded['down'];
      if (id is String && name is String && down is bool) {
        return TalkEvent(id, name, down);
      }
    case 'error':
      return ErrorEvent(_string(decoded['code']) ?? 'error');
    case 'photo':
      final id = decoded['id'];
      final jpeg = decoded['jpeg'];
      if (id is String && jpeg is String) {
        final bytes = _jpeg(jpeg);
        if (bytes != null) return PhotoEvent(id, bytes);
      }
  }
  return null;
}

/// Empty is a clear. Anything else must be a small JPEG.
Uint8List? _jpeg(String raw) {
  if (raw.isEmpty) return Uint8List(0);
  if (raw.length > 40000) return null;
  try {
    final bytes = base64Decode(raw);
    if (bytes.length < 4 || bytes.length > 24 * 1024) return null;
    if (bytes[0] != 0xff || bytes[1] != 0xd8) return null;
    return bytes;
  } catch (_) {
    return null;
  }
}

String? _string(Object? value) => value is String ? value : null;

List<RoomInfo> _rooms(Object? raw) {
  if (raw is! List) return const [];
  final rooms = <RoomInfo>[];
  for (final item in raw) {
    if (item is! Map) continue;
    final name = item['name'];
    final people = item['people'];
    if (name is String && people is int) rooms.add(RoomInfo(name, people));
  }
  return rooms;
}

List<Person> _people(Object? raw) {
  if (raw is! List) return const [];
  final people = <Person>[];
  for (final item in raw) {
    if (item is! Map) continue;
    final id = item['id'];
    final name = item['name'];
    if (id is String && name is String) people.add(Person(id, name));
  }
  return people;
}

String helloMessage(String id, String name, {String? room}) =>
    jsonEncode({'t': 'hello', 'id': id, 'name': name, 'room': ?room});

String pttMessage(bool down) => jsonEncode({'t': 'ptt', 'down': down});

String joinMessage(String room) => jsonEncode({'t': 'join', 'room': room});

String roomsMessage({bool watch = true}) =>
    jsonEncode({'t': 'rooms', if (!watch) 'watch': false});

/// [jpegBase64] is empty when the person removes their picture.
/// The relay stamps the sender id. Image bytes never use the PCM channel.
String photoMessage(String jpegBase64) =>
    jsonEncode({'t': 'photo', 'jpeg': jpegBase64});
