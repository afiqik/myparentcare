import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app_config.dart';
import '../../../auth/auth_service.dart';
import '../../../backend_logic/student_state.dart';
import '../../../core/errors.dart';
import '../../theme.dart';
import '../../widgets/app_components.dart';
import '../auth/welcome_screen.dart';
import '../legal/privacy_content.dart';

/// Padam akaun & semua data (keperluan Google Play & PDPA).
class DeleteAccountScreen extends StatefulWidget {
  const DeleteAccountScreen({super.key});

  @override
  State<DeleteAccountScreen> createState() => _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends State<DeleteAccountScreen> {
  final _reason = TextEditingController();
  final _confirmText = TextEditingController();
  bool _deleting = false;
  String _error = '';

  static const _confirmWord = 'DELETE';

  @override
  void dispose() {
    _reason.dispose();
    _confirmText.dispose();
    super.dispose();
  }

  Future<void> _delete() async {
    final auth = context.read<AuthService>();
    setState(() => _error = '');
    if (_confirmText.text.trim().toUpperCase() != _confirmWord) {
      setState(() => _error = 'Type $_confirmWord to confirm.');
      return;
    }
    final confirmed = await confirmDialog(
      context,
      title: 'Delete account permanently?',
      message:
          'All your data will be erased and your places in programs released. This cannot be undone.',
      confirmLabel: 'Delete forever',
      destructive: true,
    );
    if (!confirmed || !mounted) return;

    setState(() => _deleting = true);
    final studentState = context.read<StudentState>();
    try {
      await auth.deleteAccount(reason: _reason.text.trim());
      studentState.detach();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const WelcomeScreen()),
        (_) => false,
      );
      showSnack(context, 'Your account and data have been deleted.');
    } catch (error) {
      if (mounted) setState(() => _error = friendlyError(error));
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final isAdmin = auth.currentUser?.isAdmin ?? false;
    return Scaffold(
      appBar: AppBar(title: const Text('Delete account')),
      body: PageBackdrop(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              children: [
                Text(
                  'We are sorry to see you go',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  'Deleting your account is immediate and permanent.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 18),
                _ListCard(
                  title: 'What will be deleted',
                  color: AppTheme.error,
                  icon: Icons.delete_outline_rounded,
                  items: PrivacyContent.deletedData,
                ),
                _ListCard(
                  title: 'What we keep',
                  color: AppTheme.inkSoft,
                  icon: Icons.inventory_2_outlined,
                  items: PrivacyContent.keptAfterDeletion,
                ),
                if (isAdmin)
                  const InfoBanner(
                    icon: Icons.admin_panel_settings_outlined,
                    color: AppTheme.coral,
                    message:
                        'Administrator accounts cannot be deleted here. Ask the super admin to remove your admin role first.',
                  )
                else
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        children: [
                          TextField(
                            controller: _reason,
                            maxLength: 500,
                            maxLines: 2,
                            decoration: const InputDecoration(
                              labelText: 'Why are you leaving? (optional)',
                            ),
                          ),
                          const Padding(
                            padding: EdgeInsets.only(top: 4, bottom: 4),
                            child: Text(
                              'You will be asked to sign in with Google again to confirm it is you.',
                              style: TextStyle(fontSize: 12, color: AppTheme.inkSoft),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            key: const Key('delete_confirm_text'),
                            controller: _confirmText,
                            textCapitalization: TextCapitalization.characters,
                            decoration: const InputDecoration(
                              labelText: 'Type $_confirmWord to confirm',
                            ),
                          ),
                          if (_error.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: Text(
                                _error,
                                style: const TextStyle(
                                  color: AppTheme.error,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          const SizedBox(height: 14),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              key: const Key('delete_submit'),
                              style: FilledButton.styleFrom(backgroundColor: AppTheme.error),
                              onPressed: _deleting ? null : _delete,
                              icon: _deleting
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(Icons.delete_forever_rounded),
                              label: Text(_deleting ? 'Deleting...' : 'DELETE MY ACCOUNT'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                Text(
                  'Need help instead? Email ${AppConfig.supportEmail}',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ListCard extends StatelessWidget {
  final String title;
  final Color color;
  final IconData icon;
  final List<String> items;

  const _ListCard({
    required this.title,
    required this.color,
    required this.icon,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(width: 8),
                Text(title, style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 8),
            for (final item in items)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text('• $item', style: Theme.of(context).textTheme.bodyMedium),
              ),
          ],
        ),
      ),
    );
  }
}
