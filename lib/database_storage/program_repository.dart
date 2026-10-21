import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../load_balancer_scaling/retry_policy.dart';
import '../load_balancer_scaling/seat_planner.dart';
import 'firestore_paths.dart';
import 'models.dart';

/// Keputusan cubaan menyertai program.
enum JoinCode { success, alreadyJoined, full, unavailable, busy }

class JoinResult {
  final JoinCode code;
  final Participant? participant;
  final int attempts;

  const JoinResult(this.code, {this.participant, this.attempts = 1});

  bool get isSuccess => code == JoinCode.success;
}

/// Akses program, katalog awam, kaunter tempat dan penyertaan.
class ProgramRepository {
  static const _retryableCodes = {
    'aborted',
    'failed-precondition',
    'unavailable',
    'deadline-exceeded',
    'resource-exhausted',
  };

  final FirebaseFirestore _db;
  final RetryPolicy _retry;
  final Random _random;

  ProgramRepository(this._db, {RetryPolicy? retry, Random? random})
    : _retry = retry ?? RetryPolicy(),
      _random = random ?? Random();

  DocumentReference<Map<String, dynamic>> get _catalogRef =>
      _db.doc(FirestorePaths.catalogDoc);

  String newProgramId() => _db.collection(FirestorePaths.programs).doc().id;

  // ================================================================ pelajar

  /// Satu dokumen = semua program awam + pengumuman (1 bacaan sahaja).
  Stream<Catalog> watchCatalog() {
    return _catalogRef.snapshots(includeMetadataChanges: true).map(
      (snapshot) => Catalog.fromMap(
        snapshot.data(),
        fromCache: snapshot.metadata.isFromCache,
      ),
    );
  }

  Future<List<SeatShard>> fetchShards(String programId) async {
    final snapshot = await _db
        .collection(FirestorePaths.programShards(programId))
        .get();
    return snapshot.docs
        .map((d) => SeatShard.fromMap(d.id, d.data()))
        .toList();
  }

  Future<SeatSummary> fetchSeatSummary(String programId) async {
    return SeatPlanner.summarize(await fetchShards(programId));
  }

  /// Sertai program secara atomik: dokumen penyertaan + kaunter shard +1.
  ///
  /// Shard dipilih secara rawak. Jika shard penuh atau berlaku pertembungan,
  /// shard lain dicuba dengan backoff + jitter. Rules memastikan tiada
  /// overbooking walaupun klien diubah suai.
  Future<JoinResult> joinProgram({
    required Program program,
    required AppUser student,
  }) async {
    final participantRef = _db.doc(
      FirestorePaths.participant(program.id, student.uid),
    );
    final shardIds = List.generate(program.seatShards, SeatPlanner.shardId);
    if (shardIds.isEmpty || program.status != 'open') {
      return const JoinResult(JoinCode.unavailable);
    }

    final knownFull = <String>{};
    var denied = 0;
    for (var attempt = 1; attempt <= _retry.maxAttempts; attempt++) {
      final open = shardIds.where((id) => !knownFull.contains(id)).toList();
      if (open.isEmpty) return JoinResult(JoinCode.full, attempts: attempt);
      final shardId = open[_random.nextInt(open.length)];
      final shardRef = _db.doc(FirestorePaths.shard(program.id, shardId));
      final participant = Participant.fromStudent(
        student: student,
        program: program,
        seatShard: shardId,
      );

      try {
        final outcome = await _db.runTransaction<String>((tx) async {
          final existing = await tx.get(participantRef);
          if (existing.exists) return 'already_joined';
          final seat = await tx.get(shardRef);
          final data = seat.data();
          if (!seat.exists || data == null) return 'shard_full';
          final shard = SeatShard.fromMap(seat.id, data);
          if (shard.isFull) return 'shard_full';
          tx.update(shardRef, {'count': shard.count + 1});
          tx.set(participantRef, {
            ...participant.toJoinMap(),
            'joinedAt': FieldValue.serverTimestamp(),
            'emailUpdatedAt': FieldValue.serverTimestamp(),
          });
          return 'success';
        }, maxAttempts: 3);

        switch (outcome) {
          case 'success':
            return JoinResult(
              JoinCode.success,
              participant: participant,
              attempts: attempt,
            );
          case 'already_joined':
            return JoinResult(JoinCode.alreadyJoined, attempts: attempt);
          default:
            await _markFullShards(program.id, knownFull);
            continue;
        }
      } on FirebaseException catch (error) {
        if (error.code == 'permission-denied') {
          // Boleh jadi pertembungan (kiraan berubah), shard penuh, atau program
          // ditutup/profil tidak layak. Semak keadaan sebenar.
          if ((await participantRef.get()).exists) {
            return JoinResult(JoinCode.alreadyJoined, attempts: attempt);
          }
          await _markFullShards(program.id, knownFull);
          denied++;
          if (denied >= 6 && knownFull.length < shardIds.length) {
            return JoinResult(JoinCode.unavailable, attempts: attempt);
          }
        } else if (!_retryableCodes.contains(error.code)) {
          rethrow;
        }
        await _retry.wait(attempt);
      }
    }
    return JoinResult(JoinCode.busy, attempts: _retry.maxAttempts);
  }

