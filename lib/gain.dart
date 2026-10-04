import 'dart:typed_data';

/// Scales signed-16 little-endian mono samples. A gain of 1 returns [pcm].
/// A gain of 0 returns an empty list so the caller can skip playback.
Uint8List applyGain(Uint8List pcm, double gain) {
  if (pcm.length < 2) return pcm;
  if (gain >= 0.999) return pcm;
  if (gain <= 0.001) return Uint8List(0);
  final length = pcm.length - (pcm.length.isOdd ? 1 : 0);
  final out = Uint8List(length);
  final input = ByteData.sublistView(pcm);
  final output = ByteData.sublistView(out);
  for (var i = 0; i < length; i += 2) {
    final sample = input.getInt16(i, Endian.little);
    var scaled = (sample * gain).round();
    if (scaled > 32767) scaled = 32767;
    if (scaled < -32768) scaled = -32768;
    output.setInt16(i, scaled, Endian.little);
  }
  return out;
}
