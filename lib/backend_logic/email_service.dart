import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../api/email_gateway.dart';
import '../api/email_templates.dart';
import '../app_config.dart';
import '../database_storage/firestore_paths.dart';
import '../database_storage/models.dart';
import '../database_storage/program_repository.dart';
import '../error_tracking/error_tracker.dart';

class EmailCounts {
  final int sent;
  final int failed;
  final int queued;

  const EmailCounts({this.sent = 0, this.failed = 0, this.queued = 0});

  int get total => sent + failed + queued;
  int get successRate => (sent + failed) == 0 ? 0 : ((sent / (sent + failed)) * 100).round();
}

class QueueProgress {
  final int done;
  final int total;
  final int failed;

  const QueueProgress({required this.done, required this.total, this.failed = 0});
}

/// Penghantaran emel ibu bapa + log dalam Firestore `email_logs`.
///
/// Tanpa Cloud Functions, emel dihantar dari peranti:
/// * Pengesahan penyertaan: dari telefon pelajar sejurus selepas mendaftar.
///   Jika aplikasi ditutup sebelum sempat, status kekal "pending" dan admin
///   boleh menghantarnya daripada Pusat Emel.
/// * Kemas kini / pembatalan: admin memasukkan emel ke dalam barisan
///   (status "queued") dan memprosesnya dengan had kadar; boleh disambung
///   semula jika terganggu.
class EmailService {
  final FirebaseFirestore _db;
  final EmailGateway gateway;
  final ProgramRepository _programs;
  final Duration spacing;

  EmailService(
    this._db, {
    required this.gateway,
    required this._programs,
    this.spacing = AppConfig.bulkEmailSpacing,
  });

  CollectionReference<Map<String, dynamic>> get _logs =>
      _db.collection(FirestorePaths.emailLogs);

  // ------------------------------------------------------------ pelajar

  Future<String> sendJoinConfirmation({
    required AppUser student,
    required Program program,
  }) async {
    final message = EmailTemplates.join(
      parentEmail: student.parentEmail.trim().toLowerCase(),
      studentName: student.fullName,
      program: program,
    );
    final result = await gateway.send(message);
    final status = result.success ? 'sent' : 'failed';
    try {
      await _programs.updateEmailStatus(
        programId: program.id,
        studentUid: student.uid,
        status: status,
      );
      final ref = _logs.doc();
      await ref.set(
        _logMap(
          id: ref.id,
          message: message,
          status: status,
          error: result.error,
          studentUid: student.uid,
          programId: program.id,
          createdBy: student.uid,
          attempts: 1,
        ),
      );
    } catch (error, stack) {
      ErrorTracker().logError(
        'Failed to record join email',
        error: error,
        stackTrace: stack,
      );
    }
    return status;
  }

  Map<String, dynamic> _logMap({
    required String id,
    required EmailMessage message,
    required String status,
    required String error,
    required String studentUid,
    required String programId,
    required String createdBy,
    required int attempts,
  }) {
    String clip(String value, int max) =>
        value.length <= max ? value : value.substring(0, max);
    return {
      'id': id,
      'recipient': message.to,
      'subject': clip(message.subject, 200),
      'body': clip(message.body, 3000),
      'status': status,
      'errorMessage': clip(error, 1000),
      'studentName': clip(message.studentName, 120),
      'studentUid': studentUid,
      'programId': programId,
      'programTitle': clip(message.programTitle, 120),
      'type': message.type,
      'createdBy': createdBy,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'attempts': attempts,
    };
  }

  // -------------------------------------------------------------- admin

  /// Masukkan emel kemas kini/pembatalan ke dalam barisan.
  Future<int> enqueue({
    required List<Participant> participants,
    required EmailMessage Function(Participant) build,
    required String programId,
    required String adminUid,
  }) async {
    var count = 0;
    for (var i = 0; i < participants.length; i += 400) {
      final batch = _db.batch();
      for (final participant in participants.skip(i).take(400)) {
        if (participant.parentEmail.isEmpty) continue;
        final ref = _logs.doc();
        batch.set(
          ref,
          _logMap(
            id: ref.id,
            message: build(participant),
            status: 'queued',
            error: '',
            studentUid: participant.studentUid,
            programId: programId,
            createdBy: adminUid,
            attempts: 0,
          ),
        );
        count++;
      }
      await batch.commit();
    }
    return count;
  }

  /// Proses emel dalam barisan satu demi satu (had kadar EmailJS).
  Stream<QueueProgress> processQueue({int limit = 100}) async* {
    final snapshot = await _logs
        .where('status', isEqualTo: 'queued')
        .orderBy('createdAt')
        .limit(limit)
        .get();
    final logs = snapshot.docs.map((d) => EmailLog.fromMap(d.data())).toList();
    var done = 0;
    var failed = 0;
    yield QueueProgress(done: 0, total: logs.length);
    for (final log in logs) {
      final ok = await _deliver(log);
      done++;
      if (!ok) failed++;
      yield QueueProgress(done: done, total: logs.length, failed: failed);
      if (done < logs.length && spacing > Duration.zero) {
        await Future.delayed(spacing);
      }
    }
  }

