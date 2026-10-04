import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

/// A painted face that is the same on every phone for the same person.
class PortraitData {
  const PortraitData({
    required this.seed,
    required this.backdrop,
    required this.skin,
    required this.hair,
    required this.cloth,
    required this.hairStyle,
    required this.eyeStyle,
    required this.glasses,
  });

  factory PortraitData.of(String id) {
    final seed = _hash(id);
    return PortraitData(
      seed: seed,
      backdrop: _backdrops[_pick(seed, 0, _backdrops.length)],
      skin: _skins[_pick(seed, 3, _skins.length)],
      hair: _hairs[_pick(seed, 7, _hairs.length)],
      cloth: _cloths[_pick(seed, 11, _cloths.length)],
      hairStyle: _pick(seed, 15, 6),
      eyeStyle: _pick(seed, 18, 3),
      glasses: _pick(seed, 21, 5) == 0,
    );
  }

  final int seed;
  final Color backdrop;
  final Color skin;
  final Color hair;
  final Color cloth;
  final int hairStyle;
  final int eyeStyle;
  final bool glasses;

  @override
  bool operator ==(Object other) =>
      other is PortraitData &&
      other.seed == seed &&
      other.backdrop == backdrop &&
      other.skin == skin &&
      other.hair == hair &&
      other.cloth == cloth &&
      other.hairStyle == hairStyle &&
      other.eyeStyle == eyeStyle &&
      other.glasses == glasses;

  @override
  int get hashCode => Object.hash(
    seed,
    backdrop,
    skin,
    hair,
    cloth,
    hairStyle,
    eyeStyle,
    glasses,
  );
}

class ProfileFace extends StatelessWidget {
  const ProfileFace({
    super.key,
    required this.id,
    required this.diameter,
    this.photo,
    this.onTap,
  });

