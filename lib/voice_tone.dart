import 'dart:math' as math;
import 'dart:typed_data';

/// How a voice is pushing a speaker cone.
///
/// [bass] is the low part of the sound. [air] is everything above it.
/// Both sit between 0 and 1.
class VoiceTone {
  const VoiceTone({this.bass = 0, this.air = 0});

  static const silent = VoiceTone();

  final double bass;
  final double air;

  bool get quiet => bass < 0.02 && air < 0.02;

  @override
  bool operator ==(Object other) =>
      other is VoiceTone && other.bass == bass && other.air == air;

  @override
  int get hashCode => Object.hash(bass, air);
}

/// Width of the picture. Bass pushes it out. A brighter tone pulls it in.
double speakerScaleX(VoiceTone tone) =>
    (1 + tone.bass * 0.10 - tone.air * 0.04).clamp(0.94, 1.14);

/// Height of the picture. The cone travels a little more this way.
double speakerScaleY(VoiceTone tone) =>
    (1 + tone.bass * 0.16 - tone.air * 0.07).clamp(0.92, 1.18);

/// Follows PCM and keeps a short speaker envelope.
class VoiceToneMeter {
  double _low = 0;
  double _bass = 0;
  double _air = 0;

  VoiceTone get tone => VoiceTone(bass: _bass, air: _air);

  void reset() {
    _low = 0;
    _bass = 0;
    _air = 0;
  }

  VoiceTone push(Uint8List pcm) {
    final data = ByteData.sublistView(pcm);
    final count = pcm.length ~/ 2;
    if (count == 0) return tone;
    var lowEnergy = 0.0;
    var highEnergy = 0.0;
    for (var i = 0; i < count; i++) {
      final sample = data.getInt16(i * 2, Endian.little).toDouble();
      // About 180 Hz at 48 kHz. What passes is the bass.
      _low += 0.025 * (sample - _low);
      final high = sample - _low;
      lowEnergy += _low * _low;
      highEnergy += high * high;
    }
    _bass = _follow(_bass, _norm(math.sqrt(lowEnergy / count)));
    _air = _follow(_air, _norm(math.sqrt(highEnergy / count)));
    return tone;
  }

  VoiceTone release() {
    _bass = _snap(_bass * 0.78);
    _air = _snap(_air * 0.78);
    return tone;
  }

  double _follow(double env, double target) {
    final rate = target > env ? 0.72 : 0.4;
    return _snap(env + (target - env) * rate);
  }

  double _norm(double rms) {
    final raised = ((rms - 350) / 5200).clamp(0.0, 1.0);
    return math.sqrt(raised);
  }

  double _snap(double value) {
    final stepped = (value * 100).round() / 100;
    return stepped < 0.02 ? 0 : stepped;
  }
}
