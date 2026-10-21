import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../database_storage/admin_workspace.dart';
import '../database_storage/firestore_paths.dart';

class BackupSummary {
  final Map<String, int> counts;
  final int bytes;
  final String createdAt;
  final String createdBy;

  const BackupSummary({
    required this.counts,
    required this.bytes,
    this.createdAt = '',
    this.createdBy = '',
  });

  int get documents => counts.values.fold(0, (a, b) => a + b);
}

class BackupFile {
  final Uint8List bytes;
  final String fileName;
  final BackupSummary summary;

  const BackupFile({
    required this.bytes,
    required this.fileName,
    required this.summary,
  });
}

/// Backup penuh (Firestore + ruang kerja admin RTDB) ke fail JSON.
///
/// Pelan Spark tidak menyokong backup automatik terurus, jadi admin membuat
/// backup manual daripada aplikasi (disyorkan setiap minggu) dan menyimpan
/// fail di Google Drive / komputer. Hanya super admin boleh memulihkan.
class BackupService {
  static const format = 'myparentcare-backup';
  static const version = 1;

  final FirebaseFirestore _db;
  final AdminWorkspace _workspace;

  BackupService(this._db, this._workspace);

  // ------------------------------------------------------------ pengekodan

  static Object? encodeValue(Object? value) {
    if (value is Timestamp) {
      return {'__type': 'timestamp', 'value': value.toDate().toUtc().toIso8601String()};
    }
    if (value is Blob) {
      return {'__type': 'bytes', 'value': base64Encode(value.bytes)};
    }
    if (value is Map) {
      return value.map((k, v) => MapEntry(k.toString(), encodeValue(v)));
    }
    if (value is List) return value.map(encodeValue).toList();
    return value;
  }

  static Object? decodeValue(Object? value) {
    if (value is Map) {
      if (value['__type'] == 'timestamp') {
        return Timestamp.fromDate(DateTime.parse(value['value'] as String));
      }
      if (value['__type'] == 'bytes') {
        return Blob(base64Decode(value['value'] as String));
      }
      return value.map((k, v) => MapEntry(k.toString(), decodeValue(v)));
    }
    if (value is List) return value.map(decodeValue).toList();
    return value;
  }

  Future<Map<String, Object?>> _collection(String path) async {
    final snapshot = await _db.collection(path).get();
    return {for (final d in snapshot.docs) d.id: encodeValue(d.data())};
  }

  /// Kumpulan subkoleksi: { parentId: { docId: data } }.
  Future<Map<String, Map<String, Object?>>> _group(String name) async {
    final snapshot = await _db.collectionGroup(name).get();
    final result = <String, Map<String, Object?>>{};
    for (final doc in snapshot.docs) {
      final parentId = doc.reference.parent.parent?.id ?? '_';
      result.putIfAbsent(parentId, () => {})[doc.id] = encodeValue(doc.data());
    }
    return result;
  }

  // ---------------------------------------------------------------- backup

  Future<BackupFile> createBackup({required String adminEmail}) async {
    final firestore = <String, Object?>{
      FirestorePaths.users: await _collection(FirestorePaths.users),
      FirestorePaths.programs: await _collection(FirestorePaths.programs),
      FirestorePaths.programSeats: await _group(FirestorePaths.shards),
      FirestorePaths.participants: await _group(FirestorePaths.participants),
      FirestorePaths.notifications: await _group(FirestorePaths.notifications),
      'public': await _collection('public'),
      FirestorePaths.media: await _collection(FirestorePaths.media),
      FirestorePaths.emailLogs: await _collection(FirestorePaths.emailLogs),
      FirestorePaths.accountDeletions: await _collection(
        FirestorePaths.accountDeletions,
      ),
    };
    final rtdb = await _workspace.exportWorkspace();

    final counts = <String, int>{};
    firestore.forEach((key, value) {
      final map = value as Map;
      final nested = key == FirestorePaths.programSeats ||
          key == FirestorePaths.participants ||
          key == FirestorePaths.notifications;
      counts[key] = nested
          ? map.values.fold<int>(0, (total, v) => total + (v as Map).length)
          : map.length;
    });

    final createdAt = DateTime.now().toUtc().toIso8601String();
    final payload = {
      'format': format,
      'version': version,
      'createdAt': createdAt,
      'createdBy': adminEmail,
      'counts': counts,
      'firestore': firestore,
      'rtdb': rtdb,
    };
    final bytes = Uint8List.fromList(utf8.encode(jsonEncode(payload)));
    final stamp = createdAt.replaceAll(RegExp(r'[:.]'), '-').substring(0, 19);
    return BackupFile(
      bytes: bytes,
      fileName: 'myparentcare_backup_$stamp.json',
      summary: BackupSummary(
        counts: counts,
        bytes: bytes.length,
        createdAt: createdAt,
        createdBy: adminEmail,
      ),
    );
  }

