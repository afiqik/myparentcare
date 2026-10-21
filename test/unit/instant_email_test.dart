import 'dart:convert';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:my_parent_care/api/email_relay.dart';
import 'package:my_parent_care/backend_logic/admin_state.dart';
import 'package:my_parent_care/backend_logic/backup_service.dart';
import 'package:my_parent_care/backend_logic/email_service.dart';
import 'package:my_parent_care/backend_logic/legacy_migration_service.dart';
import 'package:my_parent_care/backend_logic/student_state.dart';
import 'package:my_parent_care/database_storage/firestore_paths.dart';
import 'package:my_parent_care/database_storage/models.dart';
import 'package:my_parent_care/rate_limiting/rate_limiter.dart';

import '../support/fakes.dart';

Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 30));

/// Emel SEGERA kepada ibu bapa selepas pelajar join (web app Apps Script),
/// serta sandaran & notifikasi apabila emel gagal.
void main() {
  setUp(RateLimiter.resetAll);

  group('EmailRelay (web app Apps Script)', () {
    const url = TestHarness.relayUrl;

    test('pautan disahkan: hanya script.google.com/macros/s/…/exec', () {
      expect(EmailRelay.isValidUrl(url), isTrue);
      expect(EmailRelay.isValidUrl('https://script.google.com/a/macros/kptm.edu.my/s/AKfyc_1/exec'), isTrue);
      expect(EmailRelay.isValidUrl('https://script.google.com/macros/s/AKfyc/dev'), isFalse);
      expect(EmailRelay.isValidUrl('https://evil.example.com/macros/s/AKfyc/exec'), isFalse);
      expect(EmailRelay.isValidUrl('http://script.google.com/macros/s/AKfyc/exec'), isFalse);
    });

    test('tiada pautan dalam public/config → tiada panggilan HTTP', () async {
      var calls = 0;
      final relay = EmailRelay(
        FakeFirebaseFirestore(),
        client: MockClient((_) async {
          calls++;
          return http.Response('{}', 200);
        }),
      );
      expect((await relay.notifyJoin(programId: 'p1', uid: 'u1')).status, 'unavailable');
      expect(calls, 0);
    });

    test('pautan tidak sah dalam public/config diabaikan', () async {
      final db = FakeFirebaseFirestore();
      await db.doc(EmailRelay.configDoc).set({'emailRelayUrl': 'https://evil.example.com/x'});
      final relay = EmailRelay(db, client: MockClient((_) async => http.Response('{}', 200)));
      expect(await relay.relayUrl(), isNull);
    });

    test('POST {join, programId, uid} → ikut 302 Apps Script → keputusan "sent"', () async {
      final db = FakeFirebaseFirestore();
      await db.doc(EmailRelay.configDoc).set({'emailRelayUrl': url});
      final requests = <http.Request>[];
      final relay = EmailRelay(
        db,
        client: MockClient((request) async {
          requests.add(request);
          if (request.method == 'POST') {
            return http.Response('', 302, headers: {
              'location': 'https://script.googleusercontent.com/macros/echo?user_content_key=abc',
            });
          }
          return http.Response('{"ok":true,"status":"sent"}', 200);
        }),
      );
      final result = await relay.notifyJoin(programId: 'p1', uid: 'stu1');
      expect(result.status, 'sent');
      expect(requests.first.method, 'POST');
      expect(requests.first.url.toString(), url);
      expect(jsonDecode(requests.first.body), {'action': 'join', 'programId': 'p1', 'uid': 'stu1'});
      expect(requests.last.method, 'GET');
      expect(requests.last.url.host, 'script.googleusercontent.com');
    });

    test('ralat HTTP / rangkaian tidak membaling – emel kekal pending untuk sandaran', () async {
      final db = FakeFirebaseFirestore();
      await db.doc(EmailRelay.configDoc).set({'emailRelayUrl': url});
      final down = EmailRelay(db, client: MockClient((_) async => http.Response('Server error', 500)));
      expect((await down.notifyJoin(programId: 'p1', uid: 'u')).status, 'error');
      final offline = EmailRelay(db, client: MockClient((_) async => throw http.ClientException('offline')));
      final result = await offline.notifyJoin(programId: 'p1', uid: 'u');
      expect(result.status, 'error');
      expect(result.message, contains('offline'));
    });

    test('ping membaca status private key; simpan pautan menulis public/config', () async {
      final db = FakeFirebaseFirestore();
      final relay = EmailRelay(
        db,
        client: MockClient((_) async => http.Response(
              '{"ok":true,"service":"myparentcare-email","version":2,"keyConfigured":true}', 200)),
      );
      final pong = await relay.ping(url);
      expect(pong.status, 'ok');
      expect(pong.keyConfigured, isTrue);
      expect((await relay.ping('https://evil.example.com')).status, 'invalid');

      expect(() => relay.saveRelayUrl('https://evil.example.com/exec', adminUid: 'a'), throwsArgumentError);
      await relay.saveRelayUrl('  $url  ', adminUid: 'admin1');
      final saved = (await db.doc(EmailRelay.configDoc).get()).data()!;
      expect(saved['emailRelayUrl'], url);
      expect(saved['emailRelayUpdatedBy'], 'admin1');
      expect(await relay.relayUrl(), url);
    });
  });

  group('StudentState: emel segera selepas join', () {
    late TestHarness h;
    late StudentState state;

    setUp(() {
      h = TestHarness();
      state = StudentState(programs: h.programs, users: h.users, relay: h.relay);
    });

    tearDown(() => state.dispose());

    test('join berjaya → web app dipanggil SEKALI dengan program & uid', () async {
      await h.enableInstantEmail();
      final program = await h.programs.createProgram(TestHarness.program(capacity: 2), adminUid: 'a');
      final student = TestHarness.student();
      await h.saveUser(student);
      final outcome = await state.joinProgram(program: program, student: student, emailVerified: true);
      expect(outcome.success, isTrue);
      await settle();
      expect(h.relayRequests, hasLength(1));
      expect(jsonDecode(h.relayRequests.single.body), {
        'action': 'join',
        'programId': program.id,
        'uid': student.uid,
      });
      // Pelajar tidak memegang private key – tiada emel dari telefon.
      expect(h.gateway.sent, isEmpty);
    });

    test('join gagal (penuh) → tiada panggilan web app', () async {
      await h.enableInstantEmail();
      final program = await h.programs.createProgram(TestHarness.program(capacity: 1), adminUid: 'a');
      await h.programs.joinProgram(program: program, student: TestHarness.student(uid: 'other'));
      final outcome = await state.joinProgram(program: program, student: TestHarness.student(), emailVerified: true);
      expect(outcome.success, isFalse);
      await settle();
      expect(h.relayRequests, isEmpty);
    });

    test('web app gagal → join tetap berjaya, emel kekal pending untuk sandaran', () async {
      await h.enableInstantEmail();
      h.relayResponder = (_) => http.Response('oops', 500);
      final program = await h.programs.createProgram(TestHarness.program(), adminUid: 'a');
      final student = TestHarness.student();
      await h.saveUser(student);
      expect((await state.joinProgram(program: program, student: student, emailVerified: true)).success, isTrue);
      await settle();
      expect((await h.programs.fetchParticipants(program.id)).single.emailStatus, 'pending');
    });
  });

  group('AdminState: sandaran tanpa emel berganda', () {
    late TestHarness h;
    late AdminState state;
    const admin = AppUser(uid: 'admin1', email: 'staff@kptm.test', role: 'admin', fullName: 'Staff');

    setUp(() async {
      h = TestHarness();
      h.workspace.emailJsKey = 'k' * 20;
      state = AdminState(
        programsRepo: h.programs,
        usersRepo: h.users,
        email: h.email,
        media: h.media,
        workspace: () => h.workspace,
        backup: () => BackupService(h.firestore, h.workspace),
        migration: () => LegacyMigrationService(h.firestore, h.workspace),
        relay: h.relay,
      );
    });

    tearDown(() => state.dispose());

    Future<Program> twoJoins() async {
      final program = await h.programs.createProgram(TestHarness.program(capacity: 5), adminUid: 'a');
      await h.programs.joinProgram(program: program, student: TestHarness.student(uid: 'fresh'));
      await h.programs.joinProgram(program: program, student: TestHarness.student(uid: 'old'));
      await h.firestore.doc(FirestorePaths.participant(program.id, 'old')).update({
        'joinedAt': DateTime.now().subtract(const Duration(minutes: 5)),
      });
      return program;
    }

    test('emel segera aktif: penghantaran automatik admin menunggu 2 minit (web app menghantar dahulu)', () async {
      await h.enableInstantEmail();
      final program = await twoJoins();
      await state.attach(admin, workspaceReady: true);
      await settle();
      expect(state.instantEmailConfigured, isTrue);
      await state.autoSendPendingEmails();
      expect(h.gateway.sent, hasLength(1));
      Future<String> status(String uid) async =>
          (await h.firestore.doc(FirestorePaths.participant(program.id, uid)).get()).data()!['emailStatus'] as String;
      expect(await status('old'), 'sent');
      expect(await status('fresh'), 'pending');

      // Butang manual "Send pending" tetap menghantar semua.
      await state.sendPendingJoinEmails();
      expect(h.gateway.sent, hasLength(2));
    });

    test('emel segera TIDAK aktif: aplikasi admin menghantar serta-merta seperti dahulu', () async {
      await twoJoins();
      await state.attach(admin, workspaceReady: true);
      await settle();
      expect(state.instantEmailConfigured, isFalse);
      await state.autoSendPendingEmails();
      expect(h.gateway.sent, hasLength(2));
    });

    test('tiada audit "Hantar 0 emel" setiap minit apabila semua penyertaan masih baharu', () async {
      await h.enableInstantEmail();
      final program = await h.programs.createProgram(TestHarness.program(), adminUid: 'a');
      await h.programs.joinProgram(program: program, student: TestHarness.student(uid: 'fresh'));
      await state.attach(admin, workspaceReady: true);
      await settle();
      final before = h.workspace.auditEntries.length;
      await state.autoSendPendingEmails();
      expect(h.gateway.sent, isEmpty);
      expect(h.workspace.auditEntries.length, before);
    });

    test('status automasi (Apps Script) dipaparkan kepada admin', () async {
      await state.attach(admin, workspaceReady: true);
      await settle();
      expect(state.emailAutomation, isNull);
      h.workspace.setAutomation(const AutomationStatus(
        ok: false,
        code: '426',
        message: 'Kuota EmailJS telah habis. Naik taraf pelan EmailJS: quota',
        at: 1759300000000,
      ));
      await settle();
      expect(state.emailAutomation!.ok, isFalse);
      expect(state.emailAutomation!.message, contains('Kuota EmailJS'));
    });

    test('simpan & uji pautan emel segera direkod dalam audit', () async {
      await state.attach(admin, workspaceReady: true);
      await settle();
      h.relayResponder = (_) => http.Response(
          '{"ok":true,"service":"myparentcare-email","version":2,"keyConfigured":true}', 200);
      await state.saveEmailRelayUrl(TestHarness.relayUrl);
      expect(state.emailRelayUrl, TestHarness.relayUrl);
      expect(h.workspace.auditEntries.first.action, 'email.relay');
      final pong = await state.testEmailRelay(TestHarness.relayUrl);
      expect(pong.status, 'ok');
      expect(pong.keyConfigured, isTrue);
    });
  });

  group('EmailService: emel gagal → pelajar dimaklumkan', () {
    late TestHarness h;

    setUp(() => h = TestHarness());

    Future<List<Map<String, dynamic>>> notificationsOf(String uid) async =>
        (await h.firestore.collection(FirestorePaths.userNotifications(uid)).get())
            .docs
            .map((d) => d.data())
            .toList();

    test('hantar semula gagal → satu notifikasi + kaunter belum dibaca; cubaan kedua tiada pendua', () async {
      final program = await h.programs.createProgram(TestHarness.program(title: 'Career Day'), adminUid: 'a');
      final student = TestHarness.student();
      await h.saveUser(student);
      await h.programs.joinProgram(program: program, student: student);
      final participant = (await h.programs.fetchParticipants(program.id)).single;
      h.gateway
        ..fail = true
        ..error = 'EmailJS menolak permintaan (templat/ID salah): bad address';

      expect(await h.email.resendJoin(participant: participant, program: program, adminUid: 'admin1'), isFalse);
      var notes = await notificationsOf(student.uid);
      expect(notes, hasLength(1));
      expect(notes.single['type'], 'info');
      expect(notes.single['title'], 'Emel kepada ibu bapa gagal dihantar');
      expect(notes.single['message'], contains('Career Day'));
      expect(notes.single['message'], contains(student.parentEmail));
      expect(notes.single['message'], contains('Alamat emel ibu bapa mungkin tidak sah'));
      expect(notes.single['isRead'], isFalse);
      expect((await h.users.fetch(student.uid))!.unreadNotifications, 1);

      await h.email.resendJoin(participant: participant, program: program, adminUid: 'admin1');
      notes = await notificationsOf(student.uid);
      expect(notes, hasLength(1));
      expect((await h.users.fetch(student.uid))!.unreadNotifications, 1);

      // Admin nampak sebab penuh dalam log.
      final logs = await h.email.fetchLogs();
      expect(logs.first.status, 'failed');
      expect(logs.first.errorMessage, contains('templat/ID salah'));
    });

    test('berjaya → tiada notifikasi kegagalan', () async {
      final program = await h.programs.createProgram(TestHarness.program(), adminUid: 'a');
      final student = TestHarness.student();
      await h.saveUser(student);
      await h.programs.joinProgram(program: program, student: student);
      final participant = (await h.programs.fetchParticipants(program.id)).single;
      expect(await h.email.resendJoin(participant: participant, program: program, adminUid: 'admin1'), isTrue);
      expect(await notificationsOf(student.uid), isEmpty);
    });

    test('petunjuk ringkas untuk pelajar', () {
      expect(EmailService.studentHint('EmailJS menolak permintaan (templat/ID salah): x'),
          contains('Alamat emel ibu bapa'));
      expect(EmailService.studentHint('Kuota EmailJS telah habis'), contains('masalah pada sistem emel'));
    });
  });
}
