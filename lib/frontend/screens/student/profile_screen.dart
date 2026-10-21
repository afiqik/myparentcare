import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:package_info_plus/package_info_plus.dart';

import '../../../app_config.dart';
import '../../../auth/auth_service.dart';
import '../../navigation.dart';
import '../../theme.dart';
import '../legal/privacy_policy_screen.dart';
import 'complete_profile_screen.dart';
import 'delete_account_screen.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final user = auth.currentUser;
    if (user == null) return const SizedBox.shrink();

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 28),
      children: [
        Center(
          child: Container(
            width: 88,
            height: 88,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: AppTheme.primaryGradient),
              borderRadius: BorderRadius.circular(28),
            ),
            child: Text(
              user.fullName.isEmpty ? 'S' : user.fullName[0].toUpperCase(),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 34,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        Text(
          user.fullName,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 4),
        Text(
          '${user.matricNo} · ${user.course}',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 20),
        Card(
          color: user.canJoinPrograms
              ? const Color(0xFFE9F8F3)
              : const Color(0xFFFFF3D8),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(
                  user.canJoinPrograms
                      ? Icons.verified_rounded
                      : Icons.pending_actions_rounded,
                  color: user.canJoinPrograms
                      ? AppTheme.success
                      : AppTheme.warning,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user.canJoinPrograms
                            ? 'Profile ready'
                            : 'Profile ${user.profileCompletePercent}% complete',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        user.canJoinPrograms
                            ? 'You can join any open program.'
                            : 'Complete all details before joining.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        _InfoCard(
          title: 'Student information',
          color: AppTheme.cobalt,
          rows: [
            _InfoRow(Icons.email_outlined, 'Email', user.email),
            _InfoRow(Icons.badge_outlined, 'Matric', user.matricNo),
            _InfoRow(Icons.school_outlined, 'Course', user.course),
            _InfoRow(Icons.layers_outlined, 'Semester', user.semester),
            _InfoRow(Icons.phone_outlined, 'Phone', user.phone),
          ],
        ),
        const SizedBox(height: 14),
        _InfoCard(
          title: 'Parent information',
          color: AppTheme.violet,
          rows: [
            _InfoRow(Icons.family_restroom_rounded, 'Name', user.parentName),
            _InfoRow(
              Icons.favorite_border_rounded,
              'Relationship',
              user.relationship,
            ),
            _InfoRow(Icons.email_outlined, 'Email', user.parentEmail),
            _InfoRow(Icons.phone_outlined, 'Phone', user.parentPhone),
          ],
        ),
        const SizedBox(height: 18),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const CompleteProfileScreen()),
            ),
            icon: const Icon(Icons.edit_outlined),
            label: const Text('EDIT PROFILE'),
          ),
        ),
        const SizedBox(height: 18),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.privacy_tip_outlined, color: AppTheme.cobalt),
                title: const Text('Privacy Policy'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const PrivacyPolicyScreen()),
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.support_agent_rounded, color: AppTheme.teal),
                title: const Text('Help & contact'),
                subtitle: const Text(AppConfig.supportEmail),
              ),
              const Divider(height: 1),
              ListTile(
                key: const Key('profile_delete_account'),
                leading: const Icon(Icons.delete_forever_outlined, color: AppTheme.error),
                title: const Text(
                  'Delete account',
                  style: TextStyle(color: AppTheme.error),
                ),
                subtitle: const Text('Permanently remove your account and data'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const DeleteAccountScreen()),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => signOutAndGoHome(context),
            icon: const Icon(Icons.logout_rounded, color: AppTheme.error),
            label: const Text(
              'Sign out',
              style: TextStyle(color: AppTheme.error),
            ),
          ),
        ),
        const SizedBox(height: 12),
        const _VersionLabel(),
      ],
    );
  }
}

class _VersionLabel extends StatelessWidget {
  const _VersionLabel();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PackageInfo>(
      future: PackageInfo.fromPlatform(),
      builder: (context, snapshot) {
        final info = snapshot.data;
        return Text(
          info == null
              ? AppConfig.appName
              : '${AppConfig.appName} ${info.version} (${info.buildNumber})',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        );
      },
    );
  }
}

class _InfoCard extends StatelessWidget {
  final String title;
  final Color color;
  final List<_InfoRow> rows;

  const _InfoCard({
    required this.title,
    required this.color,
    required this.rows,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 14),
            for (var index = 0; index < rows.length; index++) ...[
              rows[index].buildWithColor(context, color),
              if (index != rows.length - 1) const Divider(height: 22),
            ],
          ],
        ),
      ),
    );
  }
}

class _InfoRow {
  final IconData icon;
  final String label;
  final String value;

  const _InfoRow(this.icon, this.label, this.value);

  Widget buildWithColor(BuildContext context, Color color) {
    return Row(
      children: [
        Icon(icon, color: color, size: 19),
        const SizedBox(width: 11),
        SizedBox(
          width: 84,
          child: Text(label, style: Theme.of(context).textTheme.bodySmall),
        ),
        Expanded(
          child: Text(
            value.isEmpty ? 'Not provided' : value,
            textAlign: TextAlign.right,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
      ],
    );
  }
}
