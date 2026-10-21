import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:my_parent_care/database_storage/firestore_paths.dart';
import 'package:my_parent_care/frontend/screens/admin/admin_nav_layout.dart';
import 'package:my_parent_care/frontend/screens/auth/consent_screen.dart';
import 'package:my_parent_care/frontend/screens/auth/splash_screen.dart';
import 'package:my_parent_care/frontend/screens/auth/welcome_screen.dart';
import 'package:my_parent_care/frontend/screens/student/complete_profile_screen.dart';
import 'package:my_parent_care/frontend/screens/student/join_success_screen.dart';
import 'package:my_parent_care/frontend/screens/student/notifications_screen.dart';
import 'package:my_parent_care/frontend/screens/student/student_nav_layout.dart';
import 'package:my_parent_care/main.dart';

import '../support/fakes.dart';
import '../support/widget_harness.dart';

/// UJIAN INTERAKSI PENUH: dua "telefon" – aplikasi ADMIN dan aplikasi PELAJAR –
/// berkongsi satu pangkalan data tiruan dalam memori (bukan production), sama
/// seperti kedua-dua aplikasi sebenar bersambung ke projek Firebase yang sama.
/// Setiap langkah dibuat melalui UI sebenar: log masuk Google, borang, butang.

const programTitle = 'Hari Kerjaya KPTM';

Future<void> openPhone(WidgetTester tester, TestHarness phone, String device) async {
  // Kunci berbeza = aplikasi baharu (Provider/AuthService baharu), seperti
  // membuka aplikasi pada telefon lain.
  await tester.pumpWidget(KeyedSubtree(
    key: ValueKey(device),
    child: MyParentCareApp(services: phone.services(), home: const SplashScreen()),
  ));
  for (var i = 0; i < 25; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  await settle(tester, times: 8);
}

Future<void> navTo(WidgetTester tester, String label) async {
  await tester.pump(const Duration(seconds: 1));
  await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text(label)));
  await settle(tester);
}

/// Tekan butang kembali pada halaman paling atas.
Future<void> goBack(WidgetTester tester) async {
  await tester.tap(find.byType(BackButton).last);
  await tester.pumpAndSettle();
  await settle(tester, times: 2);
}

Future<void> signInWithGoogle(WidgetTester tester) async {
  expect(find.byType(WelcomeScreen), findsOneWidget);
  await tester.tap(find.byKey(const Key('google_sign_in')));
  await settle(tester, times: 10);
}

Future<void> fill(WidgetTester tester, String label, String text) =>
    enterVisible(tester, find.widgetWithText(TextFormField, label), text);

/// Apps Script (web app) tiruan: menandakan emel "sent" dan menulis log,
/// sama seperti skrip sebenar di pelayan Google.
void simulateAppsScript(TestHarness student, FakeFirebaseFirestore db, {bool down = false}) {
  student.relayResponder = (request) {
    if (down) return http.Response('Service unavailable', 503);
    final body = jsonDecode(request.body) as Map<String, dynamic>;
    if (body['action'] == 'join') {
      final ref = db.doc(FirestorePaths.participant(body['programId'] as String, body['uid'] as String));
      unawaited(() async {
        final participant = (await ref.get()).data()!;
        await ref.update({'emailStatus': 'sent', 'emailUpdatedAt': Timestamp.now()});
        await db.collection(FirestorePaths.emailLogs).doc('script-log').set({
          'id': 'script-log',
          'recipient': participant['parentEmail'],
          'subject': 'MyParentCare: Penyertaan ${participant['studentName']} disahkan',
          'body': 'Salam sejahtera,',
          'status': 'sent',
          'errorMessage': '',
          'studentName': participant['studentName'],
          'studentUid': body['uid'],
          'programId': body['programId'],
          'programTitle': participant['programTitle'],
          'type': 'join',
          'createdBy': 'apps-script',
          'createdAt': Timestamp.now(),
          'updatedAt': Timestamp.now(),
          'attempts': 1,
        });
      }());
    }
    return http.Response('{"ok":true,"status":"sent"}', 200);
  };
}

