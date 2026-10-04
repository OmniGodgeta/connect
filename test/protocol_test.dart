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
  });
}
