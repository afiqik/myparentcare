import 'package:cloud_firestore/cloud_firestore.dart';

import '../database_storage/admin_workspace.dart';
import '../database_storage/firestore_paths.dart';
import '../database_storage/models.dart';
import '../load_balancer_scaling/seat_planner.dart';

class MigrationReport {
  final int users;
  final int programs;
  final int participants;
  final int emailLogs;
  final int announcements;
  final List<String> skipped;

  const MigrationReport({
    this.users = 0,
    this.programs = 0,
    this.participants = 0,
    this.emailLogs = 0,
    this.announcements = 0,
    this.skipped = const [],
  });

  int get total => users + programs + participants + emailLogs + announcements;
}

/// Pindahkan data versi lama (RTDB terbuka) ke struktur baharu Firestore.
///
/// * Akaun demo yang kata laluannya pernah didedahkan TIDAK dipindahkan.
/// * Peranan admin lama TIDAK dipindahkan – admin mesti dilantik semula oleh
///   super admin (menghalang pengambilalihan melalui data lama).
/// * Pengguna lama diminta memberi persetujuan Dasar Privasi semasa log masuk.
class LegacyMigrationService {
  static const demoEmails = {
    'admin@myparentcare.com',
    'student@myparentcare.com',
  };

  final FirebaseFirestore _db;
  final AdminWorkspace _workspace;

  LegacyMigrationService(this._db, this._workspace);

  Future<Map<String, dynamic>> readLegacy() => _workspace.readLegacyData();

  static Map<String, dynamic> _map(Object? value) =>
      value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

  Future<MigrationReport> migrate(
    Map<String, dynamic> legacy, {
    required String adminUid,
  }) async {
    final writes = <MapEntry<DocumentReference<Map<String, dynamic>>, Map<String, dynamic>>>[];
    final skipped = <String>[];
    final now = Timestamp.now();

    // ------------------------------------------------------------ pengguna
    var users = 0;
    final legacyUsers = _map(legacy['users']);
    final skippedUids = <String>{};
    legacyUsers.forEach((uid, raw) {
      final data = _map(raw);
      final email = data['email']?.toString().toLowerCase() ?? '';
      if (demoEmails.contains(email)) {
        skipped.add('Akaun demo $email');
        skippedUids.add(uid);
        return;
      }
      final user = AppUser.fromMap({...data, 'uid': uid, 'role': 'student'});
      writes.add(MapEntry(_db.doc(FirestorePaths.user(uid)), {
        ...user.toNewUserMap(),
        'email': data['email']?.toString() ?? '',
        'role': 'student',
        'privacyVersion': '', // minta persetujuan semula
        'createdAt': now,
        'updatedAt': now,
        'consentAt': now,
      }));
      users++;
    });

    // ------------------------------------------------ program & penyertaan
    var programs = 0;
    var participants = 0;
    final catalogPrograms = <String, dynamic>{};
    final legacyParticipants = _map(legacy['participants']);
    _map(legacy['programs']).forEach((pid, raw) {
      final data = _map(raw);
      final members = _map(legacyParticipants[pid])
        ..removeWhere((uid, _) => skippedUids.contains(uid));
      final capacity = [
        (data['capacity'] as num?)?.toInt() ?? 0,
        members.length,
        1,
      ].reduce((a, b) => a > b ? a : b);
      final caps = SeatPlanner.initialCaps(capacity);
      final program = Program.fromMap({...data, 'id': pid, 'capacity': capacity})
          .copyWith(seatShards: caps.length, createdBy: adminUid);

      writes.add(MapEntry(_db.doc(FirestorePaths.program(pid)), {
        ...program.toMap(),
        'createdAt': now,
        'updatedAt': now,
      }));
      if (program.isInCatalog) catalogPrograms[pid] = program.toCatalogMap();

      // Isi shard mengikut turutan.
      final counts = List.filled(caps.length, 0);
      var shard = 0;
      members.forEach((uid, rawParticipant) {
        while (shard < caps.length && counts[shard] >= caps[shard]) {
          shard++;
        }
        if (shard >= caps.length) return;
        counts[shard]++;
        final p = Participant.fromMap({
          ..._map(rawParticipant),
          'studentUid': uid,
          'programId': pid,
          'programTitle': program.title,
          'programDate': program.date,
          'programTime': program.time,
          'programLocation': program.location,
          'seatShard': SeatPlanner.shardId(shard),
        });
        final joinedAt = DateTime.tryParse(p.joinedAt);
        writes.add(MapEntry(_db.doc(FirestorePaths.participant(pid, uid)), {
          ...p.toJoinMap(),
          'emailStatus': ['sent', 'failed'].contains(p.emailStatus)
              ? p.emailStatus
              : 'pending',
          'joinedAt': joinedAt == null ? now : Timestamp.fromDate(joinedAt),
          'emailUpdatedAt': now,
        }));
        participants++;
      });
      for (var k = 0; k < caps.length; k++) {
        writes.add(MapEntry(
          _db.doc(FirestorePaths.shard(pid, SeatPlanner.shardId(k))),
          {'count': counts[k], 'cap': caps[k]},
        ));
      }
      programs++;
    });

    // --------------------------------------------------------- pengumuman
    final announcements = <String, dynamic>{};
    _map(legacy['announcements']).forEach((id, raw) {
      final a = Announcement.fromMap({..._map(raw), 'id': id});
      announcements[id] = a.toMap();
    });

    // ------------------------------------------------------------ log emel
    var emailLogs = 0;
    _map(legacy['email_logs']).forEach((id, raw) {
      final log = EmailLog.fromMap({..._map(raw), 'id': id});
      if (log.recipient.isEmpty) return;
      final created = DateTime.tryParse(log.createdAt);
      writes.add(MapEntry(_db.doc('${FirestorePaths.emailLogs}/$id'), {
        ...log.toMap(),
        'status': log.status == 'sent' ? 'sent' : 'failed',
        'createdBy': adminUid,
        'createdAt': created == null ? now : Timestamp.fromDate(created),
        'updatedAt': now,
      }));
      emailLogs++;
    });

    writes.add(MapEntry(_db.doc(FirestorePaths.catalogDoc), {
      'programs': catalogPrograms,
      'announcements': announcements,
      'updatedAt': now,
    }));

    for (var i = 0; i < writes.length; i += 400) {
      final batch = _db.batch();
      for (final write in writes.skip(i).take(400)) {
        if (write.key.path == FirestorePaths.catalogDoc) {
          batch.set(write.key, write.value, SetOptions(merge: true));
        } else {
          batch.set(write.key, write.value);
        }
      }
      await batch.commit();
    }

    return MigrationReport(
      users: users,
      programs: programs,
      participants: participants,
      emailLogs: emailLogs,
      announcements: announcements.length,
      skipped: skipped,
    );
  }

  Future<void> deleteLegacy() => _workspace.deleteLegacyData();
}