  final String id;
  final double diameter;
  final Uint8List? photo;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final face = photo == null ? _painted() : _photo(photo!);
    if (onTap == null) return face;
    return GestureDetector(onTap: onTap, child: face);
  }

  Widget _painted() {
    return SizedBox(
      width: diameter,
      height: diameter,
      child: ClipOval(
        child: CustomPaint(
          painter: _PortraitPainter(PortraitData.of(id)),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }

  Widget _photo(Uint8List bytes) {
    return SizedBox(
      width: diameter,
      height: diameter,
      child: ClipOval(
        child: Image.memory(
          bytes,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (_, _, _) => _painted(),
        ),
      ),
    );
  }
}

class _PortraitPainter extends CustomPainter {
  const _PortraitPainter(this.data);

  final PortraitData data;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 100;
    canvas.scale(scale);
    canvas.drawCircle(const Offset(50, 50), 50, Paint()..color = data.backdrop);
    canvas.drawCircle(
      const Offset(50, 18),
      40,
      Paint()..color = Colors.white.withValues(alpha: 0.08),
    );
    canvas.drawOval(
      const Rect.fromLTWH(6, 74, 88, 42),
      Paint()..color = data.cloth,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(43, 64, 14, 16),
        const Radius.circular(4),
      ),
      Paint()..color = data.skin,
    );
    canvas.drawCircle(const Offset(50, 46), 26, Paint()..color = data.skin);
    _hair(canvas);
    _eyes(canvas);
    canvas.drawArc(
      Rect.fromCenter(center: const Offset(50, 56), width: 14, height: 9),
      0.15,
      math.pi - 0.3,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.7
        ..strokeCap = StrokeCap.round
        ..color = const Color(0xFF2A211C).withValues(alpha: 0.8),
    );
    if (data.glasses) _glasses(canvas);
  }

  void _hair(Canvas canvas) {
    final paint = Paint()..color = data.hair;
    final head = Rect.fromCircle(center: const Offset(50, 44), radius: 27);
    switch (data.hairStyle) {
      case 0:
        canvas.drawArc(head, math.pi * 1.02, math.pi * 0.96, true, paint);
      case 1:
        canvas.drawArc(head, math.pi, math.pi, true, paint);
        canvas.drawOval(const Rect.fromLTWH(20, 34, 22, 18), paint);
      case 2:
        canvas.drawArc(head, math.pi * 0.95, math.pi * 1.1, true, paint);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(22, 40, 10, 34),
            const Radius.circular(6),
          ),
          paint,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(68, 40, 10, 34),
            const Radius.circular(6),
          ),
          paint,
        );
      case 3:
        canvas.drawArc(head, math.pi, math.pi, true, paint);
        final spikes = Path();
        for (var i = 0; i < 5; i++) {
          final x = 26.0 + i * 10;
          spikes
            ..moveTo(x, 36)
            ..lineTo(x + 5, 16)
            ..lineTo(x + 10, 36);
        }
        canvas.drawPath(spikes, paint);
      case 4:
        canvas.drawArc(head, math.pi, math.pi, true, paint);
        canvas.drawCircle(const Offset(68, 24), 9, paint);
      default:
        canvas.drawArc(
          Rect.fromCircle(center: const Offset(50, 48), radius: 24),
          math.pi * 1.08,
          math.pi * 0.84,
          true,
          paint,
        );
    }
  }

  void _eyes(Canvas canvas) {
    final ink = Paint()..color = const Color(0xFF241C18);
    if (data.eyeStyle == 2) {
      final lid = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..strokeCap = StrokeCap.round
        ..color = const Color(0xFF241C18);
      canvas.drawArc(
        Rect.fromCenter(center: const Offset(40, 46), width: 10, height: 6),
        0,
        math.pi,
        false,
        lid,
      );
      canvas.drawArc(
        Rect.fromCenter(center: const Offset(60, 46), width: 10, height: 6),
        0,
        math.pi,
        false,
        lid,
      );
      return;
    }
    final radius = data.eyeStyle == 1 ? 3.3 : 2.3;
    canvas.drawCircle(const Offset(40, 46), radius, ink);
    canvas.drawCircle(const Offset(60, 46), radius, ink);
    final light = Paint()..color = Colors.white.withValues(alpha: 0.9);
    canvas.drawCircle(Offset(40 + radius * 0.3, 45), 0.9, light);
    canvas.drawCircle(Offset(60 + radius * 0.3, 45), 0.9, light);
  }

  void _glasses(Canvas canvas) {
    final frame = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..color = const Color(0xFF102028).withValues(alpha: 0.85);
    canvas.drawCircle(const Offset(40, 46), 6.5, frame);
    canvas.drawCircle(const Offset(60, 46), 6.5, frame);
    canvas.drawLine(const Offset(46.5, 46), const Offset(53.5, 46), frame);
  }

  @override
  bool shouldRepaint(_PortraitPainter oldDelegate) => oldDelegate.data != data;
}

int _hash(String id) {
  var hash = 0x811c9dc5;
  for (final unit in id.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0x7fffffff;
  }
  return hash;
}

int _pick(int seed, int shift, int count) => (seed >> shift) % count;

const _backdrops = <Color>[
  Color(0xFF14586A),
  Color(0xFF1D4E89),
  Color(0xFF3D5A3A),
  Color(0xFF6A3E5C),
  Color(0xFF8A4B2F),
  Color(0xFF2F5D50),
  Color(0xFF3E4C8A),
  Color(0xFF6B3A3A),
];

const _skins = <Color>[
  Color(0xFFF6D3B8),
  Color(0xFFF0C09A),
  Color(0xFFE0A87A),
  Color(0xFFC68642),
  Color(0xFF8D5524),
  Color(0xFF5C3317),
];

const _hairs = <Color>[
  Color(0xFF1C1410),
  Color(0xFF4A3428),
  Color(0xFF8A5A32),
  Color(0xFFD7B15A),
  Color(0xFF8C2F2F),
  Color(0xFF2C2A33),
  Color(0xFFE8E2D6),
];

const _cloths = <Color>[
  Color(0xFF123844),
  Color(0xFF1E3F6B),
  Color(0xFF3EE7F5),
  Color(0xFFC45C26),
  Color(0xFF2E6B4F),
  Color(0xFF6E4A86),
];