  // ---------------------------------------------------------------- pulih

  static Map<String, dynamic> parse(Uint8List bytes) {
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map || decoded['format'] != format) {
      throw const FormatException('Fail ini bukan backup MyParentCare.');
    }
    if ((decoded['version'] as num? ?? 0) > version) {
      throw const FormatException('Versi backup lebih baharu daripada aplikasi.');
    }
    return Map<String, dynamic>.from(decoded);
  }

  static BackupSummary summarize(Map<String, dynamic> backup) {
    final counts = Map<String, dynamic>.from(backup['counts'] as Map? ?? {});
    return BackupSummary(
      counts: counts.map((k, v) => MapEntry(k, (v as num).toInt())),
      bytes: 0,
      createdAt: backup['createdAt']?.toString() ?? '',
      createdBy: backup['createdBy']?.toString() ?? '',
    );
  }

  /// Tulis semula semua dokumen daripada backup (super admin sahaja – rules).
  /// Dokumen sedia ada dengan ID sama akan ditimpa; dokumen lain tidak dipadam.
  Future<int> restore(
    Map<String, dynamic> backup, {
    void Function(int written)? onProgress,
  }) async {
    final firestore = Map<String, dynamic>.from(backup['firestore'] as Map);
    final writes = <MapEntry<DocumentReference<Map<String, dynamic>>, Map<String, dynamic>>>[];

    void addCollection(String path, Object? docs) {
      if (docs is! Map) return;
      docs.forEach((id, data) {
        writes.add(MapEntry(
          _db.collection(path).doc(id.toString()),
          Map<String, dynamic>.from(decodeValue(data) as Map),
        ));
      });
    }

    void addGroup(String Function(String parentId) pathFor, Object? groups) {
      if (groups is! Map) return;
      groups.forEach((parentId, docs) => addCollection(pathFor(parentId.toString()), docs));
    }

    addCollection(FirestorePaths.users, firestore[FirestorePaths.users]);
    addCollection(FirestorePaths.programs, firestore[FirestorePaths.programs]);
    addGroup(FirestorePaths.programShards, firestore[FirestorePaths.programSeats]);
    addGroup(FirestorePaths.programParticipants, firestore[FirestorePaths.participants]);
    addGroup(FirestorePaths.userNotifications, firestore[FirestorePaths.notifications]);
    addCollection('public', firestore['public']);
    addCollection(FirestorePaths.media, firestore[FirestorePaths.media]);
    addCollection(FirestorePaths.emailLogs, firestore[FirestorePaths.emailLogs]);
    addCollection(FirestorePaths.accountDeletions, firestore[FirestorePaths.accountDeletions]);

    var written = 0;
    // Kelompok kecil kerana dokumen media boleh hampir 1 MB (had 10 MB/commit).
    for (var i = 0; i < writes.length;) {
      final batch = _db.batch();
      var bytes = 0;
      var inBatch = 0;
      while (i < writes.length && inBatch < 400) {
        final size = _approxSize(writes[i].value);
        if (inBatch > 0 && bytes + size > 8 * 1024 * 1024) break;
        batch.set(writes[i].key, writes[i].value);
        bytes += size;
        inBatch++;
        i++;
      }
      await batch.commit();
      written += inBatch;
      onProgress?.call(written);
    }

    final rtdb = backup['rtdb'];
    if (rtdb is Map) {
      await _workspace.restoreWorkspace(Map<String, dynamic>.from(rtdb));
    }
    return written;
  }

  static int _approxSize(Map<String, dynamic> data) {
    var size = 0;
    for (final value in data.values) {
      if (value is Blob) {
        size += value.bytes.length;
      } else {
        size += value.toString().length;
      }
    }
    return size + 256;
  }
}
