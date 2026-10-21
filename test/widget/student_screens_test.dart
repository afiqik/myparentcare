import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:my_parent_care/app_config.dart';
import 'package:my_parent_care/database_storage/firestore_paths.dart';
import 'package:my_parent_care/database_storage/models.dart';
import 'package:my_parent_care/frontend/screens/auth/consent_screen.dart';
import 'package:my_parent_care/frontend/screens/auth/onboarding_screen.dart';
import 'package:my_parent_care/frontend/screens/auth/splash_screen.dart';
import 'package:my_parent_care/frontend/screens/auth/suspended_screen.dart';
import 'package:my_parent_care/frontend/screens/auth/welcome_screen.dart';
import 'package:my_parent_care/frontend/screens/legal/privacy_policy_screen.dart';
import 'package:my_parent_care/frontend/screens/student/complete_profile_screen.dart';
import 'package:my_parent_care/frontend/screens/student/delete_account_screen.dart';
import 'package:my_parent_care/frontend/screens/student/notifications_screen.dart';
import 'package:my_parent_care/frontend/screens/student/program_detail_screen.dart';
import 'package:my_parent_care/frontend/screens/student/program_list_screen.dart';
import 'package:my_parent_care/frontend/screens/student/student_nav_layout.dart';
import 'package:my_parent_care/main.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fakes.dart';
import '../support/platform_fakes.dart';
import '../support/widget_harness.dart';

Future<void> navTo(WidgetTester tester, String label) async {
  await tester.pump(const Duration(seconds: 1));
  await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text(label)));
  await settle(tester);
}

/// Aplikasi sebenar dari SplashScreen (penghalaan ikut keadaan akaun).
Future<void> startApp(WidgetTester tester, TestHarness h) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.6;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MyParentCareApp(services: h.services(), home: const SplashScreen()));
  for (var i = 0; i < 25; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  await settle(tester, times: 8);
}

