import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_parent_care/app_config.dart';
import 'package:my_parent_care/backend_logic/admin_state.dart';
import 'package:my_parent_care/database_storage/models.dart';
import 'package:my_parent_care/frontend/screens/admin/backup_screen.dart';
import 'package:my_parent_care/frontend/screens/admin/email_logs_screen.dart';
import 'package:my_parent_care/frontend/screens/admin/email_settings_screen.dart';
import 'package:my_parent_care/frontend/screens/student/join_success_screen.dart';
import 'package:my_parent_care/backend_logic/student_state.dart';
import 'package:my_parent_care/database_storage/firestore_paths.dart';
import 'package:my_parent_care/frontend/screens/auth/consent_screen.dart';
import 'package:my_parent_care/frontend/screens/auth/splash_screen.dart';
import 'package:my_parent_care/frontend/screens/auth/welcome_screen.dart';
import 'package:my_parent_care/frontend/screens/student/complete_profile_screen.dart';
import 'package:my_parent_care/frontend/screens/legal/privacy_content.dart';
import 'package:my_parent_care/frontend/screens/legal/privacy_policy_screen.dart';
import 'package:my_parent_care/frontend/screens/student/delete_account_screen.dart';
import 'package:my_parent_care/frontend/screens/student/program_detail_screen.dart';
import 'package:my_parent_care/main.dart';
import 'package:my_parent_care/rate_limiting/rate_limiter.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fakes.dart';

