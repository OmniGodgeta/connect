import 'dart:math' as math;
import 'dart:typed_data';

import 'package:connect/portrait.dart';
import 'package:connect/voice_tone.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the same person always gets the same picture', () {
    expect(PortraitData.of('eric0001'), PortraitData.of('eric0001'));
    expect(
      PortraitData.of('eric0001').seed,
      isNot(PortraitData.of('alex0001').seed),
    );
  });

  test('bass grows the picture and a bright tone pulls it in', () {
    const bass = VoiceTone(bass: 1);
    const air = VoiceTone(air: 1);
    expect(speakerScaleY(bass), greaterThan(1));
    expect(speakerScaleY(air), lessThan(1));
    expect(speakerScaleX(bass), lessThan(speakerScaleY(bass)));
    expect(speakerScaleY(VoiceTone.silent), 1);
  });

  test('a low tone drives the cone more than a high tone', () {
    final low = VoiceToneMeter()..push(_sine(110, 14000));
    final high = VoiceToneMeter()..push(_sine(3600, 14000));
    expect(low.tone.bass, greaterThan(high.tone.bass));
    expect(high.tone.air, greaterThan(low.tone.air));
    expect(VoiceToneMeter().push(Uint8List(8)).quiet, isTrue);
  });
}

Uint8List _sine(double hz, double amplitude) {
  const rate = 48000;
  const samples = 4800;
  final bytes = ByteData(samples * 2);
  for (var i = 0; i < samples; i++) {
    final sample = (math.sin(2 * math.pi * hz * i / rate) * amplitude).round();
    bytes.setInt16(i * 2, sample.clamp(-32767, 32767), Endian.little);
  }
  return bytes.buffer.asUint8List();
}
