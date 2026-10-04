import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Largest JPEG the relay will forward.
const maxPhotoBytes = 24 * 1024;

/// Crops to a square and compresses until the JPEG fits [maxPhotoBytes].
Uint8List? shrinkJpeg(Uint8List bytes) {
  if (bytes.length < 4) return null;
  img.Image? decoded;
  try {
    decoded = img.decodeImage(bytes);
  } catch (_) {
    return null;
  }
  if (decoded == null) return null;
  final square = img.copyResizeCropSquare(decoded, size: 96);
  for (final quality in const [70, 40, 25]) {
    final jpeg = Uint8List.fromList(img.encodeJpg(square, quality: quality));
    if (jpeg.length <= maxPhotoBytes &&
        jpeg.length >= 4 &&
        jpeg[0] == 0xff &&
        jpeg[1] == 0xd8) {
      return jpeg;
    }
  }
  return null;
}
