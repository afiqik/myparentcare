import 'dart:async';

import 'package:firebase_database/firebase_database.dart';

import 'models.dart';

/// Ruang kerja admin dalam Realtime Database – pangkalan data BERASINGAN
/// daripada data pelajar (Firestore). Pelajar tidak boleh membaca apa-apa di
/// sini (lihat database.rules.json). Hanya admin yang membuka sambungan RTDB,
/// jadi had 100 sambungan serentak pelan Spark tidak dicapai oleh pelajar.
abstract class AdminWorkspace {
  Future<bool> isWorkspaceAdmin(String uid);
  Future<void> setWorkspaceAdmin(String uid, bool isAdmin);

  Future<void> logAction({
    required String actorUid,
    required String actorEmail,
    required String action,
    required String summary,
    String targetType = '',
    String targetId = '',
  });
  Stream<List<AuditEntry>> watchAudit({int limit = 100});

  Future<void> goOnline({
    required String uid,
    required String email,
    required String name,
  });
  Future<void> goOffline(String uid);
  Stream<List<AdminPresence>> watchPresence();

  Future<void> recordBackup(BackupRecord record);
  Stream<List<BackupRecord>> watchBackups({int limit = 20});

  /// Data versi lama (sebelum migrasi ke Firestore).
  Future<Map<String, dynamic>> readLegacyData();
  Future<void> deleteLegacyData();

  /// Eksport ruang kerja untuk backup.
  Future<Map<String, dynamic>> exportWorkspace();
  Future<void> restoreWorkspace(Map<String, dynamic> data);

  Stream<bool> watchConnected();

  /// Status emel automatik Apps Script (null = skrip belum pernah berjalan).
  Stream<AutomationStatus?> watchEmailAutomation();

  /// Private key EmailJS (admin sahaja). Tidak dimasukkan ke dalam backup.
  Future<String?> readEmailJsPrivateKey();
  Future<void> saveEmailJsPrivateKey(String key, {required String uid});
}

class RtdbAdminWorkspace implements AdminWorkspace {
  static const legacyNodes = [
    'users',
    'programs',
    'participants',
    'student_history',
    'student_notifications',
    'announcements',
    'email_logs',
    'system_errors',
  ];

  final FirebaseDatabase _db;

  RtdbAdminWorkspace(this._db);

  DatabaseReference get _workspace => _db.ref('admin_workspace');

  @override
  Future<bool> isWorkspaceAdmin(String uid) async {
    final snapshot = await _db
        .ref('admins/$uid')
        .get()
        .timeout(const Duration(seconds: 10));
    return snapshot.value == true;
  }

  @override
  Future<void> setWorkspaceAdmin(String uid, bool isAdmin) async {
    final ref = _db.ref('admins/$uid');
    if (isAdmin) {
      await ref.set(true);
    } else {
      await ref.remove();
      await _workspace.child('presence/$uid').remove().catchError((_) {});
    }
  }

  @override
  Future<void> logAction({
    required String actorUid,
    required String actorEmail,
    required String action,
    required String summary,
    String targetType = '',
    String targetId = '',
  }) async {
    String clip(String value, int max) =>
        value.length <= max ? value : value.substring(0, max);
    await _workspace.child('audit_logs').push().set({
      'action': clip(action, 60),
      'actorUid': actorUid,
      'actorEmail': clip(actorEmail, 254),
      'summary': clip(summary, 500),
      'targetType': clip(targetType, 40),
      'targetId': clip(targetId, 120),
      'at': ServerValue.timestamp,
    });
  }

  @override
  Stream<List<AuditEntry>> watchAudit({int limit = 100}) {
    return _workspace
        .child('audit_logs')
        .orderByChild('at')
        .limitToLast(limit)
        .onValue
        .map((event) {
          final value = event.snapshot.value;
          if (value is! Map) return <AuditEntry>[];
          final entries = value.entries
              .where((e) => e.value is Map)
              .map(
                (e) => AuditEntry.fromMap(
                  e.key.toString(),
                  Map<dynamic, dynamic>.from(e.value as Map),
                ),
              )
              .toList()
            ..sort((a, b) => b.at.compareTo(a.at));
          return entries;
        });
  }

