import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';

/// Opens the system photo picker. A cancel returns null and does not clear
/// a picture the person already chose.
Future<Uint8List?> pickGalleryPhoto() async {
  try {
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 256,
      maxHeight: 256,
      imageQuality: 70,
    );
    if (file == null) return null;
    return await file.readAsBytes();
  } catch (_) {
    return null;
  }
}
