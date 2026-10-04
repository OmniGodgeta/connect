import 'dart:typed_data';

/// Microphone and speaker. Tests use a fake. The phone uses [DeviceAudio].
abstract class AudioEngine {
  Future<bool> ensureMic();

  Future<void> startMic(void Function(Uint8List chunk) onChunk);

  Future<void> stopMic();

  Future<void> beginListen();

  void play(Uint8List pcm);

  Future<void> stopPlay();

  Future<void> dispose();
}
