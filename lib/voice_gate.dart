import 'dart:math' as math;
import 'dart:typed_data';

import 'config.dart';

/// Decides when a microphone stream is speech.
///
/// The noise floor creeps toward quiet audio. Speech has to clear that floor
/// and last [openFor] before the gate opens, then it stays open through short
/// pauses ([hangFor]) so a breath does not drop the floor.
class VoiceGate {
  VoiceGate({
    this.sampleRate = ConnectConfig.sampleRate,
    this.openFor = const Duration(milliseconds: 80),
    this.hangFor = const Duration(milliseconds: 600),
    this.preRoll = const Duration(milliseconds: 220),
    this.absoluteFloor = 700,
  });

  final int sampleRate;
  final Duration openFor;
  final Duration hangFor;
  final Duration preRoll;

  /// RMS below this never counts as speech, even in a silent room.
  final double absoluteFloor;

  bool open = false;
  double noise = 280;

  int _speechSamples = 0;
  int _quietSamples = 0;
  int _preBytes = 0;
  final List<Uint8List> _pre = <Uint8List>[];

  int get _openSamples => _samples(openFor);
  int get _hangSamples => _samples(hangFor);
  int get _preCap => sampleRate * 2 * preRoll.inMilliseconds ~/ 1000;

  void reset() {
    open = false;
    _speechSamples = 0;
    _quietSamples = 0;
    _preBytes = 0;
    _pre.clear();
  }

  VoiceDecision push(Uint8List pcm) {
    final samples = pcm.length ~/ 2;
    if (samples == 0) {
      return const VoiceDecision(
        open: false,
        justOpened: false,
        justClosed: false,
      );
    }
    final level = rmsOf(pcm);
    final speech = level >= math.max(absoluteFloor, noise * 3.2);

    if (!open) {
      _remember(pcm);
      if (!speech) {
        _speechSamples = 0;
        noise = math.max(40, noise * 0.9 + level * 0.1);
        return const VoiceDecision(
          open: false,
          justOpened: false,
          justClosed: false,
        );
      }
      _speechSamples += samples;
      if (_speechSamples < _openSamples) {
        return const VoiceDecision(
          open: false,
          justOpened: false,
          justClosed: false,
        );
      }
      open = true;
      _quietSamples = 0;
      final burst = List<Uint8List>.from(_pre);
      _pre.clear();
      _preBytes = 0;
      return VoiceDecision(
        open: true,
        justOpened: true,
        justClosed: false,
        burst: burst,
      );
    }

    if (speech) {
      _quietSamples = 0;
      return const VoiceDecision(
        open: true,
        justOpened: false,
        justClosed: false,
      );
    }
    _quietSamples += samples;
    if (_quietSamples < _hangSamples) {
      return const VoiceDecision(
        open: true,
        justOpened: false,
        justClosed: false,
      );
    }
    open = false;
    _speechSamples = 0;
    _quietSamples = 0;
    _remember(pcm);
    return const VoiceDecision(
      open: false,
      justOpened: false,
      justClosed: true,
    );
  }

  void _remember(Uint8List pcm) {
    _pre.add(Uint8List.fromList(pcm));
    _preBytes += pcm.length;
    while (_pre.length > 1 && _preBytes - _pre.first.length >= _preCap) {
      _preBytes -= _pre.removeAt(0).length;
    }
  }

  int _samples(Duration duration) =>
      sampleRate * duration.inMilliseconds ~/ 1000;
}

class VoiceDecision {
  const VoiceDecision({
    required this.open,
    required this.justOpened,
    required this.justClosed,
    this.burst = const [],
  });

  final bool open;
  final bool justOpened;
  final bool justClosed;
  final List<Uint8List> burst;
}

double rmsOf(Uint8List pcm) {
  final data = ByteData.sublistView(pcm);
  final count = pcm.length ~/ 2;
  if (count == 0) return 0;
  var sum = 0.0;
  for (var i = 0; i < count; i++) {
    final sample = data.getInt16(i * 2, Endian.little);
    sum += sample * sample;
  }
  return math.sqrt(sum / count);
}

/// Splits PCM into even-sized frames the relay will forward.
List<Uint8List> pcmFrames(
  Uint8List pcm, [
  int frameBytes = ConnectConfig.frameBytes,
]) {
  final size = frameBytes & ~1;
  final end = pcm.length & ~1;
  if (size <= 0 || end < 2) return const [];
  final frames = <Uint8List>[];
  for (var i = 0; i < end; i += size) {
    final stop = math.min(i + size, end);
    frames.add(Uint8List.sublistView(pcm, i, stop));
  }
  return frames;
}
