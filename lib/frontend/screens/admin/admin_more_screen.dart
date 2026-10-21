import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app_config.dart';
import '../../../auth/auth_service.dart';
import '../../../backend_logic/admin_state.dart';
import '../../navigation.dart';
import '../../theme.dart';
import '../../widgets/app_components.dart';
import '../legal/privacy_policy_screen.dart';
import 'admin_users_screen.dart';
import 'announcements_screen.dart';
import 'audit_log_screen.dart';
import 'backup_screen.dart';
import 'email_settings_screen.dart';
import 'system_screen.dart';

class AdminMoreScreen extends StatelessWidget {
  const AdminMoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final state = context.watch<AdminState>();
    final last = state.lastBackup;

    void open(Widget screen) =>
        Navigator.push(context, MaterialPageRoute(builder: (_) => screen));

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 30),
      children: [
        Card(
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: AppTheme.coral.withValues(alpha: 0.12),
              child: const Icon(Icons.admin_panel_settings_rounded, color: AppTheme.coral),
            ),
            title: Text(auth.currentUser?.fullName ?? 'Admin'),
            subtitle: Text(
              '${auth.currentUser?.email ?? ''}${auth.isSuperAdmin ? ' · Super admin' : ''}',
            ),
          ),
        ),
        const SizedBox(height: 16),
        const SectionTitle(title: 'Manage'),
        const SizedBox(height: 8),
        _Tile(
          icon: Icons.people_alt_rounded,
          color: AppTheme.cobalt,
          title: 'Users & roles',
          subtitle: 'Students, admins, suspend accounts',
          onTap: () => open(const AdminUsersScreen()),
        ),
        _Tile(
          icon: Icons.key_rounded,
          color: AppTheme.violet,
          title: 'Email settings',
          subtitle: state.emailKeyConfigured
              ? 'EmailJS connected – parent emails send automatically'
              : 'EmailJS private key missing – emails cannot be sent',
          warning: !state.emailKeyConfigured,
          onTap: () => open(const EmailSettingsScreen()),
        ),
        _Tile(
          icon: Icons.campaign_rounded,
          color: AppTheme.coral,
          title: 'Announcements',
          subtitle: 'Broadcast news to every student',
          onTap: () => open(const AnnouncementsScreen()),
        ),
        const SizedBox(height: 16),
        const SectionTitle(title: 'Safety & data'),
        const SizedBox(height: 8),
        _Tile(
          icon: Icons.backup_rounded,
          color: AppTheme.violet,
          title: 'Backup & restore',
          subtitle: last == null
              ? 'No backup yet – create one now'
              : 'Last backup ${formatDateTime(DateTime.fromMillisecondsSinceEpoch(last.at).toIso8601String())}'
                  '${last.isAutomatic ? ' · automatic' : ''}',
          warning: state.backupOverdue,
          onTap: () => open(const BackupScreen()),
        ),
        _Tile(
          icon: Icons.history_rounded,
          color: AppTheme.teal,
          title: 'Audit log',
          subtitle: 'Who did what, and when',
          onTap: () => open(const AuditLogScreen()),
        ),
        _Tile(
          icon: Icons.monitor_heart_outlined,
          color: AppTheme.orange,
          title: 'System health',
          subtitle: 'Error reports, free-plan usage, data migration',
          onTap: () => open(const SystemScreen()),
        ),
        const SizedBox(height: 16),
        const SectionTitle(title: 'About'),
        const SizedBox(height: 8),
        _Tile(
          icon: Icons.privacy_tip_outlined,
          color: AppTheme.inkSoft,
          title: 'Privacy Policy',
          subtitle: AppConfig.privacyPolicyUrl,
          onTap: () => open(const PrivacyPolicyScreen()),
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: () => signOutAndGoHome(context),
          icon: const Icon(Icons.logout_rounded, color: AppTheme.error),
          label: const Text('Sign out', style: TextStyle(color: AppTheme.error)),
        ),
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool warning;

  const _Tile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.warning = false,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        onTap: onTap,
        leading: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.11),
            borderRadius: BorderRadius.circular(13),
          ),
          child: Icon(icon, color: color),
        ),
        title: Text(title, style: Theme.of(context).textTheme.titleMedium),
        subtitle: Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
        trailing: warning
            ? const Icon(Icons.warning_amber_rounded, color: AppTheme.warning)
            : const Icon(Icons.chevron_right_rounded),
      ),
    );
  }
}
