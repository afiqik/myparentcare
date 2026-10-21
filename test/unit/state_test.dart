import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_parent_care/app_config.dart';
import 'package:my_parent_care/auth/auth_service.dart';
import 'package:my_parent_care/backend_logic/admin_state.dart';
import 'package:my_parent_care/backend_logic/backup_service.dart';
import 'package:my_parent_care/backend_logic/legacy_migration_service.dart';
import 'package:my_parent_care/backend_logic/student_state.dart';
import 'package:my_parent_care/database_storage/models.dart';
import 'package:my_parent_care/rate_limiting/rate_limiter.dart';

import '../support/fakes.dart';

Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 20));

AuthService authFor(TestHarness h) => AuthService(
  auth: h.auth,
  users: h.users,
  workspace: () => h.workspace,
  deletion: h.deletion,
  google: h.google,
);

void main() {
  setUp(RateLimiter.resetAll);

  group('AuthService (Google sahaja)', () {
    MockUser google(String uid, String email) =>
        MockUser(uid: uid, email: email, displayName: 'Nur Aina', isEmailVerified: true);

    test('pengguna Google baharu → needsProfile → profil pelajar dicipta', () async {
      final h = TestHarness(user: google('u1', 'aina@gmail.com'));
      final auth = authFor(h);
      final profile = await auth.signInWithGoogle();
      await settle();
      expect(profile, isNull);
      expect(auth.stage, AuthStage.needsProfile);
      await auth.createMissingProfile(fullName: 'Nur Aina', acceptedPrivacy: true);
      await settle();
      final saved = await h.users.fetch('u1');
      expect(saved!.role, 'student');
      expect(saved.authProvider, 'google');
      expect(saved.privacyVersion, AppConfig.privacyPolicyVersion);
      expect(auth.stage, AuthStage.ready);
    });

    test('tanpa persetujuan Dasar Privasi profil tidak dicipta', () async {
      final h = TestHarness(user: google('u1', 'aina@gmail.com'));
      final auth = authFor(h);
      await auth.signInWithGoogle();
      expect(
        () => auth.createMissingProfile(fullName: 'X', acceptedPrivacy: false),
        throwsStateError,
      );
    });

    test('profil sedia ada terus dimuatkan', () async {
      final h = TestHarness(user: google('stu1', 'aina@student.test'));
      await h.saveUser(TestHarness.student());
      final auth = authFor(h);
      final profile = await auth.signInWithGoogle();
      await settle();
      expect(profile!.fullName, 'Nur Aina');
      expect(auth.stage, AuthStage.ready);
    });

    test('dasar privasi baharu memerlukan persetujuan semula', () async {
      final h = TestHarness(user: google('stu1', 'aina@student.test'));
      await h.saveUser(TestHarness.student().copyWith(privacyVersion: '2020-01-01'));
      final auth = authFor(h);
      await auth.signInWithGoogle();
      await settle();
      expect(auth.stage, AuthStage.needsConsent);
      await auth.acceptPrivacyPolicy();
      await settle();
      expect(auth.stage, AuthStage.ready);
    });

    test('pelajar digantung → peringkat suspended', () async {
      final h = TestHarness(user: google('stu1', 'aina@student.test'));
      await h.saveUser(TestHarness.student().copyWith(status: 'suspended'));
      final auth = authFor(h);
      await auth.signInWithGoogle();
      await settle();
      expect(auth.stage, AuthStage.suspended);
    });

    test('super admin (Google) dicipta sebagai admin & ruang kerja RTDB dipautkan', () async {
      final h = TestHarness(user: google('super1', AppConfig.superAdminEmails.first));
      final auth = authFor(h);
      final profile = await auth.signInWithGoogle();
      expect(profile!.role, 'admin');
      expect(profile.authProvider, 'google');
      expect(auth.isSuperAdmin, isTrue);
      final access = await auth.ensureAdminAccess();
      expect(access.isAdmin, isTrue);
      expect(access.workspaceReady, isTrue);
      expect(h.workspace.admins, contains('super1'));
    });

    test('emel bukan super admin TIDAK dinaikkan menjadi admin', () async {
      final h = TestHarness(user: google('u9', 'hacker@evil.test'));
      await h.saveUser(TestHarness.student(uid: 'u9', email: 'hacker@evil.test'));
      final auth = authFor(h);
      await auth.signInWithGoogle();
      final access = await auth.ensureAdminAccess();
      expect(access.isAdmin, isFalse);
      expect(h.workspace.admins, isEmpty);
    });

    test('admin yang belum dipautkan ke ruang kerja diberi mesej jelas', () async {
      final h = TestHarness(user: google('admin2', 'staff@kptm.test'));
      await h.saveUser(TestHarness.student(uid: 'admin2', email: 'staff@kptm.test').copyWith(role: 'admin'));
      final auth = authFor(h);
      await auth.signInWithGoogle();
      final access = await auth.ensureAdminAccess();
      expect(access.isAdmin, isTrue);
      expect(access.workspaceReady, isFalse);
      expect(access.message, contains('super admin'));
    });

    test('padam akaun: sahkan semula dengan Google, data dipadam; admin ditolak', () async {
      final h = TestHarness(user: google('stu1', 'aina@student.test'));
      final student = TestHarness.student();
      await h.saveUser(student);
      final program = await h.programs.createProgram(TestHarness.program(), adminUid: 'a');
      await h.programs.joinProgram(program: program, student: student);
      final auth = authFor(h);
      await auth.signInWithGoogle();
      await settle();
      final report = await auth.deleteAccount(reason: 'Tamat');
      expect(h.google.reauthCount, 1);
      expect(report.participations, 1);
      expect(await h.users.fetch('stu1'), isNull);
      expect(auth.currentUser, isNull);

      final h2 = TestHarness(user: google('adm', 'staff@kptm.test'));
      await h2.saveUser(TestHarness.student(uid: 'adm').copyWith(role: 'admin'));
      final adminAuth = authFor(h2);
      await adminAuth.signInWithGoogle();
      await settle();
      expect(() => adminAuth.deleteAccount(), throwsStateError);
    });

    test('Google sign-in dibatalkan tidak mengubah sesi', () async {
      final h = TestHarness();
      h.google.cancel = true;
      final auth = authFor(h);
      expect(await auth.signInWithGoogle(), isNull);
      expect(auth.firebaseUser, isNull);
    });
  });

  group('StudentState', () {
    late TestHarness h;
    late StudentState state;

    setUp(() {
      h = TestHarness();
      state = StudentState(programs: h.programs, users: h.users);
    });

    tearDown(() => state.dispose());

    test('katalog: hanya program dibuka dipaparkan dalam senarai', () async {
      await h.programs.createProgram(TestHarness.program(title: 'Buka'), adminUid: 'a');
      await h.programs.createProgram(TestHarness.program(title: 'Draf', status: 'draft'), adminUid: 'a');
      await h.programs.createProgram(TestHarness.program(title: 'Tutup', status: 'closed'), adminUid: 'a');
      state.attach('stu1');
      await settle();
      expect(state.catalogLoaded, isTrue);
      expect(state.openPrograms.map((p) => p.title), ['Buka']);
      expect(state.programs.length, 2); // draf tidak pernah sampai ke pelajar
    });

    test('syarat sertai: profil, ibu bapa, pengesahan emel', () async {
      final program = await h.programs.createProgram(TestHarness.program(), adminUid: 'a');
      final incomplete = TestHarness.student(complete: false);
      expect((await state.joinProgram(program: program, student: incomplete, emailVerified: true)).code,
          'profile_required');
      final noParent = TestHarness.student().copyWith(parentEmail: '');
      expect((await state.joinProgram(program: program, student: noParent, emailVerified: true)).code,
          'parent_required');
      expect((await state.joinProgram(program: program, student: TestHarness.student(), emailVerified: false)).code,
          'email_unverified');
      final suspended = TestHarness.student().copyWith(status: 'suspended');
      expect((await state.joinProgram(program: program, student: suspended, emailVerified: true)).code,
          'suspended');
    });

    test('sertai berjaya → tempat disahkan, emel ibu bapa menunggu aplikasi admin', () async {
      final program = await h.programs.createProgram(TestHarness.program(capacity: 2), adminUid: 'a');
      final student = TestHarness.student();
      await h.saveUser(student);
      final outcome = await state.joinProgram(program: program, student: student, emailVerified: true);
      expect(outcome.success, isTrue);
      expect(outcome.emailStatus, 'pending');
      // Pelajar TIDAK memegang private key EmailJS, jadi tidak menghantar emel sendiri.
      expect(h.gateway.sent, isEmpty);
      expect((await h.programs.fetchParticipants(program.id)).single.emailStatus, 'pending');
      await settle();
      expect(state.seatsFor(program.id)!.joined, 1);
    });

    test('tekan dua kali pantas dihadkan kadar', () async {
      final program = await h.programs.createProgram(TestHarness.program(), adminUid: 'a');
      final student = TestHarness.student();
      final first = state.joinProgram(program: program, student: student, emailVerified: true);
      final second = await state.joinProgram(program: program, student: student, emailVerified: true);
      expect(second.code, 'rate_limited');
      expect((await first).success, isTrue);
    });

    test('program penuh memberi mesej yang jelas', () async {
      final program = await h.programs.createProgram(TestHarness.program(capacity: 1), adminUid: 'a');
      await h.programs.joinProgram(program: program, student: TestHarness.student(uid: 'other'));
      final outcome = await state.joinProgram(program: program, student: TestHarness.student(), emailVerified: true);
      expect(outcome.code, 'full');
    });

    test('notifikasi dimuat dan ditanda dibaca', () async {
      final program = await h.programs.createProgram(TestHarness.program(), adminUid: 'a');
      final student = TestHarness.student();
      await h.saveUser(student);
      await h.programs.joinProgram(program: program, student: student);
      await h.programs.notifyParticipants(
        participants: await h.programs.fetchParticipants(program.id),
        type: 'update', title: 'Tukar', message: 'm', programId: program.id,
      );
      await state.loadNotifications(student.uid);
      expect(state.notifications.single.isRead, isFalse);
      await state.markNotificationRead(student.uid, state.notifications.single.id);
      expect(state.notifications.single.isRead, isTrue);
      expect((await h.users.fetchNotifications(student.uid)).single.isRead, isTrue);
    });
  });

  group('AdminState', () {
    late TestHarness h;
    late AdminState state;
    const admin = AppUser(uid: 'admin1', email: 'staff@kptm.test', role: 'admin', fullName: 'Staff');

    setUp(() async {
      h = TestHarness();
      state = AdminState(
        programsRepo: h.programs,
        usersRepo: h.users,
        email: h.email,
        media: h.media,
        workspace: () => h.workspace,
        backup: () => BackupService(h.firestore, h.workspace),
        migration: () => LegacyMigrationService(h.firestore, h.workspace),
      );
      await state.attach(admin, workspaceReady: true);
    });

    tearDown(() => state.dispose());

    test('mencipta program merekod log audit dan kehadiran admin', () async {
      final program = await state.createProgram(TestHarness.program(title: 'Seminar'));
      await settle();
      expect(state.programs.single.id, program.id);
      expect(h.workspace.auditEntries.first.action, 'program.create');
      expect(h.workspace.auditEntries.first.actorUid, 'admin1');
      expect(h.workspace.presenceMap['admin1']!.online, isTrue);
    });

    test('batal program: pelajar dimaklumkan & emel ibu bapa dimasukkan ke barisan', () async {
      final program = await state.createProgram(TestHarness.program());
      for (final uid in ['a', 'b']) {
        final s = TestHarness.student(uid: uid);
        await h.saveUser(s);
        await h.programs.joinProgram(program: program, student: s);
      }
      final notified = await state.cancelProgram(program, 'Hujan lebat');
      expect(notified, 2);
      expect((await h.email.counts()).queued, 2);
      expect((await h.users.fetchNotifications('a')).single.type, 'cancelled');
      final result = await state.processEmailQueue();
      expect(result.done, 2);
      expect(h.gateway.sent.every((m) => m.type == 'cancelled'), isTrue);
      expect(h.workspace.auditEntries.map((e) => e.action), contains('program.cancel'));
    });

    test('kemas kini jadual memaklumkan peserta; perubahan tajuk sahaja tidak', () async {
      final program = await state.createProgram(TestHarness.program());
      final s = TestHarness.student();
      await h.saveUser(s);
      await h.programs.joinProgram(program: program, student: s);
      expect(await state.updateProgram(program.copyWith(title: 'Tajuk baharu'), previous: program), 0);
      final moved = program.copyWith(time: '14:00');
      expect(await state.updateProgram(moved, previous: program), 1);
      expect((await h.email.counts()).queued, 1);
    });

    test('lantik admin mengemas kini Firestore DAN ruang kerja RTDB', () async {
      final s = TestHarness.student(uid: 'staff2');
      await h.saveUser(s);
      await state.setUserRole(s, 'admin');
      expect((await h.users.fetch('staff2'))!.role, 'admin');
      expect(h.workspace.admins, contains('staff2'));
      await state.setUserRole(s.copyWith(role: 'admin'), 'student');
      expect(h.workspace.admins, isNot(contains('staff2')));
    });

    test('gantung pelajar direkod dalam audit', () async {
      final s = TestHarness.student(uid: 'naughty');
      await h.saveUser(s);
      await state.setUserStatus(s, 'suspended');
      expect((await h.users.fetch('naughty'))!.isSuspended, isTrue);
      expect(h.workspace.auditEntries.first.action, 'user.status');
    });

    test('backup direkod dalam sejarah ruang kerja', () async {
      await state.createProgram(TestHarness.program());
      final file = await state.createBackup();
      expect(file.summary.documents, greaterThan(0));
      expect(h.workspace.backupRecords.single.kind, 'backup');
      await settle();
      expect(state.lastBackup, isNotNull);
      expect(state.backupOverdue, isFalse);
    });

    test('backup automatik Apps Script dikenali & menghapuskan amaran backup lewat', () async {
      await settle();
      expect(state.backupOverdue, isTrue);
      await h.workspace.recordBackup(BackupRecord.fromMap('auto1', {
        'at': DateTime.now().millisecondsSinceEpoch,
        'by': 'apps-script',
        'byEmail': 'admin@myparentcare.com',
        'documents': 16,
        'bytes': 5943,
        'kind': 'backup',
        'note': 'Automatik → Google Drive/MyParentCare Backups/myparentcare_backup_x.json',
      }));
      await settle();
      expect(state.lastBackup!.isAutomatic, isTrue);
      expect(state.backupOverdue, isFalse);
    });

    test('emel ujian dihantar melalui gerbang & direkod dalam audit', () async {
      final ok = await state.sendTestEmail('admin@myparentcare.com');
      expect(ok.success, isTrue);
      expect(h.gateway.sent.single.to, 'admin@myparentcare.com');
      expect(h.gateway.sent.single.type, 'test');
      expect(h.workspace.auditEntries.first.action, 'email.test');
      h.gateway.fail = true;
      final failed = await state.sendTestEmail('admin@myparentcare.com');
      expect(failed.success, isFalse);
      expect(failed.error, isNotEmpty);
    });

    test('private key EmailJS disimpan di ruang kerja admin, tidak dalam log audit', () async {
      expect(state.emailKeyConfigured, isFalse);
      await state.saveEmailJsPrivateKey('secret-key-from-emailjs');
      expect(h.workspace.emailJsKey, 'secret-key-from-emailjs');
      expect(h.gateway.privateKey, 'secret-key-from-emailjs');
      expect(state.emailKeyConfigured, isTrue);
      expect(h.workspace.auditEntries.first.action, 'email.settings');
      expect(h.workspace.auditEntries.any((e) => e.summary.contains('secret-key')), isFalse);
    });

    test('kunci dimuatkan semasa admin log masuk & dibuang semasa log keluar', () async {
      h.workspace.emailJsKey = 'stored-key-1234567';
      await state.detach();
      expect(h.gateway.privateKey, isNull);
      await state.attach(admin, workspaceReady: true);
      expect(h.gateway.privateKey, 'stored-key-1234567');
      expect(state.emailKeyConfigured, isTrue);
      await state.detach();
      expect(h.gateway.privateKey, isNull);
    });

    test('penghantaran automatik: emel tertangguh dihantar apabila kunci ada', () async {
      final program = await state.createProgram(TestHarness.program());
      final s1 = TestHarness.student();
      await h.saveUser(s1);
      await h.programs.joinProgram(program: program, student: s1);
      // Tanpa kunci: tiada apa dihantar.
      await state.autoSendPendingEmails();
      expect(h.gateway.sent, isEmpty);
      await state.saveEmailJsPrivateKey('secret-key-from-emailjs');
      final pending = await h.email.fetchPendingJoinEmails();
      expect(pending, isNotEmpty);
      await state.sendPendingJoinEmails();
      expect(h.gateway.sent.single.to, s1.parentEmail);
      expect((await h.programs.fetchParticipants(program.id)).single.emailStatus, 'sent');
    });

    test('pengumuman diterbitkan ke katalog', () async {
      await state.addAnnouncement('Cuti', 'Kolej ditutup Jumaat');
      final catalog = await h.programs.watchCatalog().first;
      expect(catalog.announcements.single.title, 'Cuti');
    });
  });
}