  Future<void> _markFullShards(String programId, Set<String> knownFull) async {
    for (final shard in await fetchShards(programId)) {
      if (shard.isFull) knownFull.add(shard.id);
    }
  }

  /// Keluar program (digunakan semasa padam akaun): padam penyertaan + shard -1.
  Future<void> leaveProgram(Participant participant) async {
    final batch = _db.batch();
    batch.delete(
      _db.doc(
        FirestorePaths.participant(participant.programId, participant.studentUid),
      ),
    );
    batch.update(
      _db.doc(FirestorePaths.shard(participant.programId, participant.seatShard)),
      {'count': FieldValue.increment(-1)},
    );
    await batch.commit();
  }

  Stream<List<Participant>> watchMyParticipations(String uid) {
    return _db
        .collectionGroup(FirestorePaths.participants)
        .where('studentUid', isEqualTo: uid)
        .snapshots()
        .map(
          (snapshot) =>
              snapshot.docs.map((d) => Participant.fromMap(d.data())).toList()
                ..sort((a, b) => b.joinedAt.compareTo(a.joinedAt)),
        );
  }

  Future<List<Participant>> fetchMyParticipations(String uid) async {
    final snapshot = await _db
        .collectionGroup(FirestorePaths.participants)
        .where('studentUid', isEqualTo: uid)
        .get();
    return snapshot.docs.map((d) => Participant.fromMap(d.data())).toList();
  }

  Future<void> updateEmailStatus({
    required String programId,
    required String studentUid,
    required String status,
  }) {
    return _db.doc(FirestorePaths.participant(programId, studentUid)).update({
      'emailStatus': status,
      'emailUpdatedAt': FieldValue.serverTimestamp(),
    });
  }

  // ================================================================== admin

  Stream<List<Program>> watchAllPrograms() {
    return _db
        .collection(FirestorePaths.programs)
        .snapshots()
        .map(
          (snapshot) =>
              snapshot.docs.map((d) => Program.fromMap(d.data())).toList()
                ..sort((a, b) => a.date.compareTo(b.date)),
        );
  }

  /// Kiraan tempat bagi semua program (admin sahaja, collection group).
  Stream<Map<String, SeatSummary>> watchAllSeatSummaries() {
    return _db.collectionGroup(FirestorePaths.shards).snapshots().map((
      snapshot,
    ) {
      final grouped = <String, List<SeatShard>>{};
      for (final doc in snapshot.docs) {
        final programId = doc.reference.parent.parent?.id;
        if (programId == null) continue;
        grouped
            .putIfAbsent(programId, () => [])
            .add(SeatShard.fromMap(doc.id, doc.data()));
      }
      return grouped.map(
        (key, value) => MapEntry(key, SeatPlanner.summarize(value)),
      );
    });
  }

