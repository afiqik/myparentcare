import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../api/file_export.dart';
import '../../../auth/auth_service.dart';
import '../../../backend_logic/admin_state.dart';
import '../../../backend_logic/backup_service.dart';
import '../../../core/errors.dart';
import '../../theme.dart';
import '../../widgets/app_components.dart';

/// Backup manual (pelan Spark tiada backup automatik terurus).
/// Fail JSON mengandungi SEMUA data Firestore + ruang kerja admin RTDB.
class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key});

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  bool _working = false;
  int _restored = 0;

  Future<void> _backup() async {
    setState(() => _working = true);
    try {
      final file = await context.read<AdminState>().createBackup();
      await FileExport.save(
        bytes: file.bytes,
        fileName: file.fileName,
        mimeType: 'application/json',
        subject: 'MyParentCare backup',
      );
      if (!mounted) return;
      showSnack(
        context,
        'Backup created: ${file.summary.documents} documents (${formatBytes(file.summary.bytes)}). Store it somewhere safe.',
      );
    } catch (error) {
      if (mounted) showSnack(context, friendlyError(error), error: true);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _restore() async {
    final picked = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['json'],
    );
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    if (!mounted) return;
    Map<String, dynamic> backup;
    try {
      backup = BackupService.parse(bytes);
    } catch (error) {
      showSnack(context, friendlyError(error), error: true);
      return;
    }
    final summary = BackupService.summarize(backup);
    final ok = await confirmDialog(
      context,
      title: 'Restore this backup?',
      message:
          'Backup from ${formatDateTime(summary.createdAt)} by ${summary.createdBy} with ${summary.documents} documents.\n\n'
          'Documents with the same ID will be OVERWRITTEN. Documents created after the backup are kept. '
          'Create a fresh backup first if you are unsure.',
      confirmLabel: 'Restore',
      destructive: true,
    );
    if (!ok || !mounted) return;
    setState(() {
      _working = true;
      _restored = 0;
    });
    try {
      final written = await context.read<AdminState>().restoreBackup(
        backup,
        onProgress: (n) => mounted ? setState(() => _restored = n) : null,
      );
      if (mounted) showSnack(context, 'Restore complete: $written documents written.');
    } catch (error) {
      if (mounted) showSnack(context, 'Restore stopped: ${friendlyError(error)}', error: true);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AdminState>();
    final isSuper = context.watch<AuthService>().isSuperAdmin;
    final lastAuto = state.backups.where((b) => b.kind == 'backup' && b.isAutomatic).firstOrNull;
    return Scaffold(
      appBar: AppBar(title: const Text('Backup & restore')),
      body: PageBackdrop(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            if (lastAuto != null)
              InfoBanner(
                icon: Icons.cloud_done_outlined,
                color: AppTheme.success,
                message:
                    'Automatic daily backup is active (Google Drive → MyParentCare Backups). '
                    'Last: ${formatDateTime(DateTime.fromMillisecondsSinceEpoch(lastAuto.at).toIso8601String())}. '
                    'Backups are kept for a maximum of 90 days (Privacy Policy).',
              )
            else
              const InfoBanner(
                icon: Icons.info_outline_rounded,
                color: AppTheme.cobalt,
                message:
                    'No automatic backup yet. Install the free Google Apps Script automation (apps_script/README.md) '
                    'for daily backups to Google Drive, or create a backup here at least once a week. '
                    'Backups are kept for a maximum of 90 days (Privacy Policy).',
              ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Create backup', style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 6),
                    Text(
                      'Exports users, programs, seats, participants, notifications, media, email logs and the admin workspace to one JSON file. '
                      'Each document counts as one read from the daily free quota.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 14),
                    FilledButton.icon(
                      key: const Key('backup_create'),
                      onPressed: _working ? null : _backup,
                      icon: const Icon(Icons.cloud_download_outlined),
                      label: const Text('CREATE & DOWNLOAD BACKUP'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Restore', style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 6),
                    Text(
                      isSuper
                          ? 'Write every document from a backup file back into the database.'
                          : 'Only the super admin can restore backups.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    if (_working && _restored > 0) ...[
                      const SizedBox(height: 10),
                      Text('$_restored documents written...'),
                    ],
                    const SizedBox(height: 14),
                    OutlinedButton.icon(
                      onPressed: !isSuper || _working ? null : _restore,
                      icon: const Icon(Icons.restore_rounded),
                      label: const Text('Restore from file'),
                    ),
                  ],
                ),
              ),
            ),
            if (_working) const Padding(padding: EdgeInsets.all(16), child: LinearProgressIndicator()),
            const SizedBox(height: 16),
            const SectionTitle(title: 'History'),
            const SizedBox(height: 8),
            if (state.backups.isEmpty)
              const EmptyState(
                icon: Icons.history_toggle_off_rounded,
                title: 'No backups yet',
                message: 'Every backup and restore is recorded here.',
              )
            else
              for (final record in state.backups)
                Card(
                  child: ListTile(
                    leading: Icon(
                      record.kind == 'restore' ? Icons.restore_rounded : Icons.backup_rounded,
                      color: record.kind == 'restore' ? AppTheme.warning : AppTheme.violet,
                    ),
                    title: Text(
                      '${record.kind == 'restore' ? 'Restore' : record.isAutomatic ? 'Automatic backup' : 'Backup'}'
                      ' · ${record.documents} documents',
                    ),
                    subtitle: Text(
                      '${formatDateTime(DateTime.fromMillisecondsSinceEpoch(record.at).toIso8601String())} · ${record.byEmail}'
                      '${record.bytes > 0 ? ' · ${formatBytes(record.bytes)}' : ''}'
                      '${record.note.isNotEmpty ? '\n${record.note}' : ''}',
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}
