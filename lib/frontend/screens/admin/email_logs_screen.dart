import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../auth/auth_service.dart';
import '../../../backend_logic/admin_state.dart';
import '../../../security/input_validator.dart';
import '../../../core/errors.dart';
import '../../../database_storage/models.dart';
import '../../theme.dart';
import '../../widgets/app_components.dart';
import 'email_settings_screen.dart';

/// Pusat Emel: log penghantaran, barisan emel dan emel tertangguh.
class EmailLogsScreen extends StatefulWidget {
  const EmailLogsScreen({super.key});

  @override
  State<EmailLogsScreen> createState() => _EmailLogsScreenState();
}

class _EmailLogsScreenState extends State<EmailLogsScreen> {
  static const _filters = ['all', 'sent', 'failed', 'queued'];
  String _query = '';
  String _status = 'all';
  int _limit = 50;
  bool _testing = false;
  Stream<List<EmailLog>>? _stream;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _stream ??= _buildStream();
  }

  Stream<List<EmailLog>> _buildStream() => context.read<AdminState>().email.watchLogs(
    limit: _limit,
    status: _status == 'all' ? null : _status,
  );

  void _reload() => setState(() {
        _stream = _buildStream();
      });

  Future<void> _processQueue() async {
    final state = context.read<AdminState>();
    try {
      final result = await state.processEmailQueue();
      if (!mounted) return;
      showSnack(
        context,
        result.total == 0
            ? 'No queued emails.'
            : 'Sent ${result.done - result.failed} of ${result.total} emails (${result.failed} failed).',
        error: result.failed > 0,
      );
    } catch (error) {
      if (mounted) showSnack(context, friendlyError(error), error: true);
    }
  }

  Future<void> _sendPending() async {
    final state = context.read<AdminState>();
    try {
      final result = await state.sendPendingJoinEmails();
      if (!mounted) return;
      showSnack(
        context,
        'Sent ${result.done - result.failed} confirmation emails (${result.failed} failed).',
        error: result.failed > 0,
      );
    } catch (error) {
      if (mounted) showSnack(context, friendlyError(error), error: true);
    }
  }

  /// Hantar emel ujian sebenar supaya admin boleh mengesahkan EmailJS berfungsi.
  Future<void> _sendTest() async {
    final auth = context.read<AuthService>();
    final values = await showTextFieldsDialog(
      context,
      title: 'Send test email',
      intro: 'Sends a real email through EmailJS to check that parent notifications work.',
      fields: [
        DialogField(
          key: const Key('test_email_to'),
          label: 'Send to',
          initialValue: auth.currentUser?.email ?? auth.firebaseUser?.email ?? '',
          keyboardType: TextInputType.emailAddress,
          validator: InputValidator.validateEmail,
        ),
      ],
      confirmLabel: 'Send',
      confirmKey: const Key('test_email_send'),
    );
    final to = values?.first.trim();
    if (to == null || !mounted) return;
    setState(() => _testing = true);
    try {
      final result = await context.read<AdminState>().sendTestEmail(to);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          icon: Icon(
            result.success ? Icons.mark_email_read_rounded : Icons.error_outline_rounded,
            color: result.success ? AppTheme.success : AppTheme.error,
          ),
          title: Text(result.success ? 'Test email sent' : 'Test email failed'),
          content: Text(
            result.success
                ? 'EmailJS accepted the email for $to. Check the inbox (and the Spam folder) in a minute.'
                : result.error,
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } catch (error) {
      if (mounted) showSnack(context, friendlyError(error), error: true);
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _clear(String? status) async {
    final label = status == null ? 'ALL email logs' : '$status email logs';
    final ok = await confirmDialog(
      context,
      title: 'Delete $label?',
      message: 'This permanently deletes the delivery history. Consider creating a backup first.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!ok || !mounted) return;
    try {
      final deleted = await context.read<AdminState>().clearEmailLogs(status: status);
      if (mounted) showSnack(context, '$deleted email logs deleted.');
    } catch (error) {
      if (mounted) showSnack(context, friendlyError(error), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AdminState>();
    final counts = state.emailCounts;
    final progress = state.queueProgress;

    return Column(
      children: [
        if (!state.emailKeyConfigured)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: InfoBanner(
              icon: Icons.key_off_outlined,
              color: AppTheme.error,
              message: 'EmailJS private key is not set – parent emails cannot be sent.',
              actionLabel: 'Set up',
              onAction: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const EmailSettingsScreen()),
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 10),
          child: Row(
            children: [
              Expanded(
                child: _EmailMetric(
                  value: '${counts.sent}',
                  label: 'Delivered',
                  icon: Icons.mark_email_read_rounded,
                  color: AppTheme.success,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _EmailMetric(
                  value: '${counts.failed}',
                  label: 'Failed',
                  icon: Icons.error_outline_rounded,
                  color: counts.failed > 0 ? AppTheme.error : AppTheme.inkSoft,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _EmailMetric(
                  value: '${counts.queued + state.pendingJoinEmails}',
                  label: 'Waiting',
                  icon: Icons.schedule_send_rounded,
                  color: AppTheme.warning,
                ),
              ),
            ],
          ),
        ),
        if (progress != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LinearProgressIndicator(
                  value: progress.total == 0 ? null : progress.done / progress.total,
                  minHeight: 6,
                  borderRadius: BorderRadius.circular(99),
                ),
                const SizedBox(height: 4),
                Text(
                  'Sending ${progress.done}/${progress.total} · keep this screen open',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
                  key: const Key('email_test_button'),
                  onPressed: _testing ? null : _sendTest,
                  icon: _testing
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.outgoing_mail, size: 18),
                  label: const Text('Send test email'),
                ),
                FilledButton.tonalIcon(
                  onPressed: counts.queued == 0 || state.isBusy ? null : _processQueue,
                  icon: const Icon(Icons.send_rounded, size: 18),
                  label: Text('Send queued (${counts.queued})'),
                ),
                FilledButton.tonalIcon(
                  onPressed: state.pendingJoinEmails == 0 || state.isBusy ? null : _sendPending,
                  icon: const Icon(Icons.mark_email_unread_outlined, size: 18),
                  label: Text('Pending confirmations (${state.pendingJoinEmails})'),
                ),
                PopupMenuButton<String>(
                  tooltip: 'More',
                  onSelected: (value) {
                    switch (value) {
                      case 'refresh':
                        state.refreshDashboard();
                        _reload();
                      case 'clear_sent':
                        _clear('sent');
                      case 'clear_all':
                        _clear(null);
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'refresh', child: Text('Refresh')),
                    PopupMenuItem(value: 'clear_sent', child: Text('Delete delivered logs')),
                    PopupMenuItem(
                      value: 'clear_all',
                      child: Text('Delete all logs', style: TextStyle(color: AppTheme.error)),
                    ),
                  ],
                  child: const Padding(
                    padding: EdgeInsets.all(8),
                    child: Icon(Icons.more_horiz_rounded),
                  ),
                ),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: TextField(
            onChanged: (value) => setState(() => _query = value),
            decoration: const InputDecoration(
              hintText: 'Search parent email, student or program',
              prefixIcon: Icon(Icons.search_rounded),
            ),
          ),
        ),
        SizedBox(
          height: 50,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 7),
            scrollDirection: Axis.horizontal,
            itemCount: _filters.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final value = _filters[index];
              final selected = _status == value;
              return ChoiceChip(
                selected: selected,
                showCheckmark: false,
                selectedColor: AppTheme.ink,
                label: Text(value == 'all' ? 'All' : StatusPill.statusLabel(value)),
                labelStyle: TextStyle(
                  color: selected ? Colors.white : AppTheme.inkSoft,
                  fontWeight: FontWeight.w700,
                  fontSize: 11,
                ),
                onSelected: (_) {
                  _status = value;
                  _limit = 50;
                  _reload();
                },
              );
            },
          ),
        ),
        Expanded(
          child: StreamBuilder<List<EmailLog>>(
            stream: _stream,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return EmptyState(
                  icon: Icons.error_outline_rounded,
                  title: 'Could not load email logs',
                  message: friendlyError(snapshot.error!),
                );
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final all = snapshot.data!;
              final logs = all.where((item) {
                final searchable =
                    '${item.recipient} ${item.studentName} ${item.programTitle}'.toLowerCase();
                return searchable.contains(_query.toLowerCase());
              }).toList();
              if (logs.isEmpty) {
                return const EmptyState(
                  icon: Icons.inbox_outlined,
                  title: 'No email logs',
                  message: 'Parent notifications appear here after students join.',
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
                itemCount: logs.length + (all.length >= _limit ? 1 : 0),
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  if (index == logs.length) {
                    return Center(
                      child: TextButton(
                        onPressed: () {
                          _limit += 50;
                          _reload();
                        },
                        child: const Text('Load more'),
                      ),
                    );
                  }
                  final log = logs[index];
                  return Dismissible(
                    key: Key(log.id),
                    direction: DismissDirection.endToStart,
                    confirmDismiss: (_) => confirmDialog(
                      context,
                      title: 'Delete this log?',
                      message: 'Log for ${log.recipient} will be removed.',
                      confirmLabel: 'Delete',
                      destructive: true,
                    ),
                    background: Container(
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 20),
                      decoration: BoxDecoration(
                        color: AppTheme.error.withValues(alpha: 0.85),
                        borderRadius: BorderRadius.circular(22),
                      ),
                      child: const Icon(Icons.delete_sweep_outlined, color: Colors.white, size: 26),
                    ),
                    onDismissed: (_) => context.read<AdminState>().deleteEmailLog(log),
                    child: _EmailLogCard(log: log),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _EmailMetric extends StatelessWidget {
  final String value;
  final String label;
  final IconData icon;
  final Color color;

  const _EmailMetric({
    required this.value,
    required this.label,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(value, style: Theme.of(context).textTheme.titleLarge),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
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

class _EmailLogCard extends StatelessWidget {
  final EmailLog log;

  const _EmailLogCard({required this.log});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: () => _showEmail(context),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: StatusPill.statusColor(log.status).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Icon(
                      log.status == 'sent' ? Icons.mark_email_read_outlined : Icons.email_outlined,
                      color: StatusPill.statusColor(log.status),
                      size: 21,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          log.recipient,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text(
                          '${formatDateTime(log.sentTime)} · ${log.type} · ${log.attempts} attempt(s)',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  StatusPill(status: log.status, compact: true),
                ],
              ),
              const SizedBox(height: 13),
              Text(
                log.subject,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppTheme.ink,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '${log.studentName} · ${log.programTitle}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (log.status == 'failed' || log.status == 'queued') ...[
                const Divider(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        log.status == 'failed' ? log.errorMessage : 'Waiting in queue',
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: log.status == 'failed' ? AppTheme.error : AppTheme.warning,
                          fontSize: 11,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.tonalIcon(
                      onPressed: () => _retry(context),
                      icon: const Icon(Icons.refresh_rounded, size: 17),
                      label: Text(log.status == 'failed' ? 'Retry' : 'Send now'),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _retry(BuildContext context) async {
    try {
      final ok = await context.read<AdminState>().retryEmail(log);
      if (!context.mounted) return;
      showSnack(context, ok ? 'Email sent.' : 'Email failed again. See the error message.', error: !ok);
    } catch (error) {
      if (context.mounted) showSnack(context, friendlyError(error), error: true);
    }
  }

  void _showEmail(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.72,
        minChildSize: 0.45,
        maxChildSize: 0.92,
        builder: (_, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Email detail', style: Theme.of(context).textTheme.headlineMedium),
                ),
                StatusPill(status: log.status),
              ],
            ),
            const SizedBox(height: 18),
            Text('To', style: Theme.of(context).textTheme.bodySmall),
            Text(log.recipient, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 14),
            Text('Subject', style: Theme.of(context).textTheme.bodySmall),
            Text(log.subject, style: Theme.of(context).textTheme.titleMedium),
            if (log.errorMessage.isNotEmpty) ...[
              const SizedBox(height: 14),
              Text('Last error', style: Theme.of(context).textTheme.bodySmall),
              Text(log.errorMessage, style: const TextStyle(color: AppTheme.error)),
            ],
            const Divider(height: 30),
            Text(log.body, style: Theme.of(context).textTheme.bodyLarge),
          ],
        ),
      ),
    );
  }
}
