import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../auth/auth_service.dart';
import '../backend_logic/admin_state.dart';
import '../backend_logic/student_state.dart';
import 'screens/admin/admin_nav_layout.dart';
import 'screens/auth/consent_screen.dart';
import 'screens/auth/suspended_screen.dart';
import 'screens/auth/welcome_screen.dart';
import 'screens/student/complete_profile_screen.dart';
import 'screens/student/student_nav_layout.dart';

/// Skrin utama yang betul berdasarkan keadaan akaun semasa.
Widget homeForAuth(AuthService auth) {
  switch (auth.stage) {
    case AuthStage.loading:
    case AuthStage.signedOut:
      return const WelcomeScreen();
    case AuthStage.needsProfile:
      return const ConsentScreen(mode: ConsentMode.createProfile);
    case AuthStage.needsConsent:
      return const ConsentScreen(mode: ConsentMode.renew);
    case AuthStage.suspended:
      return const SuspendedScreen();
    case AuthStage.ready:
      final user = auth.currentUser!;
      if (user.isAdmin) return const AdminNavLayout();
      if (!user.canJoinPrograms) {
        return const CompleteProfileScreen(firstSetup: true);
      }
      return const StudentNavLayout();
  }
}

/// Ganti keseluruhan timbunan navigasi dengan skrin utama yang betul.
void goHome(BuildContext context) {
  final auth = context.read<AuthService>();
  Navigator.of(context).pushAndRemoveUntil(
    MaterialPageRoute(builder: (_) => homeForAuth(auth)),
    (_) => false,
  );
}

Future<void> signOutAndGoHome(BuildContext context) async {
  final auth = context.read<AuthService>();
  context.read<StudentState>().detach();
  await context.read<AdminState>().detach();
  await auth.signOut();
  if (!context.mounted) return;
  Navigator.of(context).pushAndRemoveUntil(
    MaterialPageRoute(builder: (_) => const WelcomeScreen()),
    (_) => false,
  );
}
