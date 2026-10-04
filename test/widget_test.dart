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

    expect(find.text('2'), findsOneWidget);
    expect(find.text('members'), findsOneWidget);
    expect(find.text('Eric'), findsOneWidget);
    expect(find.text('Alex'), findsNothing);
    expect(find.text('LIVE'), findsOneWidget);

    await tester.tap(find.byKey(const Key('members')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Members'), findsOneWidget);
    expect(find.text('Eric'), findsNWidgets(2));
    expect(find.text('Alex'), findsOneWidget);
    expect(find.text('Add a photo'), findsOneWidget);
    expect(find.text('Volume'), findsOneWidget);
    expect(find.byType(Slider), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Alex'), findsNothing);
    expect(find.text('LIVE'), findsOneWidget);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    // A paused app stops normal frames. Force one so the status line rebuilds.
    tester.binding.scheduleForcedFrame();
    await tester.pump();
    expect(room.statusLine, 'Hold a volume key to talk');
    expect(find.text('Hold a volume key to talk'), findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(room.statusLine, 'Hold to talk');
    expect(find.text('Hold to talk'), findsOneWidget);
    expect(find.text('Noise cancelling'), findsOneWidget);
    expect(find.text('Hold'), findsOneWidget);
    expect(find.byKey(const Key('ptt')), findsOneWidget);

    await tester.tap(find.text('Voice'));
    await tester.pump();
    expect(find.text('Listening for your voice'), findsOneWidget);
    expect(find.text('Everyone'), findsOneWidget);

    await tester.tap(find.byKey(const Key('rooms')));
    await tester.pump();
    expect(find.text('Create'), findsOneWidget);
    expect(find.text('here'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('create-room-name')), 'Cabin');
    await tester.tap(find.byKey(const Key('create-room')));
    await tester.pump();
    expect(relay.log, contains('join:Cabin'));

    relay.emit(WelcomeEvent(room.selfId!, 'Eric', room: 'Cabin'));
    relay.emit(RosterEvent([Person(room.selfId!, 'Eric')], null));
    await tester.pump();
    expect(find.text('Cabin'), findsOneWidget);
    expect(find.text('Create'), findsNothing);
  });
}
