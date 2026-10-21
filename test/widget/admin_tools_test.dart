import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:my_parent_care/backend_logic/backup_service.dart';
import 'package:my_parent_care/database_storage/firestore_paths.dart';
import 'package:my_parent_care/database_storage/models.dart';
import 'package:my_parent_care/frontend/screens/admin/admin_more_screen.dart';
import 'package:my_parent_care/frontend/screens/admin/admin_users_screen.dart';
import 'package:my_parent_care/frontend/screens/admin/announcements_screen.dart';
import 'package:my_parent_care/frontend/screens/admin/audit_log_screen.dart';
import 'package:my_parent_care/frontend/screens/admin/backup_screen.dart';
import 'package:my_parent_care/frontend/screens/admin/email_logs_screen.dart';
import 'package:my_parent_care/frontend/screens/admin/email_settings_screen.dart';
import 'package:my_parent_care/frontend/screens/admin/reports_screen.dart';
import 'package:my_parent_care/frontend/screens/admin/system_screen.dart';
import 'package:my_parent_care/frontend/screens/auth/welcome_screen.dart';
import 'package:my_parent_care/frontend/screens/legal/privacy_policy_screen.dart';

import '../support/fakes.dart';
import '../support/platform_fakes.dart';
import '../support/widget_harness.dart';

Future<void> addLog(TestHarness h, String id, String status, {String type = 'join', String recipient = 'ibu@example.com'}) {
  return h.firestore.collection(FirestorePaths.emailLogs).doc(id).set({
    'id': id,
    'recipient': recipient,
    'subject': 'MyParentCare: $id',
    'body': 'Isi emel $id',
    'status': status,
    'errorMessage': status == 'failed' ? 'EmailJS ralat 500: server' : '',
    'studentName': 'Pelajar $id',
    'studentUid': 'stu-$id',
    'programId': 'p1',
    'programTitle': 'Hari Kerjaya',
    'type': type,
    'createdBy': 'admin1',
    'createdAt': Timestamp.now(),
    'updatedAt': Timestamp.now(),
    'attempts': status == 'queued' ? 0 : 1,
  });
}

Future<String?> logStatus(TestHarness h, String id) async =>
    (await h.firestore.collection(FirestorePaths.emailLogs).doc(id).get()).data()?['status'] as String?;

Future<void> openMenu(WidgetTester tester, String tooltip, String item) async {
  await tester.tap(find.byTooltip(tooltip));
  await tester.pumpAndSettle();
  await tester.tap(find.text(item).last);
  await tester.pumpAndSettle();
  await settle(tester);
}

