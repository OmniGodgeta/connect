import 'dart:typed_data';

/// Microphone and speaker. Tests use a fake. The phone uses [DeviceAudio].
abstract class AudioEngine {
  Future<bool> ensureMic();

  /// [noiseCancel] turns on the platform noise suppressor, echo canceler,
  /// and automatic gain. Off captures the mic with those effects disabled.
  Future<void> startMic(
    void Function(Uint8List chunk) onChunk, {
    required bool noiseCancel,
  });

  Future<void> stopMic();

  Future<void> beginListen();

  void play(Uint8List pcm);

  Future<void> stopPlay();

  Future<void> dispose();
}
