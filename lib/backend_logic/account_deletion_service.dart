import 'package:cloud_firestore/cloud_firestore.dart';

import '../database_storage/firestore_paths.dart';
import '../database_storage/program_repository.dart';

class DeletionReport {
  final int participations;
  final int notifications;
  final int emailLogs;

  const DeletionReport({
    this.participations = 0,
    this.notifications = 0,
    this.emailLogs = 0,
  });
}

/// Padam semua data peribadi pelajar (PDPA / Google Play "Account deletion").
///
/// Susunan penting: pengesahan semula dibuat oleh [AuthService] SEBELUM
/// servis ini dipanggil, supaya pemadaman akaun Auth pada akhirnya tidak gagal
/// dengan `requires-recent-login` selepas data sudah dipadam.
class AccountDeletionService {
  final FirebaseFirestore _db;
  final ProgramRepository _programs;

  AccountDeletionService(this._db, this._programs);

  Future<DeletionReport> deleteStudentData(
    String uid, {
    String reason = '',
  }) async {
    // 1. Keluar daripada semua program (kaunter tempat -1 setiap satu).
    final participations = await _programs.fetchMyParticipations(uid);
    for (final participation in participations) {
      await _programs.leaveProgram(participation);
    }

    // 2. Notifikasi dalam aplikasi.
    final notifications = await _deleteQuery(
      _db.collection(FirestorePaths.userNotifications(uid)),
    );

    // 3. Log emel ibu bapa yang berkaitan dengan pelajar ini.
    final emailLogs = await _deleteQuery(
      _db.collection(FirestorePaths.emailLogs).where('studentUid', isEqualTo: uid),
    );

    // 4. Rekod tanpa identiti (untuk laporan PDPA admin).
    await _db.collection(FirestorePaths.accountDeletions).add({
      'createdAt': FieldValue.serverTimestamp(),
      'reason': reason.length > 500 ? reason.substring(0, 500) : reason,
      'role': 'student',
    });

    // 5. Profil pelajar.
    await _db.doc(FirestorePaths.user(uid)).delete();

    return DeletionReport(
      participations: participations.length,
      notifications: notifications,
      emailLogs: emailLogs,
    );
  }

  Future<int> _deleteQuery(Query<Map<String, dynamic>> query) async {
    var total = 0;
    while (true) {
      final snapshot = await query.limit(400).get();
      if (snapshot.docs.isEmpty) return total;
      final batch = _db.batch();
      for (final doc in snapshot.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
      total += snapshot.docs.length;
      if (snapshot.docs.length < 400) return total;
    }
  }
}
