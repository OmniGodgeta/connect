import 'dart:convert';
import 'dart:typed_data';

import 'package:connect/protocol.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('cleanName trims and rejects blanks', () {
    expect(cleanName('  Ada  Lovelace '), 'Ada Lovelace');
    expect(cleanName('   '), isNull);
    expect(cleanName('a' * 24), 'a' * 24);
    expect(cleanName('a' * 25), isNull);
  });

  test('parseEvent reads the relay messages', () {
    final welcome = parseEvent('{"t":"welcome","id":"abc12345","name":"Ada"}');
    expect(welcome, isA<WelcomeEvent>());
    expect((welcome! as WelcomeEvent).name, 'Ada');
    expect((welcome as WelcomeEvent).room, isNull);

    final placed = parseEvent(
      '{"t":"welcome","id":"abc12345","name":"Ada","room":"Cabin"}',
    );
    expect((placed! as WelcomeEvent).room, 'Cabin');

    final rooms = parseEvent(
      '{"t":"rooms","rooms":[{"name":"Everyone","people":1},{"name":"Cabin","people":2}]}',
    );
    expect(rooms, isA<RoomsEvent>());
    expect((rooms! as RoomsEvent).rooms.last.people, 2);

    final roster = parseEvent(
      '{"t":"roster","people":[{"id":"abc12345","name":"Ada"}],"speaker":null}',
    );
    expect(roster, isA<RosterEvent>());
    expect((roster! as RosterEvent).people.single.name, 'Ada');
    expect((roster as RosterEvent).speakerId, isNull);

    final denied = parseEvent('{"t":"floor","ok":false,"by":"Bea"}');
    expect(denied, isA<FloorEvent>());
    expect((denied! as FloorEvent).ok, isFalse);
    expect((denied as FloorEvent).by, 'Bea');

    expect(parseEvent('not json'), isNull);
    expect(parseEvent('{"t":"nope"}'), isNull);

    final cleared = parseEvent('{"t":"photo","id":"abc12345","jpeg":""}');
    expect(cleared, isA<PhotoEvent>());
    expect((cleared! as PhotoEvent).jpeg, isEmpty);

    final jpeg = base64Encode(Uint8List.fromList([0xff, 0xd8, 0x00, 0xd9]));
    final photo = parseEvent('{"t":"photo","id":"abc12345","jpeg":"$jpeg"}');
    expect((photo! as PhotoEvent).jpeg, [0xff, 0xd8, 0x00, 0xd9]);
    expect(parseEvent('{"t":"photo","id":"abc12345","jpeg":"!!!!"}'), isNull);

    final say = parseEvent(
      '{"t":"say","id":"spoofed","name":"Ada","text":"  hello   there  "}',
    );
    expect(say, isA<SayEvent>());
    expect((say! as SayEvent).text, 'hello there');
    expect((say as SayEvent).id, 'spoofed');

    final log = parseEvent(
      '{"t":"chatlog","lines":[{"id":"abc12345","name":"Ada","text":"hello there"},{"id":"x","name":"","text":"no"}]}',
    );
    expect(log, isA<ChatLogEvent>());
    expect((log! as ChatLogEvent).lines.single.text, 'hello there');
    expect(
      parseEvent('{"t":"say","id":"abc12345","name":"Ada","text":""}'),
      isNull,
    );
  });

  test('cleanChat trims and rejects blanks, controls, and long lines', () {
    expect(cleanChat('  hello   there '), 'hello there');
    expect(cleanChat('   '), isNull);
    expect(cleanChat('bad\nline'), 'bad line');
    expect(cleanChat('bad\u0000line'), isNull);
    expect(cleanChat('a' * 240), 'a' * 240);
    expect(cleanChat('a' * 241), isNull);
    expect(sayMessage('hello'), '{"t":"say","text":"hello"}');
  });
}
