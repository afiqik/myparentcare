
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import '../app_config.dart';

class CompressedImage {
  final Uint8List bytes;
  final int width;
  final int height;
  final String contentType;

  const CompressedImage({
    required this.bytes,
    required this.width,
    required this.height,
    this.contentType = 'image/jpeg',
  });
}

/// Memampatkan gambar supaya muat dalam satu dokumen Firestore (< 1 MiB).
///
/// Saiz dikecilkan kepada maksimum [AppConfig.maxImageDimension] piksel dan
/// kualiti JPEG diturunkan secara berperingkat sehingga < [AppConfig.maxImageBytes].
class ImageCompressor {
  ImageCompressor._();

  static Future<CompressedImage> compress(Uint8List input) {
    // Isolate pada peranti mudah alih supaya UI tidak tersekat.
    return kIsWeb ? Future.value(compressSync(input)) : compute(compressSync, input);
  }

  static CompressedImage compressSync(Uint8List input) {
    final decoded = img.decodeImage(input);
    if (decoded == null) {
      throw const FormatException('Fail ini bukan gambar yang disokong.');
    }
    var image = img.bakeOrientation(decoded);
    var maxSide = AppConfig.maxImageDimension;
    var quality = 82;
    while (true) {
      final resized = (image.width > maxSide || image.height > maxSide)
          ? img.copyResize(
              image,
              width: image.width >= image.height ? maxSide : null,
              height: image.height > image.width ? maxSide : null,
              interpolation: img.Interpolation.average,
            )
          : image;
      final bytes = Uint8List.fromList(img.encodeJpg(resized, quality: quality));
      if (bytes.length <= AppConfig.maxImageBytes) {
        return CompressedImage(
          bytes: bytes,
          width: resized.width,
          height: resized.height,
        );
      }
      if (quality > 50) {
        quality -= 10;
      } else if (maxSide > 480) {
        maxSide = (maxSide * 0.75).round();
        image = resized;
      } else {
        throw const FormatException(
          'Gambar terlalu besar walaupun selepas dimampatkan.',
        );
      }
    }
  }
}
