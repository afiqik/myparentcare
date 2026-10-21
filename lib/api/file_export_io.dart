import 'dart:typed_data';

import 'package:share_plus/share_plus.dart';

Future<void> saveFile({
  required Uint8List bytes,
  required String fileName,
  required String mimeType,
  String? subject,
}) async {
  await SharePlus.instance.share(
    ShareParams(
      title: fileName,
      subject: subject ?? fileName,
      files: [XFile.fromData(bytes, mimeType: mimeType, name: fileName)],
      fileNameOverrides: [fileName],
    ),
  );
}
