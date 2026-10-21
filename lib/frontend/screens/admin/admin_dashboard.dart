import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../backend_logic/admin_state.dart';
import '../../../database_storage/models.dart';
import '../../theme.dart';
import '../../widgets/app_components.dart';
import 'backup_screen.dart';
import 'create_program_screen.dart';
import 'email_settings_screen.dart';
import 'program_detail_admin.dart';

class AdminDashboard extends StatelessWidget {
  final ValueChanged<int> onTabChange;

  const AdminDashboard({super.key, required this.onTabChange});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AdminState>();
    final live = state.programs.where((p) => p.status == 'open').toList();
    final counts = state.emailCounts;

    return RefreshIndicator(
      onRefresh: state.refreshDashboard,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
        children: [
          Text('Admin command centre', style: Theme.of(context).textTheme.headlineLarge),
          const SizedBox(height: 6),
          Text(
            'Publish programs, watch registrations, and keep every parent informed.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          ..._alerts(context, state),
          _PublishHero(),
          const SizedBox(height: 22),
          GridView.count(
            crossAxisCount: MediaQuery.sizeOf(context).width > 700 ? 4 : 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.12,
            children: [
              MetricCard(
                value: '${live.length}',
                label: 'Open programs',
                icon: Icons.event_available_rounded,
                color: AppTheme.cobalt,
              ),
              MetricCard(
                value: '${state.totalJoined}',
                label: 'Total registrations',
                icon: Icons.groups_2_rounded,
                color: AppTheme.teal,
              ),
              MetricCard(
                value: '${state.studentCount}',
                label: 'Students',
                icon: Icons.school_rounded,
                color: AppTheme.violet,
              ),
              MetricCard(
                value: '${counts.sent}',
                label: 'Emails delivered (${counts.successRate}%)',
                icon: Icons.mark_email_read_rounded,
                color: AppTheme.success,
              ),
            ],
          ),
          const SizedBox(height: 22),
          if (state.onlineAdmins.isNotEmpty) ...[
            const SectionTitle(title: 'Admins online now'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final admin in state.onlineAdmins)
                  Chip(
                    avatar: const CircleAvatar(
                      backgroundColor: AppTheme.success,
                      radius: 5,
                    ),
                    label: Text(admin.name.isEmpty ? admin.email : admin.name),
                  ),
              ],
            ),
            const SizedBox(height: 22),
          ],
          const SectionTitle(title: 'Quick actions'),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _QuickAction(
                  icon: Icons.event_note_rounded,
                  label: 'Manage\nprograms',
                  color: AppTheme.cobalt,
                  onTap: () => onTabChange(1),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _QuickAction(
                  icon: Icons.email_outlined,
                  label: 'Email\ncentre',
                  color: AppTheme.violet,
                  onTap: () => onTabChange(2),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _QuickAction(
                  icon: Icons.tune_rounded,
                  label: 'Admin\ntools',
                  color: AppTheme.teal,
                  onTap: () => onTabChange(4),
                ),
              ),
            ],
          ),
          const SizedBox(height: 26),
          SectionTitle(
            title: 'Live programs',
            actionLabel: 'View all',
            onAction: () => onTabChange(1),
          ),
          const SizedBox(height: 12),
          if (!state.programsLoaded)
            const Center(child: CircularProgressIndicator())
          else if (live.isEmpty)
            const EmptyState(
              icon: Icons.event_note_rounded,
              title: 'No live programs',
              message: 'Publish an open program to make it visible to students.',
            )
          else
            ...live.take(3).map(
              (program) => Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: ProgramCard(
                  program: program,
                  showArtwork: false,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ProgramDetailAdmin(program: program),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _alerts(BuildContext context, AdminState state) {
    final alerts = <Widget>[];
    void add(Widget banner) {
      alerts
        ..add(banner)
        ..add(const SizedBox(height: 10));
    }

    if (state.workspaceReady && !state.emailKeyConfigured) {
      add(InfoBanner(
        icon: Icons.key_off_outlined,
        color: AppTheme.error,
        message: 'EmailJS private key is missing – parent emails are waiting. Open Tools → Email settings.',
        actionLabel: 'Tools',
        onAction: () => onTabChange(4),
      ));
    }
    final automation = state.emailAutomation;
    if (automation != null && !automation.ok) {
      add(InfoBanner(
        icon: Icons.sync_problem_rounded,
        color: AppTheme.error,
        message: 'Automatic parent emails are paused: ${automation.message} '
            'Waiting emails will be retried automatically and students have been notified.',
        actionLabel: 'Details',
        onAction: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const EmailSettingsScreen()),
        ),
      ));
    }
    if (state.emailCounts.failed > 0) {
      add(InfoBanner(
        icon: Icons.error_outline_rounded,
        color: AppTheme.error,
        message: '${state.emailCounts.failed} parent emails failed. Open the Email centre to see why and retry them.',
        actionLabel: 'Open',
        onAction: () => onTabChange(2),
      ));
    }
    if (state.pendingJoinEmails > 0 || state.emailCounts.queued > 0) {
      add(InfoBanner(
        icon: Icons.schedule_send_rounded,
        color: AppTheme.warning,
        message:
            '${state.pendingJoinEmails + state.emailCounts.queued} parent emails are waiting to be sent.',
        actionLabel: 'Send',
        onAction: () => onTabChange(2),
      ));
    }
    if (state.workspaceReady && state.backupOverdue) {
      add(InfoBanner(
        icon: Icons.backup_outlined,
        color: AppTheme.violet,
        message: state.lastBackup == null
            ? 'No backup has been made yet. Create one now.'
            : 'Last backup is older than 7 days. Create a new backup.',
        actionLabel: 'Backup',
        onAction: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const BackupScreen()),
        ),
      ));
    }
    final nearlyFull = state.programs
        .where((p) => p.status == 'open' && p.capacity > 0 && p.fillRate >= 0.9 && !p.isFull)
        .toList();
    for (final Program p in nearlyFull.take(2)) {
      add(InfoBanner(
        icon: Icons.local_fire_department_outlined,
        color: AppTheme.orange,
        message: '"${p.title}" is ${(p.fillRate * 100).round()}% full.',
      ));
    }
    return alerts;
  }
}

class _PublishHero extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppTheme.coral, AppTheme.orange],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(26),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'READY TO PUBLISH?',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.4,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Create a program\nin minutes.',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 25,
                    height: 1.08,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.7,
                  ),
                ),
                const SizedBox(height: 18),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: AppTheme.ink,
                  ),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const CreateProgramScreen()),
                  ),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('New program'),
                ),
              ],
            ),
          ),
          const Icon(Icons.rocket_launch_rounded, size: 82, color: Colors.white38),
        ],
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _QuickAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: color, size: 25),
              const SizedBox(height: 16),
              Text(label, style: Theme.of(context).textTheme.titleMedium),
            ],
          ),
        ),
      ),
    );
  }
}
