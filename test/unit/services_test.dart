import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_parent_care/api/email_templates.dart';
import 'package:my_parent_care/backend_logic/backup_service.dart';
import 'package:my_parent_care/backend_logic/legacy_migration_service.dart';
import 'package:my_parent_care/database_storage/media_repository.dart';
import 'package:my_parent_care/database_storage/models.dart';

import '../support/fakes.dart';

void main() {
  late TestHarness h;

  setUp(() => h = TestHarness());

  Future<(Program, AppUser)> joined() async {
    final program = await h.programs.createProgram(TestHarness.program(), adminUid: 'admin1');
    final student = TestHarness.student();
    await h.saveUser(student);
    await h.programs.joinProgram(program: program, student: student);
    return (program, student);
  }

  group('EmailService', () {
    test('emel pengesahan: dihantar, status penyertaan & log dikemas kini', () async {
      final (program, student) = await joined();
      final status = await h.email.sendJoinConfirmation(student: student, program: program);
      expect(status, 'sent');
      expect(h.gateway.sent.single.to, student.parentEmail);
      final participant = (await h.programs.fetchParticipants(program.id)).single;
      expect(participant.emailStatus, 'sent');
      final logs = await h.email.fetchLogs();
      expect(logs.single.status, 'sent');
      expect(logs.single.createdBy, student.uid);
    });

    test('emel gagal direkod sebagai failed dan boleh dicuba semula', () async {
      final (program, student) = await joined();
      h.gateway.fail = true;
      expect(await h.email.sendJoinConfirmation(student: student, program: program), 'failed');
      final log = (await h.email.fetchLogs()).single;
      expect(log.status, 'failed');
      expect(log.errorMessage, isNotEmpty);
      h.gateway.fail = false;
      expect(await h.email.retry(log), isTrue);
      expect((await h.email.fetchLogs()).single.status, 'sent');
      expect((await h.email.counts()).sent, 1);
    });

    test('barisan emel admin diproses dengan kemajuan', () async {
      final (program, _) = await joined();
      final participants = await h.programs.fetchParticipants(program.id);
      final queued = await h.email.enqueue(
        participants: participants,
        build: (p) => EmailTemplates.update(participant: p, program: program),
        programId: program.id,
        adminUid: 'admin1',
      );
      expect(queued, 1);
      expect((await h.email.counts()).queued, 1);
      final progress = await h.email.processQueue().toList();
      expect(progress.last.done, 1);
      expect(progress.last.failed, 0);
      expect((await h.email.counts()).queued, 0);
    });

    test('admin menghantar semula emel tertangguh dan memadam log mengikut status', () async {
      final (program, _) = await joined();
      final participant = (await h.programs.fetchParticipants(program.id)).single;
      expect(participant.emailStatus, 'pending');
      expect(await h.email.resendJoin(participant: participant, program: program, adminUid: 'admin1'), isTrue);
      expect((await h.programs.fetchParticipants(program.id)).single.emailStatus, 'sent');
      expect(await h.email.clearLogs(status: 'sent'), 1);
      expect(await h.email.fetchLogs(), isEmpty);
    });
  });

  group('AccountDeletionService', () {
    test('memadam profil, penyertaan (tempat dilepaskan), notifikasi & log emel', () async {
      final (program, student) = await joined();
      await h.email.sendJoinConfirmation(student: student, program: program);
      await h.programs.notifyParticipants(
        participants: await h.programs.fetchParticipants(program.id),
        type: 'update',
        title: 't',
        message: 'm',
        programId: program.id,
      );
      final report = await h.deletion.deleteStudentData(student.uid, reason: 'Tamat pengajian');
      expect(report.participations, 1);
      expect(report.notifications, 1);
      expect(report.emailLogs, 1);
      expect(await h.users.fetch(student.uid), isNull);
      expect((await h.programs.fetchSeatSummary(program.id)).joined, 0);
      final deletions = await h.firestore.collection('account_deletions').get();
      expect(deletions.docs.single.data().containsKey('email'), isFalse);
      expect(deletions.docs.single.data()['reason'], 'Tamat pengajian');
    });
  });

  group('BackupService', () {
    test('Timestamp dan Blob dikodkan & dinyahkod dengan tepat', () {
      final ts = Timestamp.fromDate(DateTime.utc(2026, 9, 30, 8));
      final blob = Blob(Uint8List.fromList([1, 2, 3]));
      final encoded = BackupService.encodeValue({'t': ts, 'b': blob, 'l': [ts]});
      final decoded = BackupService.decodeValue(encoded) as Map;
      expect((decoded['t'] as Timestamp).toDate(), ts.toDate());
      expect((decoded['b'] as Blob).bytes, [1, 2, 3]);
      expect((decoded['l'] as List).first, isA<Timestamp>());
    });

    test('backup mengandungi semua koleksi dan boleh dipulihkan', () async {
      final (program, student) = await joined();
      await h.media.addVideoLink(url: 'https://youtu.be/x', programId: program.id, adminUid: 'admin1');
      final service = BackupService(h.firestore, h.workspace);
      final file = await service.createBackup(adminEmail: 'admin@kptm.test');
      expect(file.summary.counts['users'], 1);
      expect(file.summary.counts['participants'], 1);
      expect(file.summary.counts['program_seats'], program.seatShards);
      expect(file.summary.counts['media'], 1);
      expect(file.fileName, endsWith('.json'));

      final parsed = BackupService.parse(file.bytes);
      final fresh = TestHarness();
      final written = await BackupService(fresh.firestore, fresh.workspace).restore(parsed);
      expect(written, file.summary.documents);
      expect((await fresh.users.fetch(student.uid))!.fullName, student.fullName);
      expect((await fresh.programs.fetchParticipants(program.id)).length, 1);
      expect((await fresh.programs.watchCatalog().first).programs.single.id, program.id);
    });

    test('private key EmailJS TIDAK dimasukkan ke dalam fail backup', () async {
      h.workspace.emailJsKey = 'secret-key-from-emailjs';
      final file = await BackupService(h.firestore, h.workspace).createBackup(adminEmail: 'a@b.com');
      expect(String.fromCharCodes(file.bytes), isNot(contains('secret-key-from-emailjs')));
    });

    test('fail bukan backup ditolak', () {
      expect(
        () => BackupService.parse(Uint8List.fromList('{"hello":1}'.codeUnits)),
        throwsFormatException,
      );
    });
  });

  group('LegacyMigrationService', () {
    test('memindahkan data lama tanpa akaun demo dan tanpa peranan admin', () async {
      final legacy = {
        'users': {
          'u1': {'uid': 'u1', 'email': 'aina@gmail.com', 'role': 'student', 'fullName': 'Aina', 'parentEmail': 'p@x.com'},
          'u2': {'uid': 'u2', 'email': 'staff@gmail.com', 'role': 'admin', 'fullName': 'Staff'},
          'demo': {'uid': 'demo', 'email': 'admin@myparentcare.com', 'role': 'admin', 'fullName': 'Admin'},
        },
        'programs': {
          'p1': {'id': 'p1', 'title': 'Futsal', 'capacity': 2, 'status': 'full', 'date': '2026-10-01', 'category': 'Sports', 'location': 'Gelanggang'},
        },
        'participants': {
          'p1': {
            'u1': {'studentUid': 'u1', 'studentName': 'Aina', 'parentEmail': 'p@x.com', 'joinedAt': '2026-07-01T10:00:00', 'emailStatus': 'sent'},
            'demo': {'studentUid': 'demo', 'studentName': 'Demo', 'parentEmail': 'd@x.com', 'joinedAt': '2026-07-01T10:00:00'},
          },
        },
        'email_logs': {
          'e1': {'id': 'e1', 'recipient': 'p@x.com', 'subject': 's', 'body': 'b', 'status': 'sent', 'sentTime': '2026-07-01T10:00:00', 'studentName': 'Aina', 'programTitle': 'Futsal'},
        },
      };
      final service = LegacyMigrationService(h.firestore, h.workspace);
      final report = await service.migrate(legacy, adminUid: 'super1');
      expect(report.users, 2);
      expect(report.skipped.single, contains('admin@myparentcare.com'));
      expect(report.participants, 1);
      expect((await h.users.fetch('u2'))!.role, 'student');
      expect((await h.users.fetch('u1'))!.privacyVersion, '');
      expect(await h.users.fetch('demo'), isNull);
      final participant = (await h.programs.fetchParticipants('p1')).single;
      expect(participant.seatShard, isNotEmpty);
      expect((await h.programs.fetchSeatSummary('p1')).joined, 1);
      final catalog = await h.programs.watchCatalog().first;
      expect(catalog.programs.single.status, 'open');
      expect((await h.email.fetchLogs()).single.recipient, 'p@x.com');
    });
  });

  group('MediaRepository', () {
    test('gambar disimpan sebagai Blob dan dibaca semula daripada cache', () async {
      final item = await h.media.uploadImage(
        bytes: Uint8List.fromList(List.filled(2048, 7)),
        programId: 'p1',
        adminUid: 'admin1',
        caption: 'Poster',
      );
      final raw = await h.firestore.doc('media/${item.id}').get();
      expect(raw.data()!['bytes'], isA<Blob>());
      h.media.cache.clear();
      final fetched = await h.media.fetch(item.id);
      expect(fetched!.bytes!.length, 2048);
      expect(h.media.cache.get(item.id), isNotNull);
      await h.media.delete(item.id);
      expect(await h.media.fetch(item.id), isNull);
    });

    test('ID YouTube diekstrak untuk gambar kecil', () {
      expect(MediaRepository.youtubeId('https://youtu.be/abc123'), 'abc123');
      expect(MediaRepository.youtubeId('https://www.youtube.com/watch?v=xyz'), 'xyz');
      expect(MediaRepository.youtubeId('https://youtube.com/shorts/s1'), 's1');
      expect(MediaRepository.youtubeId('https://drive.google.com/file/d/1/view'), isNull);
    });
  });
}
