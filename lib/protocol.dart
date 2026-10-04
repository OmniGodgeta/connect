import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

class Person {
  const Person(this.id, this.name);

  final String id;
  final String name;
}

sealed class RelayEvent {
  const RelayEvent();
}

class WelcomeEvent extends RelayEvent {
  const WelcomeEvent(this.id, this.name);

  final String id;
  final String name;
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
      if (id is String && name is String) return WelcomeEvent(id, name);
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
  }
  return null;
}

String? _string(Object? value) => value is String ? value : null;

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

String helloMessage(String id, String name) =>
    jsonEncode({'t': 'hello', 'id': id, 'name': name});

String pttMessage(bool down) => jsonEncode({'t': 'ptt', 'down': down});
