import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app_config.dart';
import '../../../auth/auth_service.dart';
import '../../../core/errors.dart';
import '../../navigation.dart';
import '../../theme.dart';
import '../../widgets/app_components.dart';
import '../legal/privacy_policy_screen.dart';

/// Skrin utama sebelum log masuk. Pelajar DAN admin log masuk dengan Google
/// sahaja – peranan dikenal pasti secara automatik selepas log masuk.
class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  String _error = '';

  Future<void> _signIn() async {
    setState(() => _error = '');
    final auth = context.read<AuthService>();
    try {
      await auth.signInWithGoogle();
      if (!mounted || auth.firebaseUser == null) return; // dibatalkan
      goHome(context);
    } catch (error) {
      if (mounted) setState(() => _error = friendlyError(error, google: true));
    }
  }

  @override
  Widget build(BuildContext context) {
    final loading = context.watch<AuthService>().isLoading;
    return Scaffold(
      body: SafeArea(
        child: PageBackdrop(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(22, 22, 22, 28),
            children: [
              const AppMark(size: 44),
              const SizedBox(height: 18),
              Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: AppTheme.cobalt.withValues(alpha: 0.09),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.school_rounded, size: 16, color: AppTheme.cobalt),
                      SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          AppConfig.audienceTagline,
                          style: TextStyle(
                            color: AppTheme.cobalt,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Programs that\nkeep family close.',
                style: Theme.of(
                  context,
                ).textTheme.displaySmall?.copyWith(fontSize: 42),
              ),
              const SizedBox(height: 14),
              Text(
                'Students join with one clear confirmation. Parents receive the details automatically.',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 30),
              Container(
                height: 250,
                decoration: BoxDecoration(
                  color: AppTheme.ink,
                  borderRadius: BorderRadius.circular(30),
                ),
                child: Stack(
                  children: [
                    Positioned(
                      right: -28,
                      top: -34,
                      child: Container(
                        width: 180,
                        height: 180,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: [AppTheme.coral, AppTheme.orange],
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: -32,
                      bottom: -52,
                      child: Container(
                        width: 190,
                        height: 190,
                        decoration: BoxDecoration(
                          color: AppTheme.cobalt.withValues(alpha: 0.8),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    const Positioned(
                      left: 30,
                      top: 34,
                      child: Icon(
                        Icons.school_rounded,
                        color: Colors.white,
                        size: 72,
                      ),
                    ),
                    const Positioned(
                      right: 32,
                      bottom: 34,
                      child: Icon(
                        Icons.family_restroom_rounded,
                        color: Colors.white,
                        size: 76,
                      ),
                    ),
                    Positioned(
                      left: 98,
                      top: 100,
                      child: Container(
                        width: 76,
                        height: 76,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: const Icon(
                          Icons.mark_email_read_rounded,
                          color: AppTheme.violet,
                          size: 36,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 30),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: const Key('google_sign_in'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.ink,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  onPressed: loading ? null : _signIn,
                  child: loading
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 26,
                              height: 26,
                              alignment: Alignment.center,
                              decoration: const BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                              ),
                              child: const Text(
                                'G',
                                style: TextStyle(
                                  color: AppTheme.cobalt,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            const Text('Log masuk dengan Google'),
                          ],
                        ),
                ),
              ),
              if (_error.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  _error,
                  key: const Key('sign_in_error'),
                  style: const TextStyle(
                    color: AppTheme.error,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              const SizedBox(height: 14),
              TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const PrivacyPolicyScreen()),
                ),
                child: const Text(
                  'Privacy Policy',
                  style: TextStyle(color: AppTheme.inkSoft, fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
