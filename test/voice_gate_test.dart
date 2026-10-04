import 'dart:typed_data';

import 'package:connect/voice_gate.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List tone(int samples, int amplitude) {
  final data = ByteData(samples * 2);
  for (var i = 0; i < samples; i++) {
    data.setInt16(i * 2, amplitude, Endian.little);
  }
  return data.buffer.asUint8List();
}

void main() {
  test('silence never opens the gate', () {
    final gate = VoiceGate(sampleRate: 16000);
    final quiet = tone(16000, 0);
    final decision = gate.push(quiet);
    expect(decision.justOpened, isFalse);
    expect(gate.open, isFalse);
  });

  test('a short blip does not open, and sustained speech does', () {
    final gate = VoiceGate(sampleRate: 16000);
    final blip = tone(800, 8000);
    expect(gate.push(blip).justOpened, isFalse);

    final decision = gate.push(tone(1600, 8000));
    expect(decision.justOpened, isTrue);
    expect(decision.burst, isNotEmpty);
    expect(gate.open, isTrue);
  });

  test('the gate stays open through a short pause, then closes', () {
    final gate = VoiceGate(sampleRate: 16000);
    expect(gate.push(tone(2000, 9000)).justOpened, isTrue);

    final pause = gate.push(tone(4000, 0));
    expect(pause.justClosed, isFalse);
    expect(gate.open, isTrue);

    final done = gate.push(tone(8000, 0));
    expect(done.justClosed, isTrue);
    expect(gate.open, isFalse);
  });

  test('frames stay inside the relay size', () {
    final pcm = tone(48000, 1);
    final frames = pcmFrames(pcm, 3840);
    expect(frames, isNotEmpty);
    expect(
      frames.every((frame) => frame.length <= 3840 && frame.length.isEven),
      isTrue,
    );
    expect(frames.fold<int>(0, (sum, frame) => sum + frame.length), pcm.length);
  });
}
