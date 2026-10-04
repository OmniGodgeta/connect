import 'dart:math' as math;
import 'dart:typed_data';

import 'config.dart';

/// A short rising tone when someone arrives.
final Uint8List arriveChime = _chime(rising: true);

/// A short falling tone when someone leaves.
final Uint8List leaveChime = _chime(rising: false);

Uint8List _chime({required bool rising}) {
  const ms = 90;
  final count = ConnectConfig.sampleRate * ms ~/ 1000;
  final data = ByteData(count * 2);
  final start = rising ? 520.0 : 420.0;
  final end = rising ? 780.0 : 260.0;
  for (var i = 0; i < count; i++) {
    final t = i / count;
    final frequency = start + (end - start) * t;
    final envelope = math.sin(math.pi * t);
    final sample =
        math.sin(2 * math.pi * frequency * i / ConnectConfig.sampleRate) *
        envelope *
        9000;
    data.setInt16(i * 2, sample.round(), Endian.little);
  }
  return data.buffer.asUint8List();
}