  Future<void> _ensureCatalog() async {
    final snapshot = await _catalogRef.get();
    if (!snapshot.exists) {
      await _catalogRef.set({
        'programs': <String, dynamic>{},
        'announcements': <String, dynamic>{},
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
  }

  void _writeCatalogEntry(Transaction tx, Program program) {
    if (program.isInCatalog) {
      tx.update(_catalogRef, {
        FieldPath(['programs', program.id]): program.toCatalogMap(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } else {
      tx.update(_catalogRef, {
        FieldPath(['programs', program.id]): FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
  }

  /// Cipta program baharu bersama shard kaunter dan entri katalog.
  Future<Program> createProgram(Program draft, {required String adminUid}) async {
    await _ensureCatalog();
    final id = draft.id.isEmpty ? newProgramId() : draft.id;
    final caps = SeatPlanner.initialCaps(draft.capacity);
    final program = draft.copyWith(
      id: id,
      seatShards: caps.length,
      createdBy: adminUid,
      updatedAt: DateTime.now().toIso8601String(),
    );
    await _db.runTransaction((tx) async {
      tx.set(_db.doc(FirestorePaths.program(id)), {
        ...program.toMap(),
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      for (var k = 0; k < caps.length; k++) {
        tx.set(_db.doc(FirestorePaths.shard(id, SeatPlanner.shardId(k))), {
          'count': 0,
          'cap': caps[k],
        });
      }
      _writeCatalogEntry(tx, program);
    });
    return program;
  }

  /// Kemas kini program. Jika kapasiti berubah, had shard disusun semula dalam
  /// transaksi yang sama (selamat walaupun pelajar sedang mendaftar).
  Future<Program> updateProgram(Program program) async {
    await _ensureCatalog();
    final programRef = _db.doc(FirestorePaths.program(program.id));
    return _db.runTransaction<Program>((tx) async {
      final current = await tx.get(programRef);
      final currentData = current.data();
      if (!current.exists || currentData == null) {
        throw StateError('Program tidak dijumpai.');
      }
      final previous = Program.fromMap(currentData);
      final shardIds = List.generate(previous.seatShards, SeatPlanner.shardId);
      final shards = <SeatShard>[];
      for (final id in shardIds) {
        final snap = await tx.get(_db.doc(FirestorePaths.shard(program.id, id)));
        final data = snap.data();
        if (snap.exists && data != null) shards.add(SeatShard.fromMap(id, data));
      }

      var seatShards = previous.seatShards;
      final currentCapacity = SeatPlanner.summarize(shards).capacity;
      if (program.capacity != currentCapacity || shards.isEmpty) {
        final caps = SeatPlanner.rebalance(
          existing: shards,
          newCapacity: program.capacity,
        );
        for (final entry in caps.entries) {
          final ref = _db.doc(FirestorePaths.shard(program.id, entry.key));
          if (shards.any((s) => s.id == entry.key)) {
            tx.update(ref, {'cap': entry.value});
          } else {
            tx.set(ref, {'count': 0, 'cap': entry.value});
          }
        }
        seatShards = caps.length;
      }

      final updated = program.copyWith(
        seatShards: seatShards,
        createdBy: previous.createdBy,
        updatedAt: DateTime.now().toIso8601String(),
      );
      tx.update(programRef, {
        ...updated.toMap(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      _writeCatalogEntry(tx, updated);
      return updated;
    });
  }

  Future<Program> setStatus(
    Program program,
    String status, {
    String reason = '',
  }) async {
    final updated = program.copyWith(
      status: status,
      cancellationReason: status == 'cancelled' ? reason : program.cancellationReason,
      updatedAt: DateTime.now().toIso8601String(),
    );
    await _ensureCatalog();
    await _db.runTransaction((tx) async {
      tx.update(_db.doc(FirestorePaths.program(program.id)), {
        'status': updated.status,
        'cancellationReason': updated.cancellationReason,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      _writeCatalogEntry(tx, updated);
    });
    return updated;
  }

  /// Padam program sepenuhnya (penyertaan, shard, entri katalog).
  Future<void> deleteProgram(String programId) async {
    final participants = await _db
        .collection(FirestorePaths.programParticipants(programId))
        .get();
    final shards = await _db
        .collection(FirestorePaths.programShards(programId))
        .get();
    final refs = [
      ...participants.docs.map((d) => d.reference),
      ...shards.docs.map((d) => d.reference),
    ];
    for (var i = 0; i < refs.length; i += 450) {
      final batch = _db.batch();
      for (final ref in refs.skip(i).take(450)) {
        batch.delete(ref);
      }
      await batch.commit();
    }
    await _ensureCatalog();
    final batch = _db.batch();
    batch.delete(_db.doc(FirestorePaths.program(programId)));
    batch.update(_catalogRef, {
      FieldPath(['programs', programId]): FieldValue.delete(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();
  }

  Stream<List<Participant>> watchParticipants(String programId) {
    return _db
        .collection(FirestorePaths.programParticipants(programId))
        .snapshots()
        .map(
          (snapshot) =>
              snapshot.docs.map((d) => Participant.fromMap(d.data())).toList()
                ..sort((a, b) => b.joinedAt.compareTo(a.joinedAt)),
        );
  }

  Future<List<Participant>> fetchParticipants(String programId) async {
    final snapshot = await _db
        .collection(FirestorePaths.programParticipants(programId))
        .get();
    return snapshot.docs.map((d) => Participant.fromMap(d.data())).toList();
  }

  /// Buang peserta: padam penyertaan, kaunter -1, dan notifikasi kepada pelajar.
  Future<void> removeParticipant({
    required Program program,
    required Participant participant,
  }) async {
    final batch = _db.batch();
    batch.delete(
      _db.doc(FirestorePaths.participant(program.id, participant.studentUid)),
    );
    if (participant.seatShard.isNotEmpty) {
      batch.update(
        _db.doc(FirestorePaths.shard(program.id, participant.seatShard)),
        {'count': FieldValue.increment(-1)},
      );
    }
    _addNotification(
      batch,
      participant.studentUid,
      type: 'removed',
      title: 'Penyertaan dibatalkan oleh admin',
      message: 'Anda telah dikeluarkan daripada ${program.title}.',
      programId: program.id,
    );
    await batch.commit();
  }

  void _addNotification(
    WriteBatch batch,
    String uid, {
    required String type,
    required String title,
    required String message,
    required String programId,
  }) {
    final ref = _db.collection(FirestorePaths.userNotifications(uid)).doc();
    batch.set(ref, {
      'id': ref.id,
      'type': type,
      'title': title.length > 120 ? title.substring(0, 120) : title,
      'message': message.length > 1000 ? message.substring(0, 1000) : message,
      'programId': programId,
      'createdAt': FieldValue.serverTimestamp(),
      'isRead': false,
    });
    batch.update(_db.doc(FirestorePaths.user(uid)), {
      'unreadNotifications': FieldValue.increment(1),
    });
  }

  /// Emel pengesahan kepada ibu bapa gagal – maklumkan pelajar SEKALI bagi
  /// setiap penyertaan ([notificationId] tetap; sama dengan Apps Script).
  Future<bool> notifyEmailFailed({
    required String uid,
    required String notificationId,
    required String programId,
    required String programTitle,
    required String parentEmail,
    required String hint,
  }) async {
    final ref = _db.doc('${FirestorePaths.userNotifications(uid)}/$notificationId');
    return _db.runTransaction((tx) async {
      if ((await tx.get(ref)).exists) return false;
      tx.set(ref, {
        'id': notificationId,
        'type': 'info',
        'title': 'Emel kepada ibu bapa gagal dihantar',
        'message': _clip(
          'Penyertaan anda dalam $programTitle tetap disahkan, tetapi emel pengesahan '
          'kepada $parentEmail tidak dapat dihantar. $hint'
          'Semak emel ibu bapa di Profil. Admin telah dimaklumkan dan boleh menghantar semula.',
          1000,
        ),
        'programId': programId,
        'createdAt': FieldValue.serverTimestamp(),
        'isRead': false,
      });
      tx.update(_db.doc(FirestorePaths.user(uid)), {
        'unreadNotifications': FieldValue.increment(1),
      });
      return true;
    });
  }

  static String _clip(String value, int max) =>
      value.length <= max ? value : value.substring(0, max);

  /// Hantar notifikasi dalam aplikasi kepada semua peserta (kelompok 200).
  Future<int> notifyParticipants({
    required List<Participant> participants,
    required String type,
    required String title,
    required String message,
    required String programId,
  }) async {
    var sent = 0;
    for (var i = 0; i < participants.length; i += 200) {
      final batch = _db.batch();
      for (final p in participants.skip(i).take(200)) {
        _addNotification(
          batch,
          p.studentUid,
          type: type,
          title: title,
          message: message,
          programId: programId,
        );
        sent++;
      }
      await batch.commit();
    }
    return sent;
  }

  // ------------------------------------------------------------ pengumuman

  Future<void> addAnnouncement(Announcement announcement, {int keep = 20}) async {
    await _ensureCatalog();
    await _db.runTransaction((tx) async {
      final snapshot = await tx.get(_catalogRef);
      final existing = Catalog.fromMap(snapshot.data()).announcements;
      final updates = <Object, Object?>{
        FieldPath(['announcements', announcement.id]): {
          ...announcement.toMap(),
          'createdAt': DateTime.now().toIso8601String(),
        },
        'updatedAt': FieldValue.serverTimestamp(),
      };
      // Simpan hanya [keep] pengumuman terkini supaya dokumen katalog kecil.
      for (final old in existing.skip(keep - 1)) {
        updates[FieldPath(['announcements', old.id])] = FieldValue.delete();
      }
      tx.update(_catalogRef, updates);
    });
  }

  Future<void> deleteAnnouncement(String id) async {
    await _catalogRef.update({
      FieldPath(['announcements', id]): FieldValue.delete(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }
}
