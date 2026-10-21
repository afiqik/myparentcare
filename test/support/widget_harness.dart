import 'dart:io';

import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_parent_care/auth/auth_service.dart';
import 'package:my_parent_care/backend_logic/admin_state.dart';
import 'package:my_parent_care/backend_logic/student_state.dart';
import 'package:my_parent_care/main.dart';
import 'package:my_parent_care/rate_limiting/rate_limiter.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_http_images.dart';
import 'fakes.dart';
import 'platform_fakes.dart';

/// Persediaan standard setiap ujian widget.
PlatformFakes setUpWidgetTest() {
  HttpOverrides.global = FakeImageHttpOverrides();
  RateLimiter.resetAll();
  SharedPreferences.setMockInitialValues({'onboarding_done': true});
  PackageInfo.setMockInitialValues(
    appName: 'MyParentCare',
    packageName: 'com.myparentcare.my_parent_care',
    version: '1.0.0',
    buildNumber: '6',
    buildSignature: '',
  );
  return PlatformFakes.install();
}

/// Akaun admin (super admin secara lalai) yang sudah log masuk dengan Google.
Future<TestHarness> adminHarness({bool superAdmin = true, String uid = 'admin1'}) async {
  final email = superAdmin ? 'admin@myparentcare.com' : 'staff@kptm.test';
  final h = TestHarness(
    user: MockUser(uid: uid, email: email, displayName: 'Admin KPTM', isEmailVerified: true),
    signedIn: true,
  );
  await h.saveUser(
    TestHarness.student(uid: uid, email: email, fullName: 'Admin KPTM').copyWith(role: 'admin'),
  );
  h.workspace.admins.add(uid);
  h.workspace.emailJsKey = 'k' * 20;
  return h;
}

/// Pelajar lengkap yang sudah log masuk.
Future<TestHarness> studentHarness({String uid = 'stu1'}) async {
  final h = TestHarness(
    user: MockUser(uid: uid, email: 'aina@student.test', displayName: 'Nur Aina', isEmailVerified: true),
    signedIn: true,
  );
  await h.saveUser(TestHarness.student(uid: uid));
  return h;
}

/// Tunggu kerja async sebenar (Firestore tiruan, strim) dan lukis semula.
Future<void> settle(WidgetTester tester, {int times = 6}) async {
  for (var i = 0; i < times; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 15)));
    await tester.pump(const Duration(milliseconds: 60));
  }
}

/// Lukis [screen] dalam aplikasi penuh (Provider sebenar) selepas sesi log
/// masuk dimuatkan – sama seperti aplikasi sebenar. [attachAdmin] menyambung
/// AdminState (program, audit, backup) seperti AdminNavLayout.
Future<void> pumpScreen(
  WidgetTester tester,
  TestHarness h,
  Widget screen, {
  bool attachAdmin = false,
  bool attachStudent = false,
  bool workspaceReady = true,
}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.6;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MyParentCareApp(
    services: h.services(),
    home: _AfterSignIn(
      attachAdmin: attachAdmin,
      attachStudent: attachStudent,
      workspaceReady: workspaceReady,
      child: screen,
    ),
  ));
  await settle(tester, times: 8);
}

class _AfterSignIn extends StatefulWidget {
  final Widget child;
  final bool attachAdmin;
  final bool attachStudent;
  final bool workspaceReady;

  const _AfterSignIn({
    required this.child,
    required this.attachAdmin,
    required this.attachStudent,
    required this.workspaceReady,
  });

  @override
  State<_AfterSignIn> createState() => _AfterSignInState();
}

class _AfterSignInState extends State<_AfterSignIn> {
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final auth = context.read<AuthService>();
      final admin = context.read<AdminState>();
      final student = context.read<StudentState>();
      await auth.initializationComplete;
      final user = auth.currentUser;
      if (widget.attachAdmin && user != null) {
        await admin.attach(user, workspaceReady: widget.workspaceReady);
      }
      if (widget.attachStudent && user != null) student.attach(user.uid);
      if (mounted) setState(() => _ready = true);
    });
  }

  @override
  Widget build(BuildContext context) =>
      _ready ? widget.child : const Scaffold(body: SizedBox.shrink());
}

/// Skrin yang dibuka dengan Navigator.push (supaya Navigator.pop boleh diuji).
class Launcher extends StatelessWidget {
  final WidgetBuilder builder;

  const Launcher({super.key, required this.builder});

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            key: const Key('launch'),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: builder)),
            child: const Text('LAUNCH'),
          ),
        ),
      );
}

/// Tatal senarai utama sehingga [finder] dibina dan kelihatan (ListView
/// hanya membina item berhampiran skrin).
Future<void> scrollTo(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    final vertical = find.byWidgetPredicate(
      (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
    );
    if (vertical.evaluate().isNotEmpty) {
      final scrollable = vertical.first;
      // Item mungkin di atas kedudukan semasa: kembali ke atas dahulu.
      await tester.drag(scrollable, const Offset(0, 20000));
      await tester.pump();
      for (var i = 0; i < 60 && finder.evaluate().isEmpty; i++) {
        await tester.drag(scrollable, const Offset(0, -250));
        await tester.pump(const Duration(milliseconds: 50));
      }
    }
  }
  await tester.ensureVisible(finder.first);
  await tester.pump();
}

/// Snackbar beratur – buang yang sedang dipaparkan supaya mesej seterusnya
/// kelihatan serta-merta.
Future<void> clearSnackBars(WidgetTester tester) async {
  final messenger = tester.state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger).first);
  messenger.clearSnackBars();
  await tester.pump(const Duration(milliseconds: 400));
}

/// Tekan widget selepas memastikan ia kelihatan (senarai panjang).
Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await scrollTo(tester, finder);
  await tester.tap(finder.first);
  await settle(tester, times: 4);
}

/// Taip ke dalam medan selepas menatal kepadanya.
Future<void> enterVisible(WidgetTester tester, Finder finder, String text) async {
  await scrollTo(tester, finder);
  await tester.enterText(finder.first, text);
  await tester.pump();
}
