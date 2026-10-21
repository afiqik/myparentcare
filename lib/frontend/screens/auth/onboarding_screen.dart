import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../theme.dart';
import '../../widgets/glass_card.dart';
import 'welcome_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  final List<OnboardingData> _onboardingPages = [
    OnboardingData(
      title: 'Connect',
      subtitle:
          'Bridging the gap between KPTM students, parents, and campus activities.',
      imagePath: 'assets/images/logo.jpg',
      gradient: AppTheme.primaryGradient,
    ),
    OnboardingData(
      title: 'Communicate',
      subtitle:
          'Instant updates, program notifications, and direct access for parents.',
      icon: Icons.chat_bubble_outline_rounded,
      gradient: AppTheme.secondaryGradient,
    ),
    OnboardingData(
      title: 'Care Together',
      subtitle: 'Building a safer, more engaged community for student success.',
      icon: Icons.favorite_border_rounded,
      gradient: AppTheme.accentGradient,
    ),
  ];

  Future<void> _completeOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_done', true);
    if (!mounted) return;
    Navigator.of(
      context,
    ).pushReplacement(MaterialPageRoute(builder: (_) => const WelcomeScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Background Gradient matching current page
          AnimatedContainer(
            duration: const Duration(milliseconds: 500),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: _onboardingPages[_currentPage].gradient,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),

          // Page View
          PageView.builder(
            controller: _pageController,
            onPageChanged: (index) {
              setState(() {
                _currentPage = index;
              });
            },
            itemCount: _onboardingPages.length,
            itemBuilder: (context, index) {
              final page = _onboardingPages[index];
              return SafeArea(
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24.0,
                      vertical: 80.0,
                    ),
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0.8, end: 1.0),
                      duration: const Duration(milliseconds: 600),
                      curve: Curves.elasticOut,
                      builder: (context, val, child) {
                        return Transform.scale(scale: val, child: child);
                      },
                      child: GlassCard(
                        borderRadius: 32,
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Top visual (Logo or Premium Icon)
                            if (page.imagePath != null)
                              ClipRRect(
                                borderRadius: BorderRadius.circular(24),
                                child: Image.asset(
                                  page.imagePath!,
                                  width: 110,
                                  height: 110,
                                  fit: BoxFit.cover,
                                ),
                              )
                            else
                              Container(
                                padding: const EdgeInsets.all(20),
                                decoration: BoxDecoration(
                                  color: AppTheme.cobalt.withValues(alpha: 0.15),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: AppTheme.cobalt.withValues(alpha: 0.25),
                                  ),
                                ),
                                child: Icon(
                                  page.icon,
                                  size: 70,
                                  color: AppTheme.cobalt,
                                ),
                              ),
                            const SizedBox(height: 32),
                            Text(
                              page.title,
                              style: const TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.textPrimary,
                                letterSpacing: 1.1,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              page.subtitle,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 15,
                                color: AppTheme.textSecondary,
                                height: 1.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),

          // Bottom Navigation
          Positioned(
            bottom: 40,
            left: 24,
            right: 24,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Skip Button
                TextButton(
                  onPressed: _completeOnboarding,
                  child: Text(
                    'Skip',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.8),
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),

                // Page Indicator Dots
                Row(
                  children: List.generate(
                    _onboardingPages.length,
                    (index) => AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      height: 8,
                      width: _currentPage == index ? 24 : 8,
                      decoration: BoxDecoration(
                        color: _currentPage == index
                            ? Colors.white
                            : Colors.white.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                ),

                // Next / Get Started Button
                IconButton(
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor:
                        _onboardingPages[_currentPage].gradient.first,
                    padding: const EdgeInsets.all(16),
                  ),
                  icon: Icon(
                    _currentPage == _onboardingPages.length - 1
                        ? Icons.done_rounded
                        : Icons.arrow_forward_rounded,
                  ),
                  onPressed: () {
                    if (_currentPage < _onboardingPages.length - 1) {
                      _pageController.nextPage(
                        duration: const Duration(milliseconds: 450),
                        curve: Curves.easeInOutCubic,
                      );
                    } else {
                      _completeOnboarding();
                    }
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class OnboardingData {
  final String title;
  final String subtitle;
  final String? imagePath;
  final IconData? icon;
  final List<Color> gradient;

  OnboardingData({
    required this.title,
    required this.subtitle,
    this.imagePath,
    this.icon,
    required this.gradient,
  });
}