void main() {
  late PlatformFakes fakes;

  setUp(() => fakes = setUpWidgetTest());

  // ================================================================ masuk aplikasi

  group('Pelajar: masuk aplikasi', () {
    testWidgets('kali pertama: onboarding → Seterusnya hingga akhir → skrin log masuk', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await startApp(tester, TestHarness());
      expect(find.byType(OnboardingScreen), findsOneWidget);
      for (var i = 0; i < 6 && find.byType(OnboardingScreen).evaluate().isNotEmpty; i++) {
        await tester.tap(find.byType(IconButton).last);
        await tester.pumpAndSettle();
      }
      expect(find.byType(WelcomeScreen), findsOneWidget);
      expect((await SharedPreferences.getInstance()).getBool('onboarding_done'), isTrue);
    });

    testWidgets('onboarding boleh dilangkau', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await startApp(tester, TestHarness());
      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();
      expect(find.byType(WelcomeScreen), findsOneWidget);
    });

    testWidgets('akaun digantung → skrin "Account suspended" → log keluar', (tester) async {
      final h = await studentHarness();
      await h.saveUser(TestHarness.student().copyWith(status: 'suspended'));
      await startApp(tester, h);
      expect(find.byType(SuspendedScreen), findsOneWidget);
      expect(find.textContaining(AppConfig.supportEmail), findsOneWidget);
      await tester.tap(find.text('Sign out'));
      await settle(tester);
      expect(find.byType(WelcomeScreen), findsOneWidget);
      expect(h.auth.currentUser, isNull);
    });

    testWidgets('Dasar Privasi baharu → setuju semula → terus ke aplikasi', (tester) async {
      final h = await studentHarness();
      await h.saveUser(TestHarness.student().copyWith(privacyVersion: '2020-01-01'));
      await startApp(tester, h);
      expect(find.byType(ConsentScreen), findsOneWidget);
      await tapVisible(tester, find.byKey(const Key('consent_checkbox')));
      await tapVisible(tester, find.byKey(const Key('consent_continue')));
      await settle(tester, times: 8);
      expect(find.byType(StudentNavLayout), findsOneWidget);
      expect((await h.users.fetch('stu1'))!.privacyVersion, AppConfig.privacyPolicyVersion);
    });

    testWidgets('tanpa internet → jalur "Luar talian" dipaparkan', (tester) async {
      final h = await studentHarness();
      await startApp(tester, h);
      final connectivity = tester.element(find.byType(StudentNavLayout)).read<AppServices>().connectivity;
      // Terputus sekejap (< 4 saat) → tiada jalur (elak berkelip).
      connectivity.reportFirestore(online: false);
      await tester.pump(const Duration(seconds: 2));
      connectivity.reportFirestore(online: true);
      await tester.pump(const Duration(seconds: 3));
      expect(find.textContaining('Luar talian'), findsNothing);
      // Terputus lama → jalur dipaparkan; sambung semula → hilang.
      connectivity.reportFirestore(online: false);
      await tester.pump(const Duration(seconds: 5));
      expect(find.textContaining('Luar talian'), findsOneWidget);
      connectivity.reportFirestore(online: true);
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.textContaining('Luar talian'), findsNothing);
    });
  });

  // ================================================================ utama & program

  group('Pelajar: utama & senarai program', () {
    Future<TestHarness> withPrograms() async {
      final h = await studentHarness();
      await h.programs.createProgram(
        TestHarness.program(title: 'Hari Kerjaya').copyWith(category: 'Career'),
        adminUid: 'admin1',
      );
      await h.programs.createProgram(
        TestHarness.program(title: 'Futsal Malam').copyWith(category: 'Sports', location: 'Gelanggang'),
        adminUid: 'admin1',
      );
      return h;
    }

    testWidgets('sapaan, "Open now", akses pantas ke Programs & Joined', (tester) async {
      final h = await withPrograms();
      await startApp(tester, h);
      expect(find.text('Hi, Nur'), findsOneWidget);
      await scrollTo(tester, find.text('Hari Kerjaya'));
      expect(find.text('Hari Kerjaya'), findsOneWidget);

      await tapVisible(tester, find.text('Browse'));
      expect(find.text('Futsal Malam'), findsOneWidget);
      await navTo(tester, 'Home');
      await tapVisible(tester, find.text('Joined'));
      expect(find.text('Upcoming'), findsOneWidget);
    });

    testWidgets('tiada program terbuka → mesej kosong', (tester) async {
      final h = await studentHarness();
      await startApp(tester, h);
      await scrollTo(tester, find.text('Belum ada program terbuka'));
      expect(find.text('Belum ada program terbuka'), findsOneWidget);
      await tapVisible(tester, find.text('Refresh programs'));
    });

    testWidgets('cari & tapis kategori; tiada padanan', (tester) async {
      final h = await withPrograms();
      await startApp(tester, h);
      await navTo(tester, 'Programs');
      expect(find.text('Hari Kerjaya'), findsOneWidget);
      expect(find.text('Futsal Malam'), findsOneWidget);

      await tester.enterText(find.widgetWithText(TextField, 'Search by title or location'), 'gelanggang');
      await settle(tester, times: 2);
      expect(find.text('Futsal Malam'), findsOneWidget);
      expect(find.text('Hari Kerjaya'), findsNothing);
      await tester.enterText(find.byType(TextField).first, '');
      await settle(tester, times: 2);

      await tester.tap(find.widgetWithText(ChoiceChip, 'Career'));
      await settle(tester, times: 2);
      expect(find.text('Hari Kerjaya'), findsOneWidget);
      expect(find.text('Futsal Malam'), findsNothing);
      await tester.scrollUntilVisible(
        find.widgetWithText(ChoiceChip, 'Volunteer'),
        150,
        scrollable: find.descendant(
          of: find.byType(ProgramListScreen),
          matching: find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.right),
        ).last, // .first ialah kotak carian (TextField juga boleh ditatal mendatar)
      );
      await tester.tap(find.widgetWithText(ChoiceChip, 'Volunteer'));
      await settle(tester, times: 2);
      expect(find.text('No matching programs'), findsOneWidget);
    });

    testWidgets('butiran program: penuh, ditutup, dibatalkan, sudah join', (tester) async {
      final h = await studentHarness();
      final full = await h.programs.createProgram(TestHarness.program(title: 'Penuh', capacity: 1), adminUid: 'a');
      await h.programs.joinProgram(program: full, student: TestHarness.student(uid: 'lain'));
      // Disertai sebelum aplikasi dibuka (strim collection group tiruan hanya
      // menghantar snapshot awal).
      final open = await h.programs.createProgram(TestHarness.program(title: 'Terbuka', capacity: 5), adminUid: 'a');
      await h.programs.joinProgram(program: open, student: TestHarness.student());
      Future<void> showDetail(Program program) async {
        await pumpScreen(tester, h, ProgramDetailScreen(program: program), attachStudent: true);
      }

      await showDetail(full.copyWith(joinedCount: 1));
      expect(find.text('PROGRAM FULL'), findsOneWidget);

      // Skrin memaparkan data terkini daripada katalog (bukan salinan lama).
      final closed = await h.programs.createProgram(TestHarness.program(title: 'Ditutup'), adminUid: 'a');
      await h.programs.setStatus(closed, 'closed');
      final cancelled = await h.programs.createProgram(TestHarness.program(title: 'Batal'), adminUid: 'a');
      await h.programs.setStatus(cancelled, 'cancelled', reason: 'Hujan');
      await showDetail(closed);
      expect(find.text('REGISTRATION CLOSED'), findsOneWidget);
      await showDetail(cancelled);
      expect(find.text('PROGRAM CANCELLED'), findsOneWidget);

      await showDetail(open);
      expect(find.text('ALREADY JOINED'), findsOneWidget);
    });
  });

  // ================================================================ program saya

  group('Pelajar: program yang disertai', () {
    testWidgets('tab Upcoming / Completed / Cancelled mengikut status program', (tester) async {
      final h = await studentHarness();
      Future<void> join(String title, String finalStatus) async {
        final p = await h.programs.createProgram(TestHarness.program(title: title, capacity: 5), adminUid: 'a');
        await h.programs.joinProgram(program: p, student: TestHarness.student());
        if (finalStatus != 'open') await h.programs.setStatus(p, finalStatus, reason: 'Sebab ujian');
      }

      await join('Akan Datang', 'open');
      await join('Sudah Selesai', 'completed');
      await join('Dibatalkan Admin', 'cancelled');
      await startApp(tester, h);
      await navTo(tester, 'Joined');
      expect(find.text('Akan Datang'), findsOneWidget);
      expect(find.textContaining('Parent email: pending'), findsOneWidget);

      await tester.tap(find.text('Completed'));
      await settle(tester);
      expect(find.text('Sudah Selesai'), findsOneWidget);
      await tester.tap(find.text('Cancelled'));
      await settle(tester);
      expect(find.text('Dibatalkan Admin'), findsOneWidget);
    });

    testWidgets('belum join apa-apa → mesej kosong', (tester) async {
      await startApp(tester, await studentHarness());
      await navTo(tester, 'Joined');
      expect(find.text('No upcoming programs'), findsOneWidget);
    });
  });

  // ================================================================ notifikasi

  group('Pelajar: notifikasi', () {
    testWidgets('lencana belum dibaca, pengumuman, tekan untuk tanda dibaca', (tester) async {
      final h = await studentHarness();
      final program = await h.programs.createProgram(TestHarness.program(title: 'Seminar'), adminUid: 'a');
      await h.programs.joinProgram(program: program, student: TestHarness.student());
      await h.programs.notifyParticipants(
        participants: await h.programs.fetchParticipants(program.id),
        type: 'cancelled',
        title: 'Program dibatalkan',
        message: 'Seminar dibatalkan. Sebab: Hujan',
        programId: program.id,
      );
      await h.programs.addAnnouncement(Announcement(
        id: 'an1',
        title: 'Cuti Semester',
        message: 'Kampus ditutup minggu depan.',
        createdAt: DateTime.now().toIso8601String(),
      ));
      await startApp(tester, h);
      expect(find.descendant(of: find.byType(AppBar), matching: find.text('1')), findsOneWidget);

      await tester.tap(find.byTooltip('Notifications'));
      await settle(tester, times: 8);
      expect(find.byType(NotificationsScreen), findsOneWidget);
      expect(find.text('Cuti Semester'), findsOneWidget);
      expect(find.text('Program dibatalkan'), findsOneWidget);
      await tester.tap(find.text('Program dibatalkan'));
      await settle(tester);
      final note = (await h.firestore.collection(FirestorePaths.userNotifications('stu1')).get()).docs.single;
      expect(note.data()['isRead'], isTrue);
    });

    testWidgets('tiada notifikasi → "All caught up"', (tester) async {
      await startApp(tester, await studentHarness());
      await tester.tap(find.byTooltip('Notifications'));
      await settle(tester, times: 8);
      expect(find.text('All caught up'), findsOneWidget);
    });
  });

  // ================================================================ profil

  group('Pelajar: profil', () {
    testWidgets('maklumat dipaparkan; edit profil menyimpan perubahan', (tester) async {
      final h = await studentHarness();
      await startApp(tester, h);
      await navTo(tester, 'Profile');
      expect(find.text('Profile ready'), findsOneWidget);
      expect(find.text('KPTM12345'), findsOneWidget);
      expect(find.text('Puan Mariam'), findsOneWidget);

      await tapVisible(tester, find.text('EDIT PROFILE'));
      expect(find.byType(CompleteProfileScreen), findsOneWidget);
      await enterVisible(tester, find.widgetWithText(TextFormField, 'Phone').first, '0111222333');
      await tapVisible(tester, find.text('SAVE PROFILE'));
      await settle(tester, times: 6);
      expect(find.text('Profile and parent information saved.'), findsWidgets);
      expect((await h.users.fetch('stu1'))!.phone, '0111222333');
    });

    testWidgets('emel ibu bapa tidak boleh sama dengan emel pelajar', (tester) async {
      final h = await studentHarness();
      await startApp(tester, h);
      await navTo(tester, 'Profile');
      await tapVisible(tester, find.text('EDIT PROFILE'));
      await enterVisible(tester, find.widgetWithText(TextFormField, 'Parent email'), 'aina@student.test');
      await tapVisible(tester, find.text('SAVE PROFILE'));
      await settle(tester, times: 4);
      expect(find.text('Parent email must be different from your own email.'), findsOneWidget);
      expect((await h.users.fetch('stu1'))!.parentEmail, 'parent.stu1@example.com');
    });

    testWidgets('pautan Dasar Privasi, bantuan & padam akaun', (tester) async {
      final h = await studentHarness();
      await startApp(tester, h);
      await navTo(tester, 'Profile');
      await scrollTo(tester, find.text(AppConfig.supportEmail));
      expect(find.text(AppConfig.supportEmail), findsOneWidget);
      await tapVisible(tester, find.text('Privacy Policy'));
      expect(find.byType(PrivacyPolicyScreen), findsOneWidget);
      await tester.tap(find.byType(BackButton).last);
      await tester.pumpAndSettle();
      await tapVisible(tester, find.byKey(const Key('profile_delete_account')));
      expect(find.byType(DeleteAccountScreen), findsOneWidget);
    });
  });

  // ================================================================ media

  group('Pelajar: gambar & video program', () {
    testWidgets('gambar dari Firestore & video YouTube; tekan video membuka pautan', (tester) async {
      final h = await studentHarness();
      final image = await h.media.uploadImage(
        bytes: Uint8List.fromList(img.encodePng(img.Image(width: 4, height: 4))),
        programId: 'p-media',
        adminUid: 'admin1',
      );
      final video = await h.media.addVideoLink(
        url: 'https://youtu.be/dQw4w9WgXcQ',
        programId: 'p-media',
        adminUid: 'admin1',
        caption: 'Video promosi',
      );
      final program = TestHarness.program(title: 'Bermedia').copyWith(
        id: 'p-media',
        coverMediaId: image.id,
        gallery: [image.toRef(), video.toRef()],
      );
      await pumpScreen(tester, h, ProgramDetailScreen(program: program), attachStudent: true);
      await scrollTo(tester, find.text('Video promosi'));
      expect(find.text('Gallery'), findsOneWidget);
      expect(find.byType(Image), findsWidgets);

      await tester.tap(find.text('Video promosi'));
      await settle(tester);
      expect(fakes.urlLauncher.launched.single, 'https://youtu.be/dQw4w9WgXcQ');

      fakes.urlLauncher.succeed = false;
      await tester.tap(find.text('Video promosi'));
      await settle(tester);
      expect(find.text('Could not open the link.'), findsOneWidget);
    });
  });
}