void main() {
  late PlatformFakes fakes;

  setUp(() => fakes = setUpWidgetTest());

  // ================================================================== email centre

  group('Admin: Pusat Emel', () {
    testWidgets('tapis status, cari, butiran emel & cuba semula emel gagal', (tester) async {
      final h = await adminHarness();
      await addLog(h, 'ok1', 'sent', recipient: 'aina.parent@example.com');
      await addLog(h, 'bad1', 'failed', recipient: 'gagal@example.com');
      await pumpScreen(tester, h, const Scaffold(body: EmailLogsScreen()), attachAdmin: true);
      expect(find.text('aina.parent@example.com'), findsOneWidget);
      expect(find.text('gagal@example.com'), findsOneWidget);

      await tester.tap(find.widgetWithText(ChoiceChip, 'FAILED'));
      await settle(tester);
      expect(find.text('aina.parent@example.com'), findsNothing);
      expect(find.text('gagal@example.com'), findsOneWidget);
      await tester.tap(find.widgetWithText(ChoiceChip, 'All'));
      await settle(tester);

      await tester.enterText(find.byType(TextField).first, 'aina');
      await settle(tester, times: 2);
      expect(find.text('gagal@example.com'), findsNothing);
      await tester.enterText(find.byType(TextField).first, '');
      await settle(tester, times: 2);

      await tester.tap(find.text('gagal@example.com'));
      await tester.pumpAndSettle();
      expect(find.text('Email detail'), findsOneWidget);
      expect(find.text('Last error'), findsOneWidget);
      expect(find.text('EmailJS ralat 500: server'), findsWidgets);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      await tapVisible(tester, find.text('Retry'));
      expect(find.text('Email sent.'), findsOneWidget);
      expect(await logStatus(h, 'bad1'), 'sent');
      expect(h.gateway.sent.single.to, 'gagal@example.com');
    });

    testWidgets('hantar emel dalam barisan & pengesahan tertangguh', (tester) async {
      final h = await adminHarness();
      await addLog(h, 'q1', 'queued', type: 'update');
      final program = await h.programs.createProgram(TestHarness.program(), adminUid: 'admin1');
      await h.saveUser(TestHarness.student());
      await h.programs.joinProgram(program: program, student: TestHarness.student());
      await pumpScreen(tester, h, const Scaffold(body: EmailLogsScreen()), attachAdmin: true);

      await tapVisible(tester, find.text('Send queued (1)'));
      expect(await logStatus(h, 'q1'), 'sent');

      await tapVisible(tester, find.text('Pending confirmations (1)'));
      final participant = (await h.programs.fetchParticipants(program.id)).single;
      expect(participant.emailStatus, 'sent');
      expect(h.gateway.sent.map((m) => m.type), containsAll(['update', 'join']));
    });

    testWidgets('padam log: leret satu log & padam semua yang dihantar', (tester) async {
      final h = await adminHarness();
      await addLog(h, 's1', 'sent', recipient: 'satu@example.com');
      await addLog(h, 's2', 'sent', recipient: 'dua@example.com');
      await addLog(h, 'f1', 'failed', recipient: 'tiga@example.com');
      await pumpScreen(tester, h, const Scaffold(body: EmailLogsScreen()), attachAdmin: true);

      await tester.drag(find.text('satu@example.com'), const Offset(-600, 0));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();
      await settle(tester);
      expect(await logStatus(h, 's1'), isNull);

      await openMenu(tester, 'More', 'Delete delivered logs');
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();
      await settle(tester);
      expect(find.text('1 email logs deleted.'), findsOneWidget);
      expect(await logStatus(h, 's2'), isNull);
      expect(await logStatus(h, 'f1'), 'failed', reason: 'log gagal disimpan untuk siasatan');
    });

    testWidgets('kunci EmailJS tiada → amaran "Set up" ke Email settings', (tester) async {
      final h = await adminHarness();
      h.workspace.emailJsKey = null;
      await pumpScreen(tester, h, const Scaffold(body: EmailLogsScreen()), attachAdmin: true);
      expect(find.textContaining('EmailJS private key is not set'), findsOneWidget);
      await tester.tap(find.text('Set up'));
      await settle(tester);
      expect(find.byType(EmailSettingsScreen), findsOneWidget);
    });
  });

  // ================================================================== email settings

  group('Admin: Email settings', () {
    testWidgets('simpan private key (disembunyikan) & hantar emel ujian', (tester) async {
      final h = await adminHarness();
      h.workspace.emailJsKey = null;
      await pumpScreen(tester, h, const EmailSettingsScreen(), attachAdmin: true);
      expect(find.textContaining('No EmailJS private key yet'), findsOneWidget);
      await enterVisible(tester, find.byKey(const Key('emailjs_private_key')), 'pendek');
      await tapVisible(tester, find.byKey(const Key('emailjs_save')));
      expect(find.textContaining('Paste the Private Key'), findsOneWidget);
      await clearSnackBars(tester);

      await enterVisible(tester, find.byKey(const Key('emailjs_private_key')), 'kunci-ujian-yang-panjang-123');
      await tapVisible(tester, find.byKey(const Key('emailjs_save')));
      expect(h.workspace.emailJsKey, 'kunci-ujian-yang-panjang-123');
      await scrollTo(tester, find.textContaining('EmailJS private key is set'));
      expect(find.textContaining('EmailJS private key is set'), findsOneWidget);
      expect(h.workspace.auditEntries.first.summary, isNot(contains('kunci-ujian')), reason: 'kunci tidak masuk audit');
      await clearSnackBars(tester);

      await tapVisible(tester, find.text('Send test email'));
      await settle(tester, times: 4);
      expect(h.gateway.sent.single.to, 'admin@myparentcare.com');
      await scrollTo(tester, find.textContaining('Test email accepted by EmailJS'));
      expect(find.textContaining('Test email accepted by EmailJS'), findsOneWidget);
    });

    testWidgets('emel segera: pautan tidak sah ditolak; simpan, uji OK & uji gagal', (tester) async {
      final h = await adminHarness();
      await pumpScreen(tester, h, const EmailSettingsScreen(), attachAdmin: true);
      await scrollTo(tester, find.textContaining('Instant email is OFF'));
      expect(find.textContaining('Instant email is OFF'), findsOneWidget);

      await enterVisible(tester, find.byKey(const Key('relay_url')), 'https://evil.example.com/exec');
      await tapVisible(tester, find.byKey(const Key('relay_save')));
      expect(find.textContaining('Paste the Web app URL'), findsOneWidget);
      await clearSnackBars(tester);

      h.relayResponder = (_) => http.Response(
          '{"ok":true,"service":"myparentcare-email","version":2,"keyConfigured":true}', 200);
      await enterVisible(tester, find.byKey(const Key('relay_url')), TestHarness.relayUrl);
      await tapVisible(tester, find.byKey(const Key('relay_test')));
      await settle(tester, times: 4);
      await scrollTo(tester, find.textContaining('Automation is reachable and the EmailJS private key is available.'));
      expect(find.textContaining('Automation is reachable and the EmailJS private key is available.'), findsOneWidget);

      await tapVisible(tester, find.byKey(const Key('relay_save')));
      await settle(tester, times: 4);
      await scrollTo(tester, find.textContaining('Instant email is ON'));
      expect(find.textContaining('Instant email is ON'), findsOneWidget);
      expect((await h.firestore.doc('public/config').get()).data()!['emailRelayUrl'], TestHarness.relayUrl);

      h.relayResponder = (_) => http.Response('Not found', 404);
      await tapVisible(tester, find.byKey(const Key('relay_test')));
      await settle(tester, times: 4);
      await scrollTo(tester, find.textContaining('Automation did not answer'));
      expect(find.textContaining('Automation did not answer'), findsOneWidget);
    });
  });

  // ================================================================== laporan

  group('Admin: Laporan', () {
    Future<TestHarness> seeded() async {
      final h = await adminHarness();
      final program = await h.programs.createProgram(TestHarness.program(title: 'Futsal', capacity: 4), adminUid: 'admin1');
      await h.saveUser(TestHarness.student());
      await h.programs.joinProgram(program: program, student: TestHarness.student());
      await addLog(h, 'l1', 'sent');
      await addLog(h, 'l2', 'failed');
      return h;
    }

    testWidgets('4 jenis laporan + eksport CSV (data betul)', (tester) async {
      final h = await seeded();
      await pumpScreen(tester, h, const Scaffold(body: ReportsScreen()), attachAdmin: true);
      expect(find.text('Program report'), findsOneWidget);
      await tapVisible(tester, find.text('EXPORT CSV'));
      expect(fakes.share.lastName, matches(RegExp(r'^myparentcare_programs_\d{8}\.csv$')));
      var csv = utf8.decode((await fakes.share.lastBytes()).skip(3).toList());
      expect(csv, startsWith('"Title","Category","Date","Status","Capacity","Joined"'));
      expect(csv, contains('"Futsal"'));

      for (final (choice, title, file) in [
        ('Student joins', 'Student join report', 'joins'),
        ('Parent email', 'Parent notification report', 'email'),
        ('Monthly', 'Monthly report', 'monthly'),
      ]) {
        await tapVisible(tester, find.text(choice));
        expect(find.text(title), findsOneWidget);
        await tapVisible(tester, find.text('EXPORT CSV'));
        expect(fakes.share.lastName, startsWith('myparentcare_${file}_'));
      }
      csv = utf8.decode((await fakes.share.lastBytes()).skip(3).toList());
      expect(csv, startsWith('"Month","Programs","Joined Students","Emails Sent"'));
    });

    testWidgets('eksport PDF menghasilkan fail PDF sah; ralat kongsi dipaparkan', (tester) async {
      final h = await seeded();
      await pumpScreen(tester, h, const Scaffold(body: ReportsScreen()), attachAdmin: true);
      await tapVisible(tester, find.text('Parent email'));
      await tapVisible(tester, find.text('EXPORT PDF'));
      await settle(tester, times: 10);
      final pdf = await fakes.share.lastBytes();
      expect(String.fromCharCodes(pdf.take(5)), '%PDF-');
      expect(fakes.share.lastName, endsWith('.pdf'));

      fakes.share.fail = true;
      await tapVisible(tester, find.text('EXPORT CSV'));
      expect(find.textContaining('Share sheet unavailable'), findsOneWidget);
    });
  });

  // ================================================================== pengguna

  group('Admin: Pengguna & peranan', () {
    Future<TestHarness> withUsers({bool superAdmin = true}) async {
      final h = await adminHarness(superAdmin: superAdmin);
      await h.saveUser(TestHarness.student(uid: 'u1', email: 'aina@student.test', fullName: 'Aina'));
      await h.saveUser(TestHarness.student(uid: 'u2', email: 'badrul@student.test', fullName: 'Badrul'));
      await h.saveUser(TestHarness.student(uid: 'boss', email: 'admin@myparentcare.com', fullName: 'Pemilik').copyWith(role: 'admin'));
      return h;
    }

    testWidgets('senarai pelajar & admin; cari ikut emel tepat', (tester) async {
      final h = await withUsers();
      await pumpScreen(tester, h, const AdminUsersScreen(), attachAdmin: true);
      expect(find.text('Aina'), findsOneWidget);
      expect(find.text('Badrul'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'badrul@student.test');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await settle(tester);
      expect(find.text('Aina'), findsNothing);
      expect(find.text('Badrul'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'tiada@student.test');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await settle(tester);
      expect(find.text('No user with that email.'), findsOneWidget);

      await tester.tap(find.text('Admins'));
      await settle(tester);
      expect(find.text('Pemilik'), findsOneWidget);
      expect(find.text('Aina'), findsNothing);
    });

    testWidgets('gantung & aktifkan semula pelajar', (tester) async {
      final h = await withUsers();
      await pumpScreen(tester, h, const AdminUsersScreen(), attachAdmin: true);
      await tapVisible(tester, find.text('Aina'));
      await tapVisible(tester, find.text('Suspend'));
      expect(find.text('Suspend Aina?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Suspend'));
      await tester.pumpAndSettle();
      await settle(tester);
      expect((await h.users.fetch('u1'))!.isSuspended, isTrue);
      expect(h.workspace.auditEntries.first.action, 'user.status');
      await settle(tester, times: 8); // senarai dimuat semula

      // Kad mungkin kekal terbuka selepas senarai dimuat semula.
      if (find.text('Reactivate').evaluate().isEmpty) await tapVisible(tester, find.text('Aina'));
      await tapVisible(tester, find.text('Reactivate'));
      await tester.tap(find.widgetWithText(FilledButton, 'Reactivate'));
      await tester.pumpAndSettle();
      await settle(tester);
      expect((await h.users.fetch('u1'))!.isSuspended, isFalse);
    });

    testWidgets('super admin melantik admin (Firestore + ruang kerja RTDB)', (tester) async {
      final h = await withUsers();
      await pumpScreen(tester, h, const AdminUsersScreen(), attachAdmin: true);
      await tapVisible(tester, find.text('Badrul'));
      await tapVisible(tester, find.text('Make admin'));
      await tester.tap(find.widgetWithText(FilledButton, 'Make admin').last);
      await tester.pumpAndSettle();
      await settle(tester);
      expect((await h.users.fetch('u2'))!.role, 'admin');
      expect(h.workspace.admins, contains('u2'));
    });

    testWidgets('akaun super admin dilindungi; admin biasa tidak boleh melantik admin', (tester) async {
      final h = await withUsers(superAdmin: false);
      await pumpScreen(tester, h, const AdminUsersScreen(), attachAdmin: true);
      expect(find.textContaining('Only the super admin can appoint'), findsOneWidget);
      await tapVisible(tester, find.text('Aina'));
      expect(find.text('Suspend'), findsOneWidget);
      expect(find.text('Make admin'), findsNothing);

      await tester.tap(find.text('Admins'));
      await settle(tester);
      await tapVisible(tester, find.text('Pemilik'));
      expect(find.text('Super admin accounts are protected.'), findsOneWidget);
      await tapVisible(tester, find.text('Admin KPTM'));
      expect(find.text('This is your account.'), findsOneWidget);
    });
  });

  // ================================================================== pengumuman

  group('Admin: Pengumuman', () {
    testWidgets('kosong → terbit (dengan pengesahan medan) → padam', (tester) async {
      final h = await adminHarness();
      await pumpScreen(tester, h, const AnnouncementsScreen(), attachAdmin: true);
      expect(find.text('No announcements'), findsOneWidget);

      await tester.tap(find.text('New'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Publish'));
      await tester.pump();
      expect(find.text('Title is required'), findsOneWidget);
      expect(find.text('Message is required'), findsOneWidget);
      await tester.enterText(find.widgetWithText(TextFormField, 'Title'), 'Cuti semester');
      await tester.enterText(find.widgetWithText(TextFormField, 'Message'), 'Kampus ditutup minggu depan.');
      await tester.tap(find.text('Publish'));
      await tester.pumpAndSettle();
      await settle(tester);
      expect(find.text('Announcement published to all students.'), findsOneWidget);
      expect(find.text('Cuti semester'), findsOneWidget);
      final catalog = (await tester.runAsync(() => h.programs.watchCatalog().first))!;
      expect(catalog.announcements.single.message, 'Kampus ditutup minggu depan.');

      await tester.tap(find.byTooltip('Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();
      await settle(tester);
      expect(find.text('No announcements'), findsOneWidget);
    });
  });

  // ================================================================== sistem

  group('Admin: Kesihatan sistem', () {
    testWidgets('laporan ralat dipaparkan & dikosongkan', (tester) async {
      final h = await adminHarness();
      await h.firestore.collection(FirestorePaths.errorReports).add({
        'message': 'Join program failed',
        'error': 'StateError: x',
        'stackTrace': '#0 main',
        'platform': 'android',
        'appVersion': '1.0.0+6',
        'uid': 'stu1',
        'createdAt': Timestamp.now(),
      });
      await pumpScreen(tester, h, const SystemScreen(), attachAdmin: true);
      expect(find.text('Free plan (Spark) limits'), findsOneWidget);
      await scrollTo(tester, find.text('Join program failed'));
      expect(find.text('Join program failed'), findsOneWidget);
      await tapVisible(tester, find.text('Clear these reports'));
      await settle(tester);
      await scrollTo(tester, find.text('No errors reported'));
      expect(find.text('No errors reported'), findsOneWidget);
    });

    testWidgets('migrasi data lama: tiada data → mesej; ada data → import & padam', (tester) async {
      final h = await adminHarness();
      await pumpScreen(tester, h, const SystemScreen(), attachAdmin: true);
      await tapVisible(tester, find.text('Find & import old data'));
      expect(find.text('No old-version data found. Nothing to migrate.'), findsOneWidget);
      await clearSnackBars(tester);

      h.workspace.legacy = {
        'users': {
          'u1': {'uid': 'u1', 'email': 'lama@gmail.com', 'role': 'student', 'fullName': 'Pelajar Lama', 'parentEmail': 'p@x.com'},
        },
        'programs': {
          'p1': {'id': 'p1', 'title': 'Program Lama', 'capacity': 5, 'status': 'open', 'date': '2026-10-01', 'category': 'Sports', 'location': 'Padang'},
        },
      };
      await tapVisible(tester, find.text('Find & import old data'));
      expect(find.text('Import old-version data?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Import'));
      await settle(tester, times: 10);
      expect(find.text('Migration complete'), findsOneWidget);
      expect(find.textContaining('Users: 1'), findsOneWidget);
      expect(find.textContaining('Programs: 1'), findsOneWidget);
      await tester.tap(find.text('Delete old data'));
      await settle(tester, times: 8);
      expect(h.workspace.legacyDeleted, isTrue);
      expect((await h.users.fetch('u1'))!.fullName, 'Pelajar Lama');
    });
  });

  // ================================================================== audit

  group('Admin: Log audit', () {
    testWidgets('senarai tindakan & carian', (tester) async {
      final h = await adminHarness();
      await h.workspace.logAction(actorUid: 'admin1', actorEmail: 'admin@myparentcare.com', action: 'program.create', summary: 'Cipta "Futsal"');
      await h.workspace.logAction(actorUid: 'admin1', actorEmail: 'admin@myparentcare.com', action: 'backup.create', summary: 'Backup 12 dokumen');
      await h.workspace.logAction(actorUid: 'admin1', actorEmail: 'admin@myparentcare.com', action: 'email.retry', summary: 'Cuba semula emel');
      await pumpScreen(tester, h, const AuditLogScreen(), attachAdmin: true);
      expect(find.text('Cipta "Futsal"'), findsOneWidget);
      expect(find.text('Backup 12 dokumen'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'backup');
      await settle(tester, times: 2);
      expect(find.text('Cipta "Futsal"'), findsNothing);
      expect(find.text('Backup 12 dokumen'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'tiada-tindakan');
      await settle(tester, times: 2);
      expect(find.text('No activity yet'), findsOneWidget);
    });

    testWidgets('ruang kerja tidak disambung → mesej jelas', (tester) async {
      final h = await adminHarness(superAdmin: false);
      await pumpScreen(tester, h, const AuditLogScreen(), attachAdmin: true, workspaceReady: false);
      expect(find.text('Admin workspace not connected'), findsOneWidget);
    });
  });

  // ================================================================== alat admin

  group('Admin: Admin tools', () {
    testWidgets('setiap jubin membuka skrin yang betul; log keluar', (tester) async {
      final h = await adminHarness();
      await pumpScreen(tester, h, const Scaffold(body: AdminMoreScreen()), attachAdmin: true);
      expect(find.textContaining('Super admin'), findsOneWidget);
      for (final (tile, type) in [
        ('Users & roles', AdminUsersScreen),
        ('Email settings', EmailSettingsScreen),
        ('Announcements', AnnouncementsScreen),
        ('Backup & restore', BackupScreen),
        ('Audit log', AuditLogScreen),
        ('System health', SystemScreen),
        ('Privacy Policy', PrivacyPolicyScreen),
      ]) {
        await tapVisible(tester, find.text(tile));
        expect(find.byType(type), findsOneWidget, reason: tile);
        await tester.pageBack();
        await tester.pumpAndSettle();
        await settle(tester, times: 2);
      }
      await tapVisible(tester, find.text('Sign out'));
      await settle(tester);
      expect(find.byType(WelcomeScreen), findsOneWidget);
      expect(h.auth.currentUser, isNull);
    });
  });

  // ================================================================== backup

  group('Admin: Backup & pulih', () {
    testWidgets('cipta backup → fail JSON dikongsi & direkod dalam sejarah', (tester) async {
      final h = await adminHarness();
      await h.programs.createProgram(TestHarness.program(title: 'Program Backup'), adminUid: 'admin1');
      await pumpScreen(tester, h, const BackupScreen(), attachAdmin: true);
      await tapVisible(tester, find.byKey(const Key('backup_create')));
      await settle(tester, times: 8);
      expect(fakes.share.lastName, matches(RegExp(r'^myparentcare_backup_.*\.json$')));
      final backup = BackupService.parse(await fakes.share.lastBytes());
      expect(BackupService.summarize(backup).counts['programs'], 1);
      expect(h.workspace.backupRecords.single.kind, 'backup');
      expect(find.textContaining('Backup created'), findsOneWidget);
    });

    testWidgets('pulih dari fail (super admin) dengan pengesahan', (tester) async {
      final source = TestHarness();
      await source.programs.createProgram(TestHarness.program(title: 'Dipulihkan'), adminUid: 'a');
      final file = await BackupService(source.firestore, source.workspace).createBackup(adminEmail: 'a@b.com');

      final h = await adminHarness();
      fakes.filePicker.next = MemoryPlatformFile(file.fileName, file.bytes);
      await pumpScreen(tester, h, const BackupScreen(), attachAdmin: true);
      await tapVisible(tester, find.text('Restore from file'));
      expect(find.text('Restore this backup?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Restore'));
      await tester.pumpAndSettle();
      await settle(tester, times: 8);
      expect(find.textContaining('Restore complete'), findsOneWidget);
      final programs = await h.firestore.collection(FirestorePaths.programs).get();
      expect(programs.docs.single.data()['title'], 'Dipulihkan');
    });

    testWidgets('fail bukan backup ditolak dengan mesej jelas', (tester) async {
      final h = await adminHarness();
      fakes.filePicker.next = MemoryPlatformFile('x.json', Uint8List.fromList(utf8.encode('{"a":1}')));
      await pumpScreen(tester, h, const BackupScreen(), attachAdmin: true);
      await tapVisible(tester, find.text('Restore from file'));
      expect(find.text('Fail ini bukan backup MyParentCare.'), findsOneWidget);

    });

    testWidgets('admin biasa tidak boleh memulihkan backup', (tester) async {
      final staff = await adminHarness(superAdmin: false, uid: 'staff1');
      await pumpScreen(tester, staff, const BackupScreen(), attachAdmin: true);
      expect(find.text('Only the super admin can restore backups.'), findsOneWidget);
      final button = tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Restore from file'));
      expect(button.onPressed, isNull);
    });

    testWidgets('sejarah memaparkan backup manual & automatik', (tester) async {
      final h = await adminHarness();
      await h.workspace.recordBackup(const BackupRecord(
        id: 'b1', at: 1759300000000, by: 'admin1', byEmail: 'admin@myparentcare.com',
        documents: 7, bytes: 2048, kind: 'backup',
      ));
      await pumpScreen(tester, h, const BackupScreen(), attachAdmin: true);
      await scrollTo(tester, find.text('Backup · 7 documents'));
      expect(find.text('Backup · 7 documents'), findsOneWidget);
      expect(find.textContaining('No automatic backup yet'), findsOneWidget);
    });
  });
}
