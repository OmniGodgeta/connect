import 'package:connect/main.dart';
import 'package:connect/name_store.dart';
import 'package:connect/protocol.dart';
import 'package:connect/room_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'room_controller_test.dart';

void main() {
  testWidgets('asks for a name, then shows the room', (tester) async {
    final relay = FakeRelay();
    final room = RoomController(
      relay: relay,
      audio: FakeAudio(),
      names: MemoryNameStore(),
      alerts: FakeAlerts(),
      schedule: (_, _) => () {},
    );
    await tester.pumpWidget(ConnectApp(controller: room));
    await tester.pumpAndSettle();

    expect(find.text('Join the room'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('name-field')), '   ');
    await tester.tap(find.byKey(const Key('join')));
    await tester.pump();
    expect(find.text('Use 1 to 24 characters.'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('name-field')), 'Eric');
    await tester.tap(find.byKey(const Key('join')));
    await tester.pumpAndSettle();
    expect(room.phase, RoomPhase.connecting);

    relay.emit(WelcomeEvent(room.selfId!, 'Eric'));
    relay.emit(
      RosterEvent([
        Person(room.selfId!, 'Eric'),
        const Person('alex0001', 'Alex'),
      ], null),
    );
    await tester.pump();

    expect(find.text('Eric'), findsOneWidget);
    expect(find.text('Alex'), findsOneWidget);
    expect(find.text('2 people in the room'), findsOneWidget);
    expect(find.text('LIVE'), findsOneWidget);
    expect(find.byKey(const Key('ptt')), findsOneWidget);
  });
}
