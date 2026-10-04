import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../protocol.dart';
import '../room_controller.dart';
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
              _Header(live: live, line: room.peopleLine),
              const SizedBox(height: 14),
              Expanded(child: _Roster(room: room)),
              const SizedBox(height: 8),
              Text(
                room.statusLine,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: room.selfTalking || someoneElse ? ConnectColors.cyan : ConnectColors.muted,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              LayoutBuilder(
                builder: (context, constraints) {
                  final diameter = math.min(constraints.maxWidth * 0.58, 210.0);
                  return PttButton(
                    diameter: diameter,
                    enabled: live,
                    active: room.selfTalking || someoneElse,
                    self: room.selfTalking,
                    onDown: () {
                      room.hold();
                    },
                    onUp: () {
                      room.release();
                    },
                  );
                },
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  TextButton(
                    onPressed: () => _rename(context),
                    child: const Text('Change name'),
                  ),
                  TextButton(
                    onPressed: () {
                      room.leave();
                    },
                    child: const Text('Leave', style: TextStyle(color: ConnectColors.warn)),
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
                child: Image.asset('assets/brand/icon.png', width: 96, height: 96),
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
              FilledButton(onPressed: onJoin, child: const Text('Join the room')),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.live, required this.line});

  final bool live;
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
              Text(line, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: live ? const Color(0x223EE7F5) : ConnectColors.tile,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: live ? ConnectColors.cyan : ConnectColors.line),
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
    return ListView.separated(
      itemCount: room.people.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final person = room.people[index];
        final talking = person.id == room.speakerId;
        final mine = person.id == room.selfId;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: talking ? const Color(0xFF123844) : ConnectColors.tile,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: talking ? ConnectColors.cyan.withValues(alpha: 0.8) : ConnectColors.line,
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
                const Text('you', style: TextStyle(color: ConnectColors.muted, fontSize: 13)),
            ],
          ),
        );
      },
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
  late final TextEditingController _name = TextEditingController(text: widget.initial);
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
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        TextButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}
