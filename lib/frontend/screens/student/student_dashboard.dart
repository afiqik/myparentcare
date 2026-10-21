import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../auth/auth_service.dart';
import '../../../backend_logic/student_state.dart';
import '../../theme.dart';
import '../../widgets/app_components.dart';
import 'program_detail_screen.dart';

class StudentDashboard extends StatelessWidget {
  final ValueChanged<int> onTabChange;

  const StudentDashboard({super.key, required this.onTabChange});

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthService>().currentUser;
    final appState = context.watch<StudentState>();
    final firstName = user?.fullName.trim().split(' ').firstOrNull ?? 'Student';
    final programs = appState.openPrograms.take(3).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      children: [
        Text(
          'Hi, $firstName',
          style: Theme.of(context).textTheme.headlineLarge,
        ),
        const SizedBox(height: 6),
        Text(
          'Cari pengalaman baharu. Kami urus notifikasi untuk keluarga.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 22),
        _HeroCard(
          joinedCount: appState.participations.length,
          onBrowse: () => onTabChange(1),
        ),
        const SizedBox(height: 16),
        if (user != null && !user.canJoinPrograms)
          _ProfilePrompt(
            percent: user.profileCompletePercent,
            onTap: () => onTabChange(3),
          )
        else if (user != null)
          _ParentReadyCard(email: user.parentEmail),
        const SizedBox(height: 26),
        const SectionTitle(title: 'Quick access'),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _QuickAction(
                title: 'Browse',
                subtitle: 'Open programs',
                icon: Icons.explore_rounded,
                color: AppTheme.cobalt,
                onTap: () => onTabChange(1),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _QuickAction(
                title: 'Joined',
                subtitle: 'Your programs',
                icon: Icons.bookmark_rounded,
                color: AppTheme.teal,
                onTap: () => onTabChange(2),
              ),
            ),
          ],
        ),
        const SizedBox(height: 26),
        SectionTitle(
          title: 'Open now',
          actionLabel: 'See all',
          onAction: () => onTabChange(1),
        ),
        const SizedBox(height: 12),
        if (!appState.catalogLoaded)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (programs.isEmpty)
          EmptyState(
            icon: Icons.event_busy_outlined,
            title: 'Belum ada program terbuka',
            message: 'Program baharu daripada admin akan muncul di sini.',
            actionLabel: 'Refresh programs',
            onAction: () => onTabChange(1),
          )
        else
          ...programs.map(
            (program) => Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: ProgramCard(
                program: program,
                seatsKnown: appState.seatsFor(program.id) != null,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ProgramDetailScreen(program: program),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _HeroCard extends StatelessWidget {
  final int joinedCount;
  final VoidCallback onBrowse;

  const _HeroCard({required this.joinedCount, required this.onBrowse});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: AppTheme.ink,
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          BoxShadow(
            color: AppTheme.ink.withValues(alpha: 0.18),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -30,
            top: -38,
            child: Container(
              width: 150,
              height: 150,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [
                    AppTheme.coral.withValues(alpha: 0.8),
                    AppTheme.orange.withValues(alpha: 0.45),
                  ],
                ),
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'PROGRAM JOURNEY',
                style: TextStyle(
                  color: Color(0xFF93C5FD),
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                '$joinedCount program\nyang disertai',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  height: 1.08,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.8,
                ),
              ),
              const SizedBox(height: 20),
              FilledButton.tonalIcon(
                onPressed: onBrowse,
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: AppTheme.ink,
                ),
                icon: const Icon(Icons.arrow_outward_rounded, size: 18),
                label: const Text('Explore programs'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProfilePrompt extends StatelessWidget {
  final int percent;
  final VoidCallback onTap;

  const _ProfilePrompt({required this.percent, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFFFFF3D8),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: AppTheme.orange.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: const Icon(
                  Icons.family_restroom_rounded,
                  color: AppTheme.warning,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Complete profile · $percent%',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 3),
                    const Text(
                      'Parent information is required before joining.',
                      style: TextStyle(color: AppTheme.inkSoft, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_rounded, color: AppTheme.ink),
            ],
          ),
        ),
      ),
    );
  }
}

class _ParentReadyCard extends StatelessWidget {
  final String email;

  const _ParentReadyCard({required this.email});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFFE9F8F3),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Icon(Icons.verified_user_rounded, color: AppTheme.success),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Ready to join',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Parent alerts will go to $email',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppTheme.inkSoft,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _QuickAction({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: color, size: 27),
              const SizedBox(height: 20),
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 2),
              Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}
