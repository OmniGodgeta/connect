import 'dart:typed_data';

/// Microphone and speaker. Tests use a fake. The phone uses [DeviceAudio].
abstract class AudioEngine {
  Future<bool> ensureMic();

  /// [noiseCancel] turns on the platform noise suppressor, echo canceler,
  /// and automatic gain. Off captures the mic with those effects disabled.
  /// [alongside] keeps the phone in normal mode so a game in front keeps
  /// its own sound while this app listens.
  Future<void> startMic(
    void Function(Uint8List chunk) onChunk, {
    required bool noiseCancel,
    bool alongside = false,
  });

  Future<void> stopMic();

  Future<void> beginListen();

  void play(Uint8List pcm);

  Future<void> stopPlay();

  Future<void> dispose();
}
