import 'dart:typed_data';

/// Queues speaker PCM and asks [onReady] whenever a chunk can be written.
///
/// The playback plugin asks for samples once when listening starts. If that
/// ask finds an empty queue, later audio never plays unless [play] asks again
/// while listening is already on.
class SpeakerFeed {
  SpeakerFeed({required this.sampleRate, this.onReady});

  final int sampleRate;
  void Function()? onReady;
  final List<int> _samples = <int>[];
  bool listening = false;

  void play(Uint8List pcm) {
    if (pcm.length < 2) return;
    _enqueue(pcm);
    if (listening) onReady?.call();
  }

  /// Listening just started. Samples that arrived during setup are fed now.
  void start() {
    listening = true;
    onReady?.call();
  }

  void stop() {
    _samples.clear();
    listening = false;
  }

  /// The next chunk to write, or null when there is nothing to play.
  List<int>? takeChunk() {
    if (!listening || _samples.isEmpty) return null;
    final budget = sampleRate ~/ 10;
    final count = _samples.length < budget ? _samples.length : budget;
    final chunk = List<int>.of(_samples.sublist(0, count));
    _samples.removeRange(0, count);
    return chunk;
  }

  void _enqueue(Uint8List pcm) {
    final data = ByteData.sublistView(pcm);
    final end = pcm.length - (pcm.length.isOdd ? 1 : 0);
    for (var i = 0; i < end; i += 2) {
      _samples.add(data.getInt16(i, Endian.little));
    }
    if (_samples.length > sampleRate) {
      _samples.removeRange(0, _samples.length - sampleRate ~/ 2);
    }
  }
}
