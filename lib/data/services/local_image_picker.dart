import 'package:flutter/services.dart';

import '../models/composer.dart';

class LocalImagePicker {
  const LocalImagePicker._();

  static const _channel = MethodChannel('cn.edu.shu.lehu_client/image_picker');

  static Future<PickedImage?> pickImage() async {
    final result = await _channel.invokeMapMethod<String, Object?>('pickImage');
    if (result == null) {
      return null;
    }
    final bytes = result['bytes'];
    if (bytes is! Uint8List || bytes.isEmpty) {
      return null;
    }
    return PickedImage(
      bytes: bytes,
      filename: (result['filename'] as String?) ?? 'image.jpg',
      mimeType: (result['mimeType'] as String?) ?? 'image/jpeg',
    );
  }
}
