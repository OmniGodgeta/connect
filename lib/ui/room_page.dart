import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../protocol.dart';
import '../room_controller.dart';
import '../talk_settings.dart';
import '../theme.dart';
import 'ptt_button.dart';

class RoomPage extends StatelessWidget {
  const RoomPage({super.key, required this.room});

  final RoomController room;

  @override
  Widget build(BuildContext context) {
    final live = room.phase == RoomPhase.live;
    final someoneElse = room.speakerId != null && room.speakerId != room.selfId;
    return DecoratedBox(
      decoration: const BoxDecoration(gradient: connectBackground),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
          child: Column(
            children: [
              _Header(
                live: live,
                roomName: room.roomName,
                line: room.peopleLine,
              ),
              const SizedBox(height: 14),
              Expanded(child: _Roster(room: room)),
              const SizedBox(height: 8),
              _TalkControls(room: room),
              const SizedBox(height: 8),
              Text(
                room.statusLine,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: room.selfTalking || someoneElse
                      ? ConnectColors.cyan
                      : ConnectColors.muted,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              LayoutBuilder(
                builder: (context, constraints) {
                  final diameter = math.min(constraints.maxWidth * 0.5, 180.0);
                  final hold = room.mode == TalkMode.hold;
                  return PttButton(
                    diameter: diameter,
                    enabled: live,
                    active: room.selfTalking || someoneElse,
                    self: room.selfTalking,
                    onDown: () {
                      if (hold) {
                        room.hold();
                      } else {
                        room.toggleVoiceMute();
                      }
                    },
                    onUp: () {
                      if (hold) room.release();
                    },
                  );
                },
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  TextButton(
                    key: const Key('rooms'),
                    onPressed: live
                        ? () {
                            room.openRooms();
                          }
                        : null,
                    child: const Text('Rooms'),
                  ),
                  TextButton(
                    onPressed: () => _rename(context),
                    child: const Text('Change name'),
                  ),
                  TextButton(
                    onPressed: () {
                      room.leave();
                    },
                    child: const Text(
                      'Leave',
                      style: TextStyle(color: ConnectColors.warn),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _rename(BuildContext context) async {
    final current = room.name ?? '';
    final next = await showDialog<String>(
      context: context,
      builder: (context) => _RenameDialog(initial: current),
    );
    if (next == null) return;
    await room.setName(next);
  }
}

class LeftPage extends StatelessWidget {
  const LeftPage({super.key, required this.onJoin});

  final VoidCallback onJoin;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(gradient: connectBackground),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Spacer(),
              ClipRRect(
                borderRadius: BorderRadius.circular(28),
                child: Image.asset(
                  'assets/brand/icon.png',
                  width: 96,
                  height: 96,
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'You left the room',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              const Text(
                'You will not hear anyone until you join again.',
                textAlign: TextAlign.center,
                style: TextStyle(color: ConnectColors.muted, fontSize: 15),
              ),
              const SizedBox(height: 28),
              FilledButton(
                onPressed: onJoin,
                child: const Text('Join the room'),
              ),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}

class _TalkControls extends StatelessWidget {
  const _TalkControls({required this.room});

  final RoomController room;

  @override
  Widget build(BuildContext context) {
    final hold = room.mode == TalkMode.hold;
    return Column(
      children: [
        SegmentedButton<TalkMode>(
          key: const Key('talk-mode'),
          showSelectedIcon: false,
          style: ButtonStyle(
            visualDensity: VisualDensity.compact,
            backgroundColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) {
                return const Color(0xFF14586A);
              }
              return ConnectColors.tile;
            }),
            foregroundColor: WidgetStateProperty.all(ConnectColors.text),
            side: WidgetStateProperty.all(
              const BorderSide(color: ConnectColors.line),
            ),
          ),
          segments: const [
            ButtonSegment(value: TalkMode.hold, label: Text('Hold')),
            ButtonSegment(value: TalkMode.voice, label: Text('Voice')),
          ],
          selected: {room.mode},
          onSelectionChanged: (next) {
            room.setMode(next.first);
          },
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            const Expanded(
              child: Text(
                'Noise cancelling',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
            ),
            Switch(
              key: const Key('noise-cancel'),
              value: room.noiseCancel,
              onChanged: room.setNoiseCancel,
            ),
          ],
        ),
        Text(
          hold
              ? 'Press and hold the button. Noise cancelling cleans the mic.'
              : room.voiceMuted
              ? 'Tap the button to listen for your voice again.'
              : 'Just speak. Tap the button to mute.',
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: ConnectColors.muted,
            fontSize: 12,
            height: 1.3,
          ),
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.live,
    required this.roomName,
    required this.line,
  });

  final bool live;
  final String roomName;
  final String line;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'CONNECT',
                style: TextStyle(
                  fontSize: 13,
                  letterSpacing: 2.4,
                  fontWeight: FontWeight.w700,
                  color: ConnectColors.cyan,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                roomName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                line,
                style: const TextStyle(
                  color: ConnectColors.muted,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: live ? const Color(0x223EE7F5) : ConnectColors.tile,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: live ? ConnectColors.cyan : ConnectColors.line,
            ),
          ),
          child: Text(
            live ? 'LIVE' : 'LINKING',
            style: TextStyle(
              color: live ? ConnectColors.cyan : ConnectColors.muted,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.1,
            ),
          ),
        ),
      ],
    );
  }
}

class _Roster extends StatelessWidget {
  const _Roster({required this.room});

  final RoomController room;

  @override
  Widget build(BuildContext context) {
    if (room.people.isEmpty) {
      return const Center(
        child: Text(
          'Waiting for the room.',
          style: TextStyle(color: ConnectColors.muted),
        ),
      );
    }
    return SingleChildScrollView(
      child: Column(
        children: [
          for (var index = 0; index < room.people.length; index++) ...[
            if (index > 0) const SizedBox(height: 8),
            _personTile(room, room.people[index]),
          ],
        ],
      ),
    );
  }

  Widget _personTile(RoomController room, Person person) {
    final talking = person.id == room.speakerId;
    final mine = person.id == room.selfId;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: talking ? const Color(0xFF123844) : ConnectColors.tile,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: talking
              ? ConnectColors.cyan.withValues(alpha: 0.8)
              : ConnectColors.line,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: talking ? ConnectColors.cyan : ConnectColors.line,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              person.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
          ),
          if (mine)
            const Text(
              'you',
              style: TextStyle(color: ConnectColors.muted, fontSize: 13),
            ),
        ],
      ),
    );
  }
}

