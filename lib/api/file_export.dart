import 'dart:typed_data';

import 'file_export_io.dart' as impl;

/// Simpan/kongsi fail (laporan CSV/PDF, backup JSON) merentas platform.
/// Android/iOS: helaian kongsi sistem (simpan ke Drive, Files, WhatsApp, emel).
class FileExport {
  FileExport._();

  static Future<void> save({
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
    String? subject,
  }) {
    return impl.saveFile(
      bytes: bytes,
      fileName: fileName,
      mimeType: mimeType,
      subject: subject,
    );
  }
}
