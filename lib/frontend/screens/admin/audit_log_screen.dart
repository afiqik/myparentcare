import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../backend_logic/admin_state.dart';
import '../../theme.dart';
import '../../widgets/app_components.dart';

/// Log audit (RTDB, append-only): setiap tindakan admin direkodkan dan tidak
/// boleh diubah atau dipadam, walaupun oleh admin.
class AuditLogScreen extends StatefulWidget {
  const AuditLogScreen({super.key});

  @override
  State<AuditLogScreen> createState() => _AuditLogScreenState();
}

class _AuditLogScreenState extends State<AuditLogScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AdminState>();
    final entries = state.audit.where((e) {
      final text = '${e.action} ${e.summary} ${e.actorEmail}'.toLowerCase();
      return text.contains(_query.toLowerCase());
    }).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Audit log')),
      body: PageBackdrop(
        child: !state.workspaceReady
            ? const EmptyState(
                icon: Icons.link_off_rounded,
                title: 'Admin workspace not connected',
                message: 'The audit log lives in the admin-only Realtime Database. Ask the super admin to re-grant your access.',
              )
            : Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                    child: TextField(
                      onChanged: (v) => setState(() => _query = v),
                      decoration: const InputDecoration(
                        hintText: 'Search action, admin or details',
                        prefixIcon: Icon(Icons.search_rounded),
                      ),
                    ),
                  ),
                  Expanded(
                    child: entries.isEmpty
                        ? const EmptyState(
                            icon: Icons.history_rounded,
                            title: 'No activity yet',
                            message: 'Admin actions are recorded here automatically.',
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
                            itemCount: entries.length,
                            separatorBuilder: (_, _) => const SizedBox(height: 8),
                            itemBuilder: (context, index) {
                              final e = entries[index];
                              return Card(
                                child: ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: AppTheme.teal.withValues(alpha: 0.12),
                                    child: Icon(_icon(e.action), color: AppTheme.teal, size: 20),
                                  ),
                                  title: Text(e.summary),
                                  subtitle: Text('${e.actorEmail} · ${formatDateTime(e.atIso)}'),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
      ),
    );
  }

  IconData _icon(String action) {
    if (action.startsWith('program')) return Icons.event_note_rounded;
    if (action.startsWith('participant')) return Icons.person_remove_outlined;
    if (action.startsWith('email')) return Icons.email_outlined;
    if (action.startsWith('user')) return Icons.manage_accounts_outlined;
    if (action.startsWith('backup')) return Icons.backup_outlined;
    if (action.startsWith('media')) return Icons.image_outlined;
    if (action.startsWith('announcement')) return Icons.campaign_outlined;
    return Icons.history_rounded;
  }
}