  @override
  Future<void> goOnline({
    required String uid,
    required String email,
    required String name,
  }) async {
    final ref = _workspace.child('presence/$uid');
    await ref.onDisconnect().update({
      'online': false,
      'lastSeen': ServerValue.timestamp,
    });
    await ref.set({
      'online': true,
      'lastSeen': ServerValue.timestamp,
      'email': email,
      'name': name.length > 120 ? name.substring(0, 120) : name,
    });
  }

  @override
  Future<void> goOffline(String uid) async {
    final ref = _workspace.child('presence/$uid');
    await ref.update({'online': false, 'lastSeen': ServerValue.timestamp});
    await ref.onDisconnect().cancel();
  }

  @override
  Stream<List<AdminPresence>> watchPresence() {
    return _workspace.child('presence').onValue.map((event) {
      final value = event.snapshot.value;
      if (value is! Map) return <AdminPresence>[];
      return value.entries
          .where((e) => e.value is Map)
          .map(
            (e) => AdminPresence.fromMap(
              e.key.toString(),
              Map<dynamic, dynamic>.from(e.value as Map),
            ),
          )
          .toList()
        ..sort((a, b) => b.lastSeen.compareTo(a.lastSeen));
    });
  }

  @override
  Stream<AutomationStatus?> watchEmailAutomation() {
    return _workspace.child('automation/email').onValue.map((event) {
      final value = event.snapshot.value;
      return value is Map ? AutomationStatus.fromMap(value) : null;
    });
  }

  @override
  Future<void> recordBackup(BackupRecord record) async {
    await _workspace.child('backups').push().set({
      'at': ServerValue.timestamp,
      'by': record.by,
      'byEmail': record.byEmail,
      'documents': record.documents,
      'bytes': record.bytes,
      'kind': record.kind,
      'note': record.note.length > 300 ? record.note.substring(0, 300) : record.note,
    });
  }

  @override
  Stream<List<BackupRecord>> watchBackups({int limit = 20}) {
    return _workspace
        .child('backups')
        .orderByChild('at')
        .limitToLast(limit)
        .onValue
        .map((event) {
          final value = event.snapshot.value;
          if (value is! Map) return <BackupRecord>[];
          return value.entries
              .where((e) => e.value is Map)
              .map(
                (e) => BackupRecord.fromMap(
                  e.key.toString(),
                  Map<dynamic, dynamic>.from(e.value as Map),
                ),
              )
              .toList()
            ..sort((a, b) => b.at.compareTo(a.at));
        });
  }

  @override
  Future<Map<String, dynamic>> readLegacyData() async {
    final result = <String, dynamic>{};
    for (final node in legacyNodes) {
      final snapshot = await _db.ref(node).get();
      if (snapshot.exists) result[node] = snapshot.value;
    }
    return result;
  }

  @override
  Future<void> deleteLegacyData() async {
    await _db.ref().update({for (final node in legacyNodes) node: null});
  }

  @override
  Future<Map<String, dynamic>> exportWorkspace() async {
    final admins = await _db.ref('admins').get();
    final workspace = await _workspace.get();
    final value = workspace.value is Map
        ? Map<String, dynamic>.from(workspace.value as Map)
        : <String, dynamic>{};
    // Rahsia (private key EmailJS) TIDAK dieksport ke fail backup.
    value.remove('settings');
    return {
      'admins': admins.value,
      'admin_workspace': value,
    };
  }

  @override
  Future<String?> readEmailJsPrivateKey() async {
    final snapshot = await _workspace.child('settings/emailjs/privateKey').get();
    final value = snapshot.value;
    return value is String && value.isNotEmpty ? value : null;
  }

  @override
  Future<void> saveEmailJsPrivateKey(String key, {required String uid}) async {
    await _workspace.child('settings/emailjs').set({
      'privateKey': key.trim(),
      'updatedBy': uid,
      'updatedAt': ServerValue.timestamp,
    });
  }

  @override
  Future<void> restoreWorkspace(Map<String, dynamic> data) async {
    // Log audit & rekod backup adalah append-only; hanya nota dipulihkan.
    final workspace = data['admin_workspace'];
    if (workspace is Map && workspace['notes'] is Map) {
      await _workspace.child('notes').update(
        Map<String, Object?>.from(workspace['notes'] as Map),
      );
    }
  }

  @override
  Stream<bool> watchConnected() => _db
      .ref('.info/connected')
      .onValue
      .map((event) => event.snapshot.value == true);
}
