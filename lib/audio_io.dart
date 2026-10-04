import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_pcm_sound/flutter_pcm_sound.dart';
import 'package:record/record.dart';

import 'audio_engine.dart';
import 'config.dart';

class DeviceAudio implements AudioEngine {
  DeviceAudio() : _recorder = AudioRecorder();

  final AudioRecorder _recorder;
  StreamSubscription<Uint8List>? _mic;
  final List<int> _samples = <int>[];
  bool _listening = false;
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
    if (_listening || _starting) return;
    _starting = true;
    try {
      await FlutterPcmSound.setup(
        sampleRate: ConnectConfig.sampleRate,
        channelCount: 1,
      );
      await FlutterPcmSound.setFeedThreshold(ConnectConfig.sampleRate ~/ 10);
      FlutterPcmSound.setFeedCallback(_onFeed);
      _listening = true;
      FlutterPcmSound.start();
    } finally {
      _starting = false;
    }
  }

  @override
  void play(Uint8List pcm) {
    if (pcm.length < 2) return;
    _enqueue(pcm);
    if (!_listening) unawaited(beginListen());
  }

  void _enqueue(Uint8List pcm) {
    final data = ByteData.sublistView(pcm);
    final end = pcm.length - (pcm.length.isOdd ? 1 : 0);
    for (var i = 0; i < end; i += 2) {
      _samples.add(data.getInt16(i, Endian.little));
    }
    final cap = ConnectConfig.sampleRate;
    if (_samples.length > cap) {
      _samples.removeRange(0, _samples.length - ConnectConfig.sampleRate ~/ 2);
    }
  }

  void _onFeed(int remaining) {
    if (!_listening || _samples.isEmpty) return;
    final budget = ConnectConfig.sampleRate ~/ 10;
    final count = _samples.length < budget ? _samples.length : budget;
    final chunk = _samples.sublist(0, count);
    _samples.removeRange(0, count);
    FlutterPcmSound.feed(PcmArrayInt16.fromList(chunk));
  }

  @override
  Future<void> stopPlay() async {
    _samples.clear();
    if (!_listening) return;
    _listening = false;
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