class RoomsPage extends StatefulWidget {
  const RoomsPage({super.key, required this.room});

  final RoomController room;

  @override
  State<RoomsPage> createState() => _RoomsPageState();
}

class _RoomsPageState extends State<RoomsPage> {
  final TextEditingController _name = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final room = widget.room;
    final rooms = room.availableRooms;
    return DecoratedBox(
      decoration: const BoxDecoration(gradient: connectBackground),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  TextButton(
                    key: const Key('rooms-back'),
                    onPressed: () {
                      room.closeRooms();
                    },
                    child: const Text('Back'),
                  ),
                  const Expanded(
                    child: Text(
                      'Rooms',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const Text(
                'Create a room and it shows up for friends on this network.',
                style: TextStyle(color: ConnectColors.muted, fontSize: 14),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      for (var index = 0; index < rooms.length; index++) ...[
                        if (index > 0) const SizedBox(height: 8),
                        _roomTile(room, rooms[index]),
                      ],
                    ],
                  ),
                ),
              ),
              if (room.banner != null) ...[
                const SizedBox(height: 8),
                Text(
                  room.banner!,
                  style: const TextStyle(
                    color: ConnectColors.warn,
                    fontSize: 14,
                  ),
                ),
              ],
              const SizedBox(height: 8),
              TextField(
                key: const Key('create-room-name'),
                controller: _name,
                textCapitalization: TextCapitalization.words,
                cursorColor: ConnectColors.cyan,
                decoration: const InputDecoration(
                  hintText: 'Room name',
                  filled: true,
                  fillColor: ConnectColors.tile,
                ),
                onSubmitted: (value) {
                  room.joinRoom(value);
                },
              ),
              const SizedBox(height: 8),
              FilledButton(
                key: const Key('create-room'),
                onPressed: () {
                  room.joinRoom(_name.text);
                },
                child: const Text('Create'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _roomTile(RoomController room, RoomInfo info) {
    final here = info.name == room.roomName;
    final count = info.people == 1 ? '1 person' : '${info.people} people';
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: Key('room-${info.name}'),
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          room.joinRoom(info.name);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: here ? const Color(0xFF123844) : ConnectColors.tile,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: here
                  ? ConnectColors.cyan.withValues(alpha: 0.8)
                  : ConnectColors.line,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      info.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      info.people == 0 ? 'Empty' : count,
                      style: const TextStyle(
                        color: ConnectColors.muted,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              if (here)
                const Text(
                  'here',
                  style: TextStyle(color: ConnectColors.cyan, fontSize: 13),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.initial});

  final String initial;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final TextEditingController _name = TextEditingController(
    text: widget.initial,
  );
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _save() {
    final cleaned = cleanName(_name.text);
    if (cleaned == null) {
      setState(() => _error = 'Use 1 to 24 characters.');
      return;
    }
    Navigator.of(context).pop(cleaned);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: ConnectColors.deep,
      title: const Text('Your name'),
      content: TextField(
        controller: _name,
        autofocus: true,
        textCapitalization: TextCapitalization.words,
        onSubmitted: (_) => _save(),
        cursorColor: ConnectColors.cyan,
        decoration: InputDecoration(
          errorText: _error,
          filled: true,
          fillColor: ConnectColors.tile,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}