Future<void> pumpApp(WidgetTester tester, TestHarness h, Widget home) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.6;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MyParentCareApp(services: h.services(), home: home));
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  setUp(() {
    RateLimiter.resetAll();
    SharedPreferences.setMockInitialValues({'onboarding_done': true});
    PackageInfo.setMockInitialValues(
      appName: 'MyParentCare',
      packageName: 'com.myparentcare.my_parent_care',
      version: '1.0.0',
      buildNumber: '2',
      buildSignature: '',
    );
  });

  testWidgets('Skrin alu-aluan: Google sahaja – tiada medan emel/kata laluan', (tester) async {
    await pumpApp(tester, TestHarness(), const WelcomeScreen());
    expect(find.text(AppConfig.audienceTagline), findsOneWidget);
    expect(find.text('Log masuk dengan Google'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.textContaining('Password'), findsNothing);
    expect(find.textContaining('Create student account'), findsNothing);
    await tester.scrollUntilVisible(find.text('Privacy Policy'), 200);
    expect(find.text('Privacy Policy'), findsOneWidget);
  });

  testWidgets('Log masuk Google (pengguna baharu) → skrin persetujuan & profil', (tester) async {
    final h = TestHarness(user: MockUser(uid: 'new1', email: 'baru@gmail.com', displayName: 'Pelajar Baru'));
    await pumpApp(tester, h, const WelcomeScreen());
    await tester.tap(find.byKey(const Key('google_sign_in')));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('One more step'), findsOneWidget);
    expect(find.byType(ConsentScreen), findsOneWidget);
    // Nama daripada akaun Google diisi terlebih dahulu.
    expect(find.widgetWithText(TextFormField, 'Pelajar Baru'), findsOneWidget);
  });

  testWidgets('Tetapan profil WAJIB: pelajar tidak lengkap sentiasa dihantar ke "Set up your profile"', (tester) async {
    final h = TestHarness(user: MockUser(uid: 'stu1', email: 'aina@student.test'), signedIn: true);
    await h.saveUser(TestHarness.student(complete: false));
    // Aplikasi sebenar bermula dari SplashScreen yang menghala ikut keadaan akaun.
    await pumpApp(tester, h, const SplashScreen());
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(CompleteProfileScreen), findsOneWidget);
    expect(find.text('Set up your profile'), findsOneWidget);
    expect(find.byType(BackButton), findsNothing);
    expect(find.text('Sign out'), findsOneWidget);
    // Simpan dengan medan kosong → ralat pengesahan, tidak boleh diteruskan.
    await tester.tap(find.text('SAVE PROFILE'));
    await tester.pump();
    expect(find.text('Matric/Student ID is required'), findsOneWidget);
    expect(find.text('Parent name is required'), findsOneWidget);
  });

  testWidgets('Profil lengkap → terus ke aplikasi pelajar (bukan skrin profil)', (tester) async {
    final h = TestHarness(user: MockUser(uid: 'stu1', email: 'aina@student.test'), signedIn: true);
    await h.saveUser(TestHarness.student());
    await pumpApp(tester, h, const SplashScreen());
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(CompleteProfileScreen), findsNothing);
    expect(find.text('Hi, Nur'), findsOneWidget);
  });

  testWidgets('Dasar Privasi memaparkan semua seksyen dan institusi', (tester) async {
    await pumpApp(tester, TestHarness(), const PrivacyPolicyScreen());
    expect(find.text(PrivacyContent.title), findsOneWidget);
    expect(find.textContaining('KPTM Batu Pahat'), findsWidgets);
    for (final section in PrivacyContent.sections) {
      await tester.scrollUntilVisible(find.text(section.title), 300);
      expect(find.text(section.title), findsOneWidget);
    }
    await tester.scrollUntilVisible(find.text('Summary in English'), 300);
    expect(find.text('Summary in English'), findsOneWidget);
  });

  testWidgets('Padam akaun: wajib taip DELETE, kemudian sahkan semula dengan Google', (tester) async {
    final h = TestHarness(user: MockUser(uid: 'stu1', email: 'aina@student.test'), signedIn: true);
    await h.saveUser(TestHarness.student());
    await pumpApp(tester, h, const DeleteAccountScreen());
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('What will be deleted'), findsOneWidget);
    expect(find.textContaining('sign in with Google again'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('delete_submit')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('delete_submit')));
    await tester.pump();
    expect(find.text('Type DELETE to confirm.'), findsOneWidget);
    expect(await h.users.fetch('stu1'), isNotNull);

    await tester.enterText(find.byKey(const Key('delete_confirm_text')), 'DELETE');
    await tester.tap(find.byKey(const Key('delete_submit')));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.text('Delete forever'));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(h.google.reauthCount, 1);
    expect(await h.users.fetch('stu1'), isNull);
  });

  testWidgets('Pusat Emel: butang "Send test email" menghantar emel ujian sebenar', (tester) async {
    final h = TestHarness(user: MockUser(uid: 'admin1', email: 'admin@myparentcare.com'), signedIn: true);
    await h.saveUser(TestHarness.student(uid: 'admin1', email: 'admin@myparentcare.com').copyWith(role: 'admin'));
    await pumpApp(tester, h, const Scaffold(body: EmailLogsScreen()));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.byKey(const Key('email_test_button')));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byKey(const Key('test_email_to')), findsOneWidget);
    await tester.enterText(find.byKey(const Key('test_email_to')), 'admin@myparentcare.com');
    await tester.tap(find.byKey(const Key('test_email_send')));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Test email sent'), findsOneWidget);
    expect(h.gateway.sent.single.to, 'admin@myparentcare.com');
    expect(h.gateway.sent.single.subject, contains('Emel ujian'));
  });

  testWidgets('Pusat Emel: ralat EmailJS dipaparkan dengan jelas', (tester) async {
    final h = TestHarness(user: MockUser(uid: 'admin1', email: 'admin@myparentcare.com'), signedIn: true);
    await h.saveUser(TestHarness.student(uid: 'admin1', email: 'admin@myparentcare.com').copyWith(role: 'admin'));
    h.gateway
      ..fail = true
      ..error = 'EmailJS menyekat permintaan. Aktifkan "API for non-browser applications"';
    await pumpApp(tester, h, const Scaffold(body: EmailLogsScreen()));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.byKey(const Key('email_test_button')));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.enterText(find.byKey(const Key('test_email_to')), 'admin@myparentcare.com');
    await tester.tap(find.byKey(const Key('test_email_send')));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Test email failed'), findsOneWidget);
    expect(find.textContaining('non-browser'), findsOneWidget);
  });

  testWidgets('Butiran program: emel belum disahkan → tidak boleh sertai', (tester) async {
    final h = TestHarness(
      user: MockUser(uid: 'stu1', email: 'aina@student.test', isEmailVerified: false),
      signedIn: true,
    );
    await h.saveUser(TestHarness.student());
    final program = await h.programs.createProgram(TestHarness.program(), adminUid: 'a');
    await pumpApp(tester, h, ProgramDetailScreen(program: program));
    await tester.pump(const Duration(milliseconds: 300));
    // Lapisan tambahan: akaun tanpa emel disahkan tidak boleh menekan JOIN
    // (akaun Google sentiasa disahkan; rules juga menyemak email_verified).
    expect(find.text('VERIFY EMAIL TO JOIN'), findsOneWidget);
  });

  testWidgets('Butiran program: pelajar disahkan boleh menekan JOIN', (tester) async {
    final h = TestHarness(
      user: MockUser(uid: 'stu1', email: 'aina@student.test', isEmailVerified: true),
      signedIn: true,
    );
    await h.saveUser(TestHarness.student());
    final program = await h.programs.createProgram(TestHarness.program(capacity: 5), adminUid: 'a');
    await pumpApp(tester, h, ProgramDetailScreen(program: program));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('JOIN PROGRAM'), findsOneWidget);
    expect(find.textContaining('5 slots left'), findsOneWidget);
  });

  testWidgets('Backup & restore: backup automatik harian (Apps Script) dipaparkan', (tester) async {
    final h = TestHarness(user: MockUser(uid: 'admin1', email: 'admin@myparentcare.com'), signedIn: true);
    await h.workspace.recordBackup(BackupRecord.fromMap('auto1', {
      'at': DateTime.now().millisecondsSinceEpoch,
      'by': 'apps-script',
      'byEmail': 'admin@myparentcare.com',
      'documents': 16,
      'bytes': 5943,
      'kind': 'backup',
      'note': 'Automatik → Google Drive/MyParentCare Backups/myparentcare_backup_x.json',
    }));
    await pumpApp(tester, h, const BackupScreen());
    expect(find.textContaining('No automatic backup yet'), findsOneWidget);

    final context = tester.element(find.byType(BackupScreen));
    await tester.runAsync(() => context.read<AdminState>().attach(
          const AppUser(uid: 'admin1', email: 'admin@myparentcare.com', role: 'admin', fullName: 'Admin'),
          workspaceReady: true,
        ));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.textContaining('Automatic daily backup is active'), findsOneWidget);
    expect(find.text('Automatic backup · 16 documents'), findsOneWidget);
    expect(find.textContaining('MyParentCare Backups/myparentcare_backup_x.json'), findsOneWidget);
  });

  testWidgets('Log masuk: tiada nota "Pelajar dan admin menggunakan butang yang sama"', (tester) async {
    await pumpApp(tester, TestHarness(), const WelcomeScreen());
    expect(find.textContaining('Pelajar dan admin'), findsNothing);
    expect(find.byKey(const Key('google_sign_in')), findsOneWidget);
  });

  testWidgets('Selepas join: status emel ibu bapa dikemas kini secara langsung (menghantar → dihantar / gagal)', (tester) async {
    final h = TestHarness(
      user: MockUser(uid: 'stu1', email: 'aina@student.test', isEmailVerified: true),
      signedIn: true,
    );
    final student = TestHarness.student();
    await h.saveUser(student);
    final program = await h.programs.createProgram(TestHarness.program(capacity: 5), adminUid: 'a');
    await h.programs.joinProgram(program: program, student: student);
    await pumpApp(tester, h, JoinSuccessScreen(program: program, student: student, emailStatus: 'pending'));
    final context = tester.element(find.byType(JoinSuccessScreen));
    context.read<StudentState>().attach(student.uid);
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.textContaining('Sending the confirmation email to ${student.parentEmail}'), findsOneWidget);

    // fake_cloud_firestore tidak menstrim kemas kini collection group; langgan
    // semula untuk mendapatkan snapshot terkini (Firestore sebenar menstrim terus).
    final ref = h.firestore.doc(FirestorePaths.participant(program.id, student.uid));
    final studentState = context.read<StudentState>();
    Future<void> setStatus(String status) async {
      await tester.runAsync(() async {
        await ref.update({'emailStatus': status});
        studentState
          ..detach()
          ..attach(student.uid);
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    await setStatus('sent');
    expect(find.text('Email sent to ${student.parentEmail}'), findsOneWidget);

    await setStatus('failed');
    expect(find.textContaining('could not be sent'), findsOneWidget);
    expect(find.textContaining('The admin has been notified'), findsOneWidget);
  });

  testWidgets('Email settings: status automasi terhenti & emel segera boleh diaktifkan', (tester) async {
    final h = TestHarness(user: MockUser(uid: 'admin1', email: 'admin@myparentcare.com'), signedIn: true);
    h.workspace.setAutomation(const AutomationStatus(
      ok: false,
      code: '426',
      message: 'Kuota EmailJS telah habis.',
      at: 1759300000000,
    ));
    await pumpApp(tester, h, const EmailSettingsScreen());
    final context = tester.element(find.byType(EmailSettingsScreen));
    await tester.runAsync(() => context.read<AdminState>().attach(
          const AppUser(uid: 'admin1', email: 'admin@myparentcare.com', role: 'admin', fullName: 'Admin'),
          workspaceReady: true,
        ));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.textContaining('Paused since'), findsOneWidget);
    expect(find.textContaining('Kuota EmailJS telah habis.'), findsOneWidget);
    expect(find.textContaining('Instant email is OFF'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('relay_url')), TestHarness.relayUrl);
    await tester.ensureVisible(find.byKey(const Key('relay_save')));
    await tester.tap(find.byKey(const Key('relay_save')));
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.textContaining('Instant email is ON'), findsOneWidget);
    final saved = await tester.runAsync(() => h.firestore.doc('public/config').get());
    expect(saved!.data()!['emailRelayUrl'], TestHarness.relayUrl);
  });
}
