import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../portrait.dart';
import '../protocol.dart';
import '../room_controller.dart';
import '../talk_settings.dart';
import '../theme.dart';
import '../voice_tone.dart';
import 'ptt_button.dart';
import 'speaker_stage.dart';

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
              _Header(live: live, roomName: room.roomName),
              const SizedBox(height: 14),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final rowHeight = math.min(
                      68.0,
                      constraints.maxHeight * 0.22,
                    );
                    final showFaces = rowHeight >= 40 && room.people.isNotEmpty;
                    return Column(
                      children: [
                        Expanded(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _MembersButton(room: room),
                                const SizedBox(height: 4),
                                SpeakerStage(room: room),
                              ],
                            ),
                          ),
                        ),
                        if (showFaces)
                          SizedBox(
                            height: rowHeight,
                            child: _FaceRow(room: room),
                          ),
                      ],
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
              _TalkControls(room: room),
              if (live && (!room.volumeKeysReady || !room.bubbleReady)) ...[
                const SizedBox(height: 4),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  children: [
                    if (!room.volumeKeysReady)
                      TextButton(
                        key: const Key('volume-keys'),
                        onPressed: room.openVolumeKeys,
                        style: TextButton.styleFrom(
                          foregroundColor: ConnectColors.cyan,
                          visualDensity: VisualDensity.compact,
                          textStyle: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        child: const Text('Volume keys'),
                      ),
                    if (!room.bubbleReady)
                      TextButton(
                        key: const Key('game-bubble'),
                        onPressed: room.openBubble,
                        style: TextButton.styleFrom(
                          foregroundColor: ConnectColors.cyan,
                          visualDensity: VisualDensity.compact,
                          textStyle: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        child: const Text('Bubble over games'),
                      ),
                  ],
                ),
              ],
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
              ? 'Press and hold the button. In a game, hold a volume key or the bubble.'
              : room.voiceMuted
              ? 'Tap the button to listen again. In a game, use a volume key or the bubble.'
              : 'Just speak. Tap the button to mute. In a game, use a volume key or the bubble.',
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

class _FaceRow extends StatelessWidget {
  const _FaceRow({required this.room});

  final RoomController room;

  @override
  Widget build(BuildContext context) {
    final people = room.people;
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 10.0;
        const slot = 56.0;
        final width = people.length * slot + (people.length - 1) * gap;
        final faces = <Widget>[
          for (var index = 0; index < people.length; index++)
            Semantics(
              label: people[index].name,
              child: _TalkingFace(
                room: room,
                person: people[index],
                diameter: 46,
              ),
            ),
        ];
        if (width <= constraints.maxWidth) {
          return Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var index = 0; index < faces.length; index++) ...[
                if (index > 0) const SizedBox(width: gap),
                faces[index],
              ],
            ],
          );
        }
        return ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          itemCount: faces.length,
          separatorBuilder: (_, _) => const SizedBox(width: gap),
          itemBuilder: (context, index) => Center(child: faces[index]),
        );
      },
    );
  }
}

class _TalkingFace extends StatelessWidget {
  const _TalkingFace({
    required this.room,
    required this.person,
    required this.diameter,
  });

  final RoomController room;
  final Person person;
  final double diameter;

  bool get _active =>
      person.id == room.speakerId ||
      (room.selfTalking && person.id == room.selfId);

  @override
  Widget build(BuildContext context) {
    final face = ProfileFace(
      id: person.id,
      diameter: diameter,
      photo: room.photoOf(person.id),
      onTap: person.id == room.selfId ? room.choosePhoto : null,
    );
    if (!_active) return _frame(face, false);
    return VoiceBrush(
      room: room,
      builder: (context, tone) {
        return Transform.scale(
          scaleX: speakerScaleX(tone),
          scaleY: speakerScaleY(tone),
          child: _frame(face, true),
        );
      },
    );
  }

  Widget _frame(Widget face, bool hot) {
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: hot ? ConnectColors.cyan : ConnectColors.line,
          width: hot ? 2 : 1,
        ),
      ),
      child: face,
    );
  }
}

class _MembersButton extends StatelessWidget {
  const _MembersButton({required this.room});

  final RoomController room;

  @override
  Widget build(BuildContext context) {
    final count = room.people.length;
    final label = count == 1 ? 'member' : 'members';
    return TextButton(
      key: const Key('members'),
      onPressed: () => _showMembers(context, room),
      style: TextButton.styleFrom(
        foregroundColor: ConnectColors.text,
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$count',
            key: const Key('member-count'),
            style: const TextStyle(
              fontSize: 56,
              height: 1,
              fontWeight: FontWeight.w700,
              color: ConnectColors.cyan,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: ConnectColors.muted,
            ),
          ),
        ],
      ),
    );
  }
}

void _showMembers(BuildContext context, RoomController room) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: ConnectColors.deep,
    showDragHandle: true,
    builder: (context) {
      return ListenableBuilder(
        listenable: room,
        builder: (context, _) {
          final people = room.people;
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Members',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 12),
                  if (people.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 12),
                      child: Text(
                        'Waiting for the room.',
                        style: TextStyle(color: ConnectColors.muted),
                      ),
                    )
                  else
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: MediaQuery.sizeOf(context).height * 0.5,
                      ),
                      child: SingleChildScrollView(
                        child: Column(
                          children: [
                            for (
                              var index = 0;
                              index < people.length;
                              index++
                            ) ...[
                              if (index > 0) const SizedBox(height: 8),
                              _personTile(room, people[index]),
                            ],
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}

class _Header extends StatelessWidget {
  const _Header({required this.live, required this.roomName});

  final bool live;
  final String roomName;

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
        _TalkingFace(room: room, person: person, diameter: 42),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                person.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (mine)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    key: const Key('pick-photo'),
                    onPressed: room.choosePhoto,
                    style: TextButton.styleFrom(
                      foregroundColor: ConnectColors.cyan,
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(0, 32),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(
                      room.photoOf(person.id) == null
                          ? 'Add a photo'
                          : 'Change photo',
                    ),
                  ),
                ),
              if (mine && room.photoOf(person.id) != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    key: const Key('clear-photo'),
                    onPressed: room.clearPhoto,
                    style: TextButton.styleFrom(
                      foregroundColor: ConnectColors.muted,
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(0, 32),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text('Remove photo'),
                  ),
                ),
              if (!mine) ...[
                const Text(
                  'Volume',
                  style: TextStyle(color: ConnectColors.muted, fontSize: 12),
                ),
                Slider(
                  key: Key('level-${person.id}'),
                  value: room.levelFor(person.id),
                  onChanged: (value) => room.previewLevel(person.id, value),
                  onChangeEnd: (value) {
                    room.setLevel(person.id, value);
                  },
                ),
              ],
            ],
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
