import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';

class PttButton extends StatefulWidget {
  const PttButton({
    super.key,
    required this.diameter,
    required this.enabled,
    required this.active,
    required this.self,
    required this.onDown,
    required this.onUp,
  });

  final double diameter;
  final bool enabled;
  final bool active;
  final bool self;
  final VoidCallback onDown;
  final VoidCallback onUp;

  @override
  State<PttButton> createState() => _PttButtonState();
}

class _PttButtonState extends State<PttButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _rings = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );

  @override
  void initState() {
    super.initState();
    if (widget.active) _rings.repeat();
  }

  @override
  void didUpdateWidget(PttButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.self && !oldWidget.self) {
      HapticFeedback.mediumImpact();
    }
    if (widget.active && !_rings.isAnimating) {
      _rings.repeat();
    } else if (!widget.active && _rings.isAnimating) {
      _rings
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _rings.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final outer = widget.diameter * 1.42;
    return SizedBox(
      width: outer,
      height: outer,
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedBuilder(
            animation: _rings,
            builder: (context, _) {
              return CustomPaint(
                size: Size.square(outer),
                painter: _RingPainter(
                  progress: _rings.value,
                  active: widget.active,
                ),
              );
            },
          ),
          Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: widget.enabled ? (_) => widget.onDown() : null,
            onPointerUp: (_) => widget.onUp(),
            onPointerCancel: (_) => widget.onUp(),
            child: Container(
              key: const Key('ptt'),
              width: widget.diameter,
              height: widget.diameter,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.self
                    ? const Color(0xFF14586A)
                    : ConnectColors.disc,
                border: Border.all(
                  color: widget.self || widget.active
                      ? ConnectColors.cyan
                      : ConnectColors.line,
                  width: widget.self ? 3 : 2,
                ),
                boxShadow: widget.self
                    ? const [
                        BoxShadow(
                          color: Color(0x733EE7F5),
                          blurRadius: 28,
                          spreadRadius: 2,
                        ),
                      ]
                    : null,
              ),
              child: const CustomPaint(painter: _RadioGlyphPainter()),
            ),
          ),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter({required this.progress, required this.active});

  final double progress;
  final bool active;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final inner = size.width * 0.34;
    final reach = size.width * 0.48;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round;
    if (!active) {
      paint.color = ConnectColors.cyan.withValues(alpha: 0.18);
      canvas.drawCircle(center, inner + 10, paint);
      canvas.drawCircle(center, inner + 26, paint);
      return;
    }
    for (var i = 0; i < 3; i++) {
      final t = (progress + i / 3) % 1.0;
      paint.color = ConnectColors.cyan.withValues(alpha: (1 - t) * 0.8);
      canvas.drawCircle(center, inner + 6 + t * (reach - inner), paint);
    }
  }

  @override
  bool shouldRepaint(_RingPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.active != active;
  }
}

class _RadioGlyphPainter extends CustomPainter {
  const _RadioGlyphPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final body = Paint()..color = const Color(0xFF1B3E66);
    final glow = Paint()..color = ConnectColors.cyan;
    final w = size.width;
    final h = size.height;
    final rect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(w / 2, h * 0.56),
        width: w * 0.34,
        height: h * 0.46,
      ),
      Radius.circular(w * 0.06),
    );
    canvas.drawRRect(rect, body);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(w / 2, h * 0.30),
          width: w * 0.07,
          height: h * 0.16,
        ),
        Radius.circular(8),
      ),
      body,
    );
    canvas.drawCircle(Offset(w / 2, h * 0.50), w * 0.055, glow);
    final speaker = Paint()..color = const Color(0xFF0E2438);
    for (var row = 0; row < 3; row++) {
      for (var col = 0; col < 3; col++) {
        canvas.drawCircle(
          Offset(w * (0.43 + col * 0.07), h * (0.60 + row * 0.055)),
          math.max(1.2, w * 0.012),
          speaker,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_RadioGlyphPainter oldDelegate) => false;
}