  Future<bool> _deliver(EmailLog log) async {
    final result = await gateway.send(EmailTemplates.fromLog(log));
    await _logs.doc(log.id).update({
      'status': result.success ? 'sent' : 'failed',
      'errorMessage': result.error.length > 1000
          ? result.error.substring(0, 1000)
          : result.error,
      'attempts': log.attempts + 1,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    if (log.type == 'join' && log.programId.isNotEmpty && log.studentUid.isNotEmpty) {
      await _programs
          .updateEmailStatus(
            programId: log.programId,
            studentUid: log.studentUid,
            status: result.success ? 'sent' : 'failed',
          )
          .catchError((_) {});
      if (!result.success) {
        await _notifyStudentFailed(
          uid: log.studentUid,
          notificationId: 'email-failed-${log.id}',
          programId: log.programId,
          programTitle: log.programTitle,
          parentEmail: log.recipient,
          error: result.error,
        );
      }
    }
    return result.success;
  }

  /// Sebab ringkas untuk pelajar (sebab penuh kekal dalam log admin).
  static String studentHint(String error) =>
      error.contains('templat/ID salah') || error.contains('ralat 422')
          ? 'Alamat emel ibu bapa mungkin tidak sah. '
          : 'Berlaku masalah pada sistem emel. ';

  Future<void> _notifyStudentFailed({
    required String uid,
    required String notificationId,
    required String programId,
    required String programTitle,
    required String parentEmail,
    required String error,
  }) async {
    try {
      await _programs.notifyEmailFailed(
        uid: uid,
        notificationId: notificationId,
        programId: programId,
        programTitle: programTitle,
        parentEmail: parentEmail,
        hint: studentHint(error),
      );
    } catch (error, stack) {
      ErrorTracker().logError('Notify student of failed email', error: error, stackTrace: stack);
    }
  }

  Future<bool> retry(EmailLog log) => _deliver(log);

  /// Hantar semula emel pengesahan penyertaan untuk seorang peserta.
  Future<bool> resendJoin({
    required Participant participant,
    required Program program,
    required String adminUid,
  }) async {
    final message = EmailTemplates.join(
      parentEmail: participant.parentEmail,
      studentName: participant.studentName,
      program: program,
    );
    final result = await gateway.send(message);
    final status = result.success ? 'sent' : 'failed';
    await _programs.updateEmailStatus(
      programId: program.id,
      studentUid: participant.studentUid,
      status: status,
    );
    if (!result.success) {
      final joined = DateTime.tryParse(participant.joinedAt)?.millisecondsSinceEpoch ?? 0;
      await _notifyStudentFailed(
        uid: participant.studentUid,
        notificationId: 'email-failed-${program.id}-$joined',
        programId: program.id,
        programTitle: program.title,
        parentEmail: participant.parentEmail,
        error: result.error,
      );
    }
    final ref = _logs.doc();
    await ref.set(
      _logMap(
        id: ref.id,
        message: message,
        status: status,
        error: result.error,
        studentUid: participant.studentUid,
        programId: program.id,
        createdBy: adminUid,
        attempts: 1,
      ),
    );
    return result.success;
  }

  /// Emel pengesahan yang belum dihantar (aplikasi pelajar ditutup awal).
  Future<List<Participant>> fetchPendingJoinEmails({int limit = 50}) async {
    final snapshot = await _db
        .collectionGroup(FirestorePaths.participants)
        .where('emailStatus', isEqualTo: 'pending')
        .limit(limit)
        .get();
    return snapshot.docs.map((d) => Participant.fromMap(d.data())).toList();
  }

  Future<int> countPendingJoinEmails() async {
    final result = await _db
        .collectionGroup(FirestorePaths.participants)
        .where('emailStatus', isEqualTo: 'pending')
        .count()
        .get();
    return result.count ?? 0;
  }

  Stream<List<EmailLog>> watchLogs({int limit = 50, String? status}) {
    Query<Map<String, dynamic>> query = _logs;
    if (status != null) query = query.where('status', isEqualTo: status);
    return query
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((s) => s.docs.map((d) => EmailLog.fromMap(d.data())).toList());
  }

  Future<List<EmailLog>> fetchLogs({int limit = 500}) async {
    final snapshot = await _logs
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .get();
    return snapshot.docs.map((d) => EmailLog.fromMap(d.data())).toList();
  }

  Future<EmailCounts> counts() async {
    Future<int> count(String status) async {
      final result = await _logs.where('status', isEqualTo: status).count().get();
      return result.count ?? 0;
    }

    final values = await Future.wait([
      count('sent'),
      count('failed'),
      count('queued'),
    ]);
    return EmailCounts(sent: values[0], failed: values[1], queued: values[2]);
  }

  Future<void> deleteLog(String id) => _logs.doc(id).delete();

  /// Padam log mengikut status (atau semua) secara berkelompok.
  Future<int> clearLogs({String? status}) async {
    var deleted = 0;
    while (true) {
      Query<Map<String, dynamic>> query = _logs;
      if (status != null) query = query.where('status', isEqualTo: status);
      final snapshot = await query.limit(400).get();
      if (snapshot.docs.isEmpty) break;
      final batch = _db.batch();
      for (final doc in snapshot.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
      deleted += snapshot.docs.length;
      if (snapshot.docs.length < 400) break;
    }
    return deleted;
  }
}