/// Admin log masuk dengan Google (kali pertama) dan menerbitkan program.
Future<void> adminPublishesProgram(WidgetTester tester, TestHarness admin) async {
  await openPhone(tester, admin, 'admin-1');
  await signInWithGoogle(tester);
  expect(find.byType(AdminNavLayout), findsOneWidget, reason: 'super admin terus ke ruang admin');
  expect(find.text('Admin command centre'), findsOneWidget);

  await navTo(tester, 'Programs');
  await tester.tap(find.text('Create program'));
  await settle(tester);
  await enterVisible(tester, find.byKey(const Key('program_title')), programTitle);
  await enterVisible(tester, find.byKey(const Key('program_description')), 'Jumpa majikan dan bina resume.');
  await enterVisible(tester, find.byKey(const Key('program_location')), 'Dewan Utama KPTM');
  await enterVisible(tester, find.byKey(const Key('program_capacity')), '30');
  await tapVisible(tester, find.byKey(const Key('program_save')));
  await settle(tester);
  expect(find.textContaining('Program published to the Student App.'), findsWidgets);
  await tester.pump(const Duration(seconds: 1));
  expect(find.text(programTitle), findsOneWidget);
}

/// Pelajar baharu log masuk dengan Google, setuju Dasar Privasi, lengkapkan
/// profil (wajib) dan sertai program yang diterbitkan admin.
Future<void> studentSignsUpAndJoins(WidgetTester tester, TestHarness student) async {
  await openPhone(tester, student, 'student-1');
  await signInWithGoogle(tester);

  expect(find.byType(ConsentScreen), findsOneWidget);
  expect(find.widgetWithText(TextFormField, 'Nur Aina'), findsOneWidget, reason: 'nama daripada Google');
  await tapVisible(tester, find.byKey(const Key('consent_checkbox')));
  await tapVisible(tester, find.byKey(const Key('consent_continue')));
  await settle(tester, times: 10);

  expect(find.byType(CompleteProfileScreen), findsOneWidget, reason: 'profil wajib sebelum boleh join');
  await fill(tester, 'Matric number', 'KPTM-BP-2026-001');
  await fill(tester, 'Course', 'Diploma Sains Komputer');
  await fill(tester, 'Semester', '3');
  await fill(tester, 'Phone', '0123456789');
  await fill(tester, 'Parent / guardian name', 'Puan Mariam');
  await fill(tester, 'Parent email', 'mariam.ibu@example.com');
  await fill(tester, 'Parent phone', '0198765432');
  await tapVisible(tester, find.widgetWithText(DropdownButtonFormField<String>, 'Relationship'));
  await tester.tap(find.text('Mother').last);
  await settle(tester, times: 2);
  await tapVisible(tester, find.text('SAVE PROFILE'));
  await settle(tester, times: 10);

  expect(find.byType(StudentNavLayout), findsOneWidget);
  await navTo(tester, 'Programs');
  await tapVisible(tester, find.text(programTitle));
  expect(find.text('JOIN PROGRAM'), findsOneWidget);
  await tapVisible(tester, find.byKey(const Key('program_action')));
  expect(find.text('Confirm your place'), findsOneWidget);
  expect(find.text('Dewan Utama KPTM'), findsWidgets);
  await tapVisible(tester, find.text('CONFIRM JOIN'));
  await settle(tester, times: 10);

  expect(find.byType(JoinSuccessScreen), findsOneWidget);
  expect(find.text("You're in!"), findsOneWidget);
  // Telefon pelajar memanggil web app Apps Script SEKALI untuk emel segera.
  expect(student.relayRequests, hasLength(1));
  final call = jsonDecode(student.relayRequests.single.body) as Map;
  expect(call['action'], 'join');
  expect(call['uid'], 'stu-aina');
}

/// Dua telefon berkongsi satu pangkalan data TIRUAN dalam memori.
/// `admin()` / `student()` mencipta aplikasi pada telefon itu; `signedIn: true`
/// = aplikasi dibuka semula selepas log masuk (sesi Google disimpan).
class Phones {
  final db = FakeFirebaseFirestore();
  final workspace = InMemoryAdminWorkspace()..emailJsKey = 'k' * 20;

  TestHarness admin({bool signedIn = false}) => TestHarness(
        user: MockUser(uid: 'admin-kptm', email: 'admin@myparentcare.com', displayName: 'Pentadbir KPTM', isEmailVerified: true),
        signedIn: signedIn,
        firestore: db,
        workspace: workspace,
      );

  TestHarness student({bool signedIn = false}) => TestHarness(
        user: MockUser(uid: 'stu-aina', email: 'aina@student.test', displayName: 'Nur Aina', isEmailVerified: true),
        signedIn: signedIn,
        firestore: db,
      );
}

