import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../auth/auth_service.dart';
import '../../../backend_logic/admin_state.dart';
import '../../../core/errors.dart';
import '../../../database_storage/firestore_paths.dart';
import '../../../main.dart';
import '../../theme.dart';
import '../../widgets/app_components.dart';

/// Kesihatan sistem: laporan ralat, panduan kuota percuma, migrasi data lama.
class SystemScreen extends StatefulWidget {
  const SystemScreen({super.key});

  @override
  State<SystemScreen> createState() => _SystemScreenState();
}

class _SystemScreenState extends State<SystemScreen> {
  late Future<QuerySnapshot<Map<String, dynamic>>> _errors;
  bool _migrating = false;

  @override
  void initState() {
    super.initState();
    _errors = _loadErrors();
  }

  Future<QuerySnapshot<Map<String, dynamic>>> _loadErrors() {
    return context
        .read<AppServices>()
        .firestore
        .collection(FirestorePaths.errorReports)
        .orderBy('createdAt', descending: true)
        .limit(30)
        .get();
  }

  Future<void> _clearErrors(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) async {
    final firestore = context.read<AppServices>().firestore;
    final batch = firestore.batch();
    for (final d in docs) {
      batch.delete(d.reference);
    }
    await batch.commit();
    if (!mounted) return;
    setState(() {
      _errors = _loadErrors();
    });
  }

  Future<void> _migrate() async {
    final state = context.read<AdminState>();
    setState(() => _migrating = true);
    try {
      final legacy = await state.readLegacyData();
      if (legacy.isEmpty) {
        if (mounted) showSnack(context, 'No old-version data found. Nothing to migrate.');
        return;
      }
      if (!mounted) return;
      final counts = legacy.map((k, v) => MapEntry(k, v is Map ? v.length : 0));
      final ok = await confirmDialog(
        context,
        title: 'Import old-version data?',
        message:
            'Found: ${counts.entries.map((e) => '${e.key} ${e.value}').join(', ')}.\n\n'
            'Demo accounts and old admin roles are NOT imported. Existing students will be asked to accept the Privacy Policy again.',
        confirmLabel: 'Import',
      );
      if (!ok || !mounted) return;
      final report = await state.migrateLegacy(legacy);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Migration complete'),
          content: Text(
            'Users: ${report.users}\nPrograms: ${report.programs}\nParticipants: ${report.participants}\n'
            'Email logs: ${report.emailLogs}\nAnnouncements: ${report.announcements}'
            '${report.skipped.isEmpty ? '' : '\n\nSkipped: ${report.skipped.join(', ')}'}\n\n'
            'Check the data, then delete the old public copy.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Later')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppTheme.error),
              onPressed: () async {
                Navigator.pop(dialogContext);
                await state.deleteLegacyData();
                if (mounted) showSnack(context, 'Old-version data deleted from Realtime Database.');
              },
              child: const Text('Delete old data'),
            ),
          ],
        ),
      );
    } catch (error) {
      if (mounted) showSnack(context, friendlyError(error), error: true);
    } finally {
      if (mounted) setState(() => _migrating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isSuper = context.watch<AuthService>().isSuperAdmin;
    final state = context.watch<AdminState>();
    return Scaffold(
      appBar: AppBar(title: const Text('System health')),
      body: PageBackdrop(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Free plan (Spark) limits', style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 10),
                    const _Limit('Firestore', '50,000 reads · 20,000 writes · 20,000 deletes per day'),
                    const _Limit('Realtime Database', '100 simultaneous connections (admins only) · 1 GB stored'),
                    const _Limit('Hosting (download page)', '10 GB storage · 360 MB transfer per day'),
                    const _Limit('EmailJS (free)', '200 emails per month – upgrade for more parents'),
                    const SizedBox(height: 8),
                    Text(
                      'Students use ~5 reads per app open thanks to the single catalog document and caching. '
                      'Check usage in Firebase Console → Usage and billing.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Workspace connection: ${state.workspaceReady ? 'connected' : 'not linked'}',
                      style: TextStyle(
                        color: state.workspaceReady ? AppTheme.success : AppTheme.error,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (isSuper)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Import old-version data', style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 6),
                      Text(
                        'Moves data from the old publicly readable Realtime Database structure into the new secure Firestore structure.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: _migrating ? null : _migrate,
                        icon: _migrating
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.move_up_rounded),
                        label: const Text('Find & import old data'),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 12),
            const SectionTitle(title: 'Recent error reports'),
            const SizedBox(height: 8),
            FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
              future: _errors,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Text(friendlyError(snapshot.error!), style: const TextStyle(color: AppTheme.error));
                }
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                final docs = snapshot.data!.docs;
                if (docs.isEmpty) {
                  return const EmptyState(
                    icon: Icons.check_circle_outline_rounded,
                    title: 'No errors reported',
                    message: 'App crashes and failures from users appear here.',
                  );
                }
                return Column(
                  children: [
                    for (final d in docs)
                      Card(
                        child: ExpansionTile(
                          shape: const Border(),
                          leading: const Icon(Icons.bug_report_outlined, color: AppTheme.error),
                          title: Text(d.data()['message']?.toString() ?? ''),
                          subtitle: Text(
                            '${d.data()['platform'] ?? ''} · v${d.data()['appVersion'] ?? ''} · '
                            '${formatDateTime((d.data()['createdAt'] as Timestamp?)?.toDate().toIso8601String() ?? '')}',
                          ),
                          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          children: [
                            SelectableText(
                              '${d.data()['error'] ?? ''}\n\n${d.data()['stackTrace'] ?? ''}',
                              style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                            ),
                          ],
                        ),
                      ),
                    TextButton.icon(
                      onPressed: () => _clearErrors(docs),
                      icon: const Icon(Icons.delete_sweep_outlined),
                      label: const Text('Clear these reports'),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _Limit extends StatelessWidget {
  final String name;
  final String value;

  const _Limit(this.name, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 130, child: Text(name, style: Theme.of(context).textTheme.titleSmall)),
          Expanded(child: Text(value, style: Theme.of(context).textTheme.bodySmall)),
        ],
      ),
    );
  }
}
