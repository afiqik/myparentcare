import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../cache_cdn/image_compressor.dart';
import '../cache_cdn/media_cache.dart';
import 'firestore_paths.dart';
import 'models.dart';

/// Media program dalam Firestore (pelan Spark – tanpa Cloud Storage).
///
/// * Gambar: dimampatkan (< 900 KB) dan disimpan sebagai Blob dalam satu
///   dokumen `media/{id}`. Dokumen tidak pernah diubah, jadi dicache kekal.
/// * Video: disimpan sebagai pautan https (YouTube / Google Drive) kerana had
///   dokumen Firestore ialah 1 MiB.
class MediaRepository {
  final FirebaseFirestore _db;
  final MediaCache cache;
  final Future<CompressedImage> Function(Uint8List) _compress;

  MediaRepository(
    this._db, {
    MediaCache? cache,
    Future<CompressedImage> Function(Uint8List)? compressor,
  }) : cache = cache ?? MediaCache(),
       _compress = compressor ?? ImageCompressor.compress;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection(FirestorePaths.media);

  Future<MediaItem> uploadImage({
    required Uint8List bytes,
    required String programId,
    required String adminUid,
    String caption = '',
  }) async {
    final compressed = await _compress(bytes);
    final ref = _col.doc();
    await ref.set({
      'id': ref.id,
      'programId': programId,
      'kind': 'image',
      'bytes': Blob(compressed.bytes),
      'contentType': compressed.contentType,
      'sizeBytes': compressed.bytes.length,
      'width': compressed.width,
      'height': compressed.height,
      'url': '',
      'caption': _clip(caption, 200),
      'uploadedBy': adminUid,
      'createdAt': FieldValue.serverTimestamp(),
    });
    final item = MediaItem(
      id: ref.id,
      programId: programId,
      kind: 'image',
      bytes: compressed.bytes,
      contentType: compressed.contentType,
      sizeBytes: compressed.bytes.length,
      width: compressed.width,
      height: compressed.height,
      caption: caption,
      uploadedBy: adminUid,
    );
    cache.put(item);
    return item;
  }

  Future<MediaItem> addVideoLink({
    required String url,
    required String programId,
    required String adminUid,
    String caption = '',
  }) async {
    final ref = _col.doc();
    await ref.set({
      'id': ref.id,
      'programId': programId,
      'kind': 'video',
      'url': url.trim(),
      'contentType': 'video/link',
      'sizeBytes': 0,
      'width': 0,
      'height': 0,
      'caption': _clip(caption, 200),
      'uploadedBy': adminUid,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return MediaItem(
      id: ref.id,
      programId: programId,
      kind: 'video',
      url: url.trim(),
      caption: caption,
      uploadedBy: adminUid,
    );
  }

  /// Cache memori → cache cakera Firestore → pelayan (hanya sekali).
  Future<MediaItem?> fetch(String id) async {
    if (id.isEmpty) return null;
    final cached = cache.get(id);
    if (cached != null) return cached;
    final ref = _col.doc(id);
    DocumentSnapshot<Map<String, dynamic>>? snapshot;
    try {
      snapshot = await ref.get(const GetOptions(source: Source.cache));
    } catch (_) {
      snapshot = null;
    }
    if (snapshot == null || !snapshot.exists) {
      snapshot = await ref.get();
    }
    final data = snapshot.data();
    if (!snapshot.exists || data == null) return null;
    final item = MediaItem.fromMap(data);
    cache.put(item);
    return item;
  }

  Future<List<MediaItem>> listForProgram(String programId) async {
    final snapshot = await _col
        .where('programId', isEqualTo: programId)
        .orderBy('createdAt')
        .get();
    final items = snapshot.docs.map((d) => MediaItem.fromMap(d.data())).toList();
    for (final item in items) {
      cache.put(item);
    }
    return items;
  }

  Future<void> delete(String id) async {
    cache.remove(id);
    await _col.doc(id).delete();
  }

  static String _clip(String value, int max) =>
      value.length <= max ? value : value.substring(0, max);

  /// ID video YouTube daripada pautan (untuk gambar kecil / thumbnail).
  static String? youtubeId(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return null;
    if (uri.host.contains('youtu.be')) {
      return uri.pathSegments.isNotEmpty ? uri.pathSegments.first : null;
    }
    if (uri.host.contains('youtube.com')) {
      if (uri.queryParameters['v'] != null) return uri.queryParameters['v'];
      final segments = uri.pathSegments;
      final index = segments.indexWhere((s) => s == 'shorts' || s == 'embed');
      if (index >= 0 && index + 1 < segments.length) return segments[index + 1];
    }
    return null;
  }
}