void main() {
  setUp(setUpWidgetTest);

  testWidgets('admin terbit program → pelajar daftar & join → emel segera → admin lihat peserta & batal → pelajar dimaklumkan',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.6;
    addTearDown(tester.view.reset);
    final phones = Phones();
    final db = phones.db;
    final student = phones.student();
    await student.enableInstantEmail();
    simulateAppsScript(student, db);

    // 1. ADMIN
    await adminPublishesProgram(tester, phones.admin());

    // 2. PELAJAR
    await studentSignsUpAndJoins(tester, student);
    await settle(tester, times: 6);
    final pid = (await db.collection(FirestorePaths.programs).get()).docs.single.id;
    final joined = (await db.doc(FirestorePaths.participant(pid, 'stu-aina')).get()).data()!;
    expect(joined['parentEmail'], 'mariam.ibu@example.com');
    expect(joined['emailStatus'], 'sent', reason: 'emel dihantar serta-merta oleh web app');
    await tapVisible(tester, find.text('VIEW MY JOINED PROGRAMS'));
    expect(find.text(programTitle), findsWidgets);

    // 3. ADMIN (telefon admin dibuka semula – masih log masuk)
    await openPhone(tester, phones.admin(signedIn: true), 'admin-2');
    expect(find.byType(AdminNavLayout), findsOneWidget);
    await navTo(tester, 'Programs');
    await tapVisible(tester, find.text(programTitle));
    await tapVisible(tester, find.text('VIEW PARTICIPANTS (1)'));
    expect(find.text('Nur Aina'), findsOneWidget);
    expect(find.text('SENT'), findsOneWidget, reason: 'status emel ibu bapa');
    await goBack(tester);

    await tester.tap(find.byTooltip('Program actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel program').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Cancellation reason'), 'Penceramah tidak dapat hadir');
    await tester.tap(find.widgetWithText(FilledButton, 'Cancel program'));
    await settle(tester, times: 8);
    expect(find.textContaining('1 students notified'), findsWidgets);

    await goBack(tester);
    await navTo(tester, 'Email');
    expect(find.text('mariam.ibu@example.com'), findsWidgets, reason: 'log emel daripada Apps Script');

    // 4. PELAJAR menerima notifikasi pembatalan
    await openPhone(tester, phones.student(signedIn: true), 'student-2');
    expect(find.byType(StudentNavLayout), findsOneWidget);
    await tester.tap(find.byTooltip('Notifications'));
    await settle(tester, times: 8);
    expect(find.byType(NotificationsScreen), findsOneWidget);
    expect(find.text('Program dibatalkan'), findsOneWidget);
    expect(find.textContaining('Penceramah tidak dapat hadir'), findsOneWidget);
    await tester.tap(find.text('Program dibatalkan'));
    await settle(tester);
    final note = (await db.collection(FirestorePaths.userNotifications('stu-aina')).get()).docs.single.data();
    expect(note['isRead'], isTrue);

    await goBack(tester);
    await navTo(tester, 'Joined');
    await tester.tap(find.text('Cancelled'));
    await settle(tester);
    expect(find.text(programTitle), findsWidgets);
  });

  testWidgets('emel segera gagal (pelayan Google tidak menjawab) → admin hantar → gagal → pelajar diberitahu',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.6;
    addTearDown(tester.view.reset);
    final phones = Phones();
    final db = phones.db;
    final student = phones.student();
    await student.enableInstantEmail();
    simulateAppsScript(student, db, down: true);

    await adminPublishesProgram(tester, phones.admin());
    await studentSignsUpAndJoins(tester, student);
    expect(find.textContaining('Sending the confirmation email to mariam.ibu@example.com'), findsOneWidget,
        reason: 'emel kekal "pending" – sandaran akan menghantarnya');

    // Admin: pengesahan tertangguh dihantar dari Pusat Emel, tetapi EmailJS menolak.
    final admin = phones.admin(signedIn: true);
    await openPhone(tester, admin, 'admin-2');
    admin.gateway
      ..fail = true
      ..error = 'EmailJS menolak permintaan (templat/ID salah): invalid address';
    await navTo(tester, 'Email');
    await tapVisible(tester, find.text('Pending confirmations (1)'));
    await settle(tester, times: 8);
    final pid = (await db.collection(FirestorePaths.programs).get()).docs.single.id;
    expect((await db.doc(FirestorePaths.participant(pid, 'stu-aina')).get()).data()!['emailStatus'], 'failed');
    await tester.tap(find.widgetWithText(ChoiceChip, 'FAILED'));
    await settle(tester);
    expect(find.text('mariam.ibu@example.com'), findsOneWidget, reason: 'admin nampak emel gagal + sebab');

    // Pelajar: notifikasi kegagalan & petunjuk semak emel ibu bapa.
    await openPhone(tester, phones.student(signedIn: true), 'student-2');
    await tester.tap(find.byTooltip('Notifications'));
    await settle(tester, times: 8);
    expect(find.text('Emel kepada ibu bapa gagal dihantar'), findsOneWidget);
    expect(find.textContaining('Alamat emel ibu bapa mungkin tidak sah'), findsOneWidget);
  });
}
