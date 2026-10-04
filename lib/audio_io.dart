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
  }) async {
    await stopMic();
    final stream = await _start(noiseCancel);
    _mic = stream.listen(onChunk);
  }

  Future<Stream<Uint8List>> _start(bool noiseCancel) async {
    try {
      return await _recorder.startStream(_config(noiseCancel));
    } catch (_) {
      if (!noiseCancel) rethrow;
      // Some phones reject the voice-communication path. The plain mic still talks.
      return _recorder.startStream(_config(false));
    }
  }

  RecordConfig _config(bool noiseCancel) {
    return RecordConfig(
      encoder: AudioEncoder.pcm16bits,
      sampleRate: ConnectConfig.sampleRate,
      numChannels: 1,
      autoGain: noiseCancel,
      echoCancel: noiseCancel,
      noiseSuppress: noiseCancel,
      androidConfig: AndroidRecordConfig(
        audioSource: noiseCancel
            ? AndroidAudioSource.voiceCommunication
            : AndroidAudioSource.mic,
        audioManagerMode: noiseCancel
            ? AudioManagerMode.modeInCommunication
            : AudioManagerMode.modeNormal,
        speakerphone: noiseCancel,
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
    _samples.clear();
    if (_listening) return;
    await FlutterPcmSound.setup(
      sampleRate: ConnectConfig.sampleRate,
      channelCount: 1,
    );
    await FlutterPcmSound.setFeedThreshold(ConnectConfig.sampleRate ~/ 10);
    FlutterPcmSound.setFeedCallback(_onFeed);
    _listening = true;
    FlutterPcmSound.start();
  }

  @override
  void play(Uint8List pcm) {
    if (!_listening || pcm.length < 2) return;
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
