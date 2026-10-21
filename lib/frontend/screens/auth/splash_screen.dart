import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../app_config.dart';
import '../../../auth/auth_service.dart';
import '../../navigation.dart';
import '../../theme.dart';
import 'onboarding_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _route();
  }

  Future<void> _route() async {
    final stopwatch = Stopwatch()..start();
    final auth = context.read<AuthService>();

    try {
      await auth.initializationComplete.timeout(const Duration(seconds: 8));
      // Tunggu profil dimuatkan (atau disahkan tiada) selepas sesi dipulihkan.
      final deadline = DateTime.now().add(const Duration(seconds: 8));
      while (auth.stage == AuthStage.loading && DateTime.now().isBefore(deadline)) {
        await Future.delayed(const Duration(milliseconds: 100));
      }
    } catch (_) {
      debugPrint('Auth initialization timed out.');
    }

    var onboardingDone = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      onboardingDone = prefs.getBool('onboarding_done') ?? false;
    } catch (_) {}

    final elapsed = stopwatch.elapsedMilliseconds;
    if (elapsed < 1200) {
      await Future.delayed(Duration(milliseconds: 1200 - elapsed));
    }
    if (!mounted) return;

    if (!onboardingDone && auth.stage == AuthStage.signedOut) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const OnboardingScreen()),
      );
      return;
    }
    goHome(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: AppTheme.primaryGradient,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 104,
                height: 104,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(30),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(22),
                  child: Image.asset(
                    'assets/images/launcher_icon.png',
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              const SizedBox(height: 22),
              const Text(
                'MyParentCare',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.8,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Program pelajar, ibu bapa sentiasa tahu.',
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
                ),
                child: const Text(
                  AppConfig.audienceTagline,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: 34),
              const SizedBox(
                width: 26,
                height: 26,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2.4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
