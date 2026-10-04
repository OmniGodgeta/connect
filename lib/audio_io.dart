import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_pcm_sound/flutter_pcm_sound.dart';
import 'package:record/record.dart';

import 'audio_engine.dart';
import 'config.dart';
import 'speaker_feed.dart';

class DeviceAudio implements AudioEngine {
  DeviceAudio() : _recorder = AudioRecorder() {
    _feed = SpeakerFeed(sampleRate: ConnectConfig.sampleRate, onReady: _pump);
  }

  final AudioRecorder _recorder;
  late final SpeakerFeed _feed;
  StreamSubscription<Uint8List>? _mic;
  bool _starting = false;

  @override
  Future<bool> ensureMic() async {
    try {
      return await _recorder.hasPermission();
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> startMic(
    void Function(Uint8List chunk) onChunk, {
    required bool noiseCancel,
    bool alongside = false,
  }) async {
    await stopMic();
    final stream = await _start(noiseCancel, alongside);
    _mic = stream.listen(onChunk);
  }

  Future<Stream<Uint8List>> _start(bool noiseCancel, bool alongside) async {
    try {
      return await _recorder.startStream(
        _config(noiseCancel, alongside: alongside),
      );
    } catch (_) {
      if (!noiseCancel && !alongside) rethrow;
      // Some phones reject the processed path. The plain mic still talks.
      return _recorder.startStream(_config(false));
    }
  }

  RecordConfig _config(bool noiseCancel, {bool alongside = false}) {
    final processed = noiseCancel;
    final callPath = processed && !alongside;
    return RecordConfig(
      encoder: AudioEncoder.pcm16bits,
      sampleRate: ConnectConfig.sampleRate,
      numChannels: 1,
      autoGain: processed,
      echoCancel: processed,
      noiseSuppress: processed,
      androidConfig: AndroidRecordConfig(
        audioSource: callPath
            ? AndroidAudioSource.voiceCommunication
            : processed
            ? AndroidAudioSource.voiceRecognition
            : AndroidAudioSource.mic,
        audioManagerMode: callPath
            ? AudioManagerMode.modeInCommunication
            : AudioManagerMode.modeNormal,
        speakerphone: callPath,
      ),
    );
  }

  @override
  Future<void> stopMic() async {
    await _mic?.cancel();
    _mic = null;
    try {
      if (await _recorder.isRecording()) {
        await _recorder.stop();
      }
    } catch (_) {
      // The recorder can already be stopped when the permission sheet closes.
    }
  }

  @override
  Future<void> beginListen() async {
    if (_feed.listening || _starting) return;
    _starting = true;
    try {
      await FlutterPcmSound.setup(
        sampleRate: ConnectConfig.sampleRate,
        channelCount: 1,
      );
      await FlutterPcmSound.setFeedThreshold(ConnectConfig.sampleRate ~/ 10);
      FlutterPcmSound.setFeedCallback((_) => _pump());
      // Samples can arrive before setup finishes. start() feeds those, and
      // also arms the plugin's one-shot callback for an empty queue.
      _feed.start();
      FlutterPcmSound.start();
    } finally {
      _starting = false;
    }
  }

  @override
  void play(Uint8List pcm) {
    _feed.play(pcm);
    if (!_feed.listening) unawaited(beginListen());
  }

  void _pump() {
    final chunk = _feed.takeChunk();
    if (chunk == null) return;
    FlutterPcmSound.feed(PcmArrayInt16.fromList(chunk));
  }

  @override
  Future<void> stopPlay() async {
    final was = _feed.listening;
    _feed.stop();
    if (!was) return;
    FlutterPcmSound.setFeedCallback(null);
    await FlutterPcmSound.release();
  }

  @override
  Future<void> dispose() async {
    await stopMic();
    await stopPlay();
    await _recorder.dispose();
  }
}
