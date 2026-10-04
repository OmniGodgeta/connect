import 'dart:typed_data';

import 'package:connect/speaker_feed.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List pcm16(List<int> samples) {
  final data = ByteData(samples.length * 2);
  for (var i = 0; i < samples.length; i++) {
    data.setInt16(i * 2, samples[i], Endian.little);
  }
  return data.buffer.asUint8List();
}

void main() {
  test('speech queued after listening started is still fed', () {
    final fed = <List<int>>[];
    final feed = SpeakerFeed(sampleRate: 48000);
    feed.onReady = () {
      final chunk = feed.takeChunk();
      if (chunk != null) fed.add(chunk);
    };

    feed.start();
    expect(fed, isEmpty);

    feed.play(pcm16([1, -2, 3]));
    expect(fed, [
      [1, -2, 3],
    ]);
  });

  test('samples that arrive before listening are fed when it starts', () {
    final fed = <List<int>>[];
    final feed = SpeakerFeed(sampleRate: 48000);
    feed.onReady = () {
      final chunk = feed.takeChunk();
      if (chunk != null) fed.add(chunk);
    };

    feed.play(pcm16([4, 5]));
    expect(fed, isEmpty);
    feed.start();
    expect(fed, [
      [4, 5],
    ]);
  });

  test('stopping drops audio that has not been written yet', () {
    final feed = SpeakerFeed(sampleRate: 48000);
    feed.start();
    feed.play(pcm16([9]));
    feed.stop();
    final fed = <List<int>>[];
    feed.onReady = () {
      final chunk = feed.takeChunk();
      if (chunk != null) fed.add(chunk);
    };
    feed.start();
    expect(fed, isEmpty);
  });
}
