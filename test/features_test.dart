import 'dart:typed_data';

import 'package:connect/gain.dart';
import 'package:connect/photo_image.dart';
import 'package:connect/presence.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  test('presence ignores the opening roster and yourself', () {
    final presence = Presence();
    expect(presence.take(['me', 'ada'], 'me'), (0, 0));
    expect(presence.take(['me', 'ada', 'bea'], 'me'), (1, 0));
    expect(presence.take(['me'], 'me'), (0, 2));
    presence.reset();
    expect(presence.take(['me', 'cam'], 'me'), (0, 0));
  });

  test('gain leaves full volume alone and silences zero', () {
    final pcm = ByteData(4)
      ..setInt16(0, 1000, Endian.little)
      ..setInt16(2, -1000, Endian.little);
    final bytes = pcm.buffer.asUint8List();
    expect(applyGain(bytes, 1), same(bytes));
    expect(applyGain(bytes, 0), isEmpty);
    final half = applyGain(bytes, 0.5);
    expect(ByteData.sublistView(half).getInt16(0, Endian.little), 500);
    expect(ByteData.sublistView(half).getInt16(2, Endian.little), -500);
  });

  test('a picture shrinks to a small jpeg', () {
    final source = img.Image(width: 40, height: 20);
    img.fill(source, color: img.ColorRgb8(20, 140, 180));
    final jpeg = shrinkJpeg(Uint8List.fromList(img.encodeJpg(source)));
    expect(jpeg, isNotNull);
    expect(jpeg!.length, lessThanOrEqualTo(maxPhotoBytes));
    expect(jpeg[0], 0xff);
    expect(jpeg[1], 0xd8);
    expect(shrinkJpeg(Uint8List.fromList([1, 2, 3, 4])), isNull);
  });
}
