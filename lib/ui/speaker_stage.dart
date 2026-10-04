import 'package:flutter/material.dart';

import '../portrait.dart';
import '../protocol.dart';
import '../room_controller.dart';
import '../theme.dart';
import '../voice_tone.dart';

/// Repaints [builder] as the voice cone moves.
class VoiceBrush extends StatefulWidget {
  const VoiceBrush({super.key, required this.room, required this.builder});

  final RoomController room;
  final Widget Function(BuildContext context, VoiceTone tone) builder;

  @override
  State<VoiceBrush> createState() => _VoiceBrushState();
}

class _VoiceBrushState extends State<VoiceBrush> {
  @override
  void initState() {
    super.initState();
    widget.room.voice.addListener(_changed);
  }

  @override
  void didUpdateWidget(VoiceBrush oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.room != widget.room) {
      oldWidget.room.voice.removeListener(_changed);
      widget.room.voice.addListener(_changed);
    }
  }

  @override
  void dispose() {
    widget.room.voice.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return widget.builder(context, widget.room.voice.value);
  }
}

class SpeakerStage extends StatelessWidget {
  const SpeakerStage({super.key, required this.room});

  final RoomController room;

  static const double extent = 236;

  @override
  Widget build(BuildContext context) {
    return VoiceBrush(
      room: room,
      builder: (context, tone) {
        final person = _onStage(room);
        return SizedBox(
          width: extent,
          height: extent,
          child: person == null
              ? const SizedBox.shrink()
              : Column(
                  children: [
                    SizedBox(
                      width: 200,
                      height: 200,
                      child: CustomPaint(
                        painter: _SpeakerHalo(tone),
                        child: Center(
                          child: Transform.scale(
                            scaleX: speakerScaleX(tone),
                            scaleY: speakerScaleY(tone),
                            child: ProfileFace(id: person.id, diameter: 128),
                          ),
                        ),
                      ),
                    ),
                    Text(
                      person.name,
                      key: const Key('speaker-name'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: _live(room, person)
                            ? ConnectColors.cyan
                            : ConnectColors.text,
                      ),
                    ),
                  ],
                ),
        );
      },
    );
  }
}

class _SpeakerHalo extends CustomPainter {
  const _SpeakerHalo(this.tone);

  final VoiceTone tone;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final bass = tone.bass;
    final air = tone.air;
    for (var ring = 0; ring < 3; ring++) {
      final radius = 70 + ring * 10 + bass * 12 + (ring == 1 ? air * 4 : 0);
      final alpha = (0.08 + bass * 0.42 + air * 0.12 - ring * 0.08).clamp(
        0.04,
        0.7,
      );
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = (4.2 - ring * 0.8) + bass * 1.4
          ..color = ConnectColors.cyan.withValues(alpha: alpha),
      );
    }
  }

  @override
  bool shouldRepaint(_SpeakerHalo oldDelegate) => oldDelegate.tone != tone;
}

Person? _onStage(RoomController room) {
  if (room.selfTalking && room.selfId != null && room.name != null) {
    return Person(room.selfId!, room.name!);
  }
  final speakerId = room.speakerId;
  if (speakerId != null) {
    for (final person in room.people) {
      if (person.id == speakerId) return person;
    }
    final speakerName = room.speakerName;
    if (speakerName != null) return Person(speakerId, speakerName);
  }
  if (room.selfId != null && room.name != null) {
    return Person(room.selfId!, room.name!);
  }
  return null;
}

bool _live(RoomController room, Person person) {
  if (room.selfTalking && person.id == room.selfId) return true;
  return room.speakerId == person.id && room.speakerId != null;
}
