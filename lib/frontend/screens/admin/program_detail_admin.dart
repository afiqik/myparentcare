import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../backend_logic/admin_state.dart';
import '../../../core/errors.dart';
import '../../../database_storage/models.dart';
import '../../theme.dart';
import '../../widgets/app_components.dart';
import '../../widgets/media_widgets.dart';
import 'create_program_screen.dart';
import 'participant_list_screen.dart';

class ProgramDetailAdmin extends StatelessWidget {
  final Program program;

  const ProgramDetailAdmin({super.key, required this.program});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AdminState>();
    final latest = state.programById(program.id) ?? program;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 250,
            pinned: true,
            backgroundColor: AppTheme.canvas,
            actions: [
              PopupMenuButton<_AdminAction>(
                tooltip: 'Program actions',
                onSelected: (action) {
                  Future.delayed(Duration.zero, () {
                    if (context.mounted) {
                      _runAction(context, action, latest);
                    }
                  });
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: _AdminAction.edit,
                    child: _MenuRow(Icons.edit_outlined, 'Edit program'),
                  ),
                  const PopupMenuItem(
                    value: _AdminAction.duplicate,
                    child: _MenuRow(Icons.copy_all_outlined, 'Duplicate'),
                  ),
                  if (latest.status == 'draft' || latest.status == 'closed')
                    const PopupMenuItem(
                      value: _AdminAction.open,
                      child: _MenuRow(Icons.lock_open_rounded, 'Open registration'),
                    ),
                  if (latest.status == 'open')
                    const PopupMenuItem(
                      value: _AdminAction.close,
                      child: _MenuRow(
                        Icons.lock_outline_rounded,
                        'Close registration',
                      ),
                    ),
                  if (latest.status == 'open' || latest.status == 'closed')
                    const PopupMenuItem(
                      value: _AdminAction.complete,
                      child: _MenuRow(Icons.task_alt_rounded, 'Mark completed'),
                    ),
                  if (latest.status != 'archived')
                    const PopupMenuItem(
                      value: _AdminAction.archive,
                      child: _MenuRow(Icons.archive_outlined, 'Archive'),
                    ),
                  if (latest.status != 'cancelled' &&
                      latest.status != 'completed')
                    const PopupMenuItem(
                      value: _AdminAction.cancel,
                      child: _MenuRow(
                        Icons.event_busy_outlined,
                        'Cancel program',
                        color: AppTheme.warning,
                      ),
                    ),
                  const PopupMenuDivider(),
                  const PopupMenuItem(
                    value: _AdminAction.delete,
                    child: _MenuRow(
                      Icons.delete_outline_rounded,
                      'Delete permanently',
                      color: AppTheme.error,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 8),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: ProgramArtwork(
                program: latest,
                height: 250,
                borderRadius: BorderRadius.zero,
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 120),
            sliver: SliverList.list(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        latest.category,
                        style: TextStyle(
                          color: AppTheme.categoryColor(latest.category),
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    StatusPill(status: latest.displayStatus),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  latest.title,
                  style: Theme.of(context).textTheme.headlineLarge,
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: MetricCard(
                        value: '${latest.joinedCount}',
                        label: 'Students joined',
                        icon: Icons.groups_2_rounded,
                        color: AppTheme.teal,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: MetricCard(
                        value: '${latest.remainingSlots}',
                        label: 'Slots remaining',
                        icon: Icons.airline_seat_recline_normal_rounded,
                        color: AppTheme.cobalt,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      children: [
                        _DetailLine(
                          icon: Icons.calendar_month_rounded,
                          label: 'Date',
                          value: formatProgramDate(latest.date),
                        ),
                        _DetailLine(
                          icon: Icons.schedule_rounded,
                          label: 'Time',
                          value: latest.time,
                        ),
                        _DetailLine(
                          icon: Icons.location_on_outlined,
                          label: 'Location',
                          value: latest.location,
                          isLast: true,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Description',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 9),
                Text(
                  latest.description,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                if (latest.gallery.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Text('Gallery', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 9),
                  MediaGallery(media: latest.gallery),
                ],
                if (latest.status == 'cancelled') ...[
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppTheme.error.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.info_outline_rounded,
                          color: AppTheme.error,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            latest.cancellationReason.isEmpty
                                ? 'No cancellation reason was recorded.'
                                : latest.cancellationReason,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                Card(
                  color: const Color(0xFFF1F6FC),
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.info_outline_rounded,
                          color: AppTheme.cobalt,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            latest.joinedCount > 0
                                ? 'Editing or cancelling this program notifies joined students and parents.'
                                : 'No students have joined yet. This program can still be deleted.',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          decoration: const BoxDecoration(
            color: AppTheme.surface,
            border: Border(top: BorderSide(color: AppTheme.border)),
          ),
          child: FilledButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ParticipantListScreen(program: latest),
              ),
            ),
            icon: const Icon(Icons.groups_2_rounded),
            label: Text('VIEW PARTICIPANTS (${latest.joinedCount})'),
          ),
        ),
      ),
    );
  }

  Future<void> _runAction(
    BuildContext context,
    _AdminAction action,
    Program latest,
  ) async {
    final state = context.read<AdminState>();
    try {
      switch (action) {
        case _AdminAction.edit:
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => CreateProgramScreen(programToEdit: latest),
            ),
          );
          return;
        case _AdminAction.duplicate:
          await state.duplicateProgram(latest);
          if (!context.mounted) return;
          _showMessage(context, 'A draft copy was created.');
          return;
        case _AdminAction.open:
          await state.setProgramStatus(latest, 'open');
          if (!context.mounted) return;
          _showMessage(context, 'Registration is open. Students can now see this program.');
          return;
        case _AdminAction.close:
          if (!await _confirm(
            context,
            'Close registration?',
            'Students will no longer be able to join this program.',
          )) {
            return;
          }
          await state.setProgramStatus(latest, 'closed');
          if (!context.mounted) return;
          _showMessage(context, 'Registration closed.');
          return;
        case _AdminAction.complete:
          await state.setProgramStatus(latest, 'completed');
          if (!context.mounted) return;
          _showMessage(context, 'Program marked as completed.');
          return;
        case _AdminAction.archive:
          if (!await _confirm(
            context,
            'Archive program?',
            'It will be hidden from students but kept for admin reports.',
          )) {
            return;
          }
          await state.setProgramStatus(latest, 'archived');
          if (!context.mounted) return;
          _showMessage(context, 'Program archived.');
          return;
        case _AdminAction.cancel:
          final reason = await _askCancellationReason(context);
          if (reason == null || reason.trim().isEmpty) return;
          final notified = await state.cancelProgram(latest, reason.trim());
          if (!context.mounted) return;
          _showMessage(
            context,
            notified > 0
                ? 'Program cancelled. $notified students notified; parent emails queued in Email centre.'
                : 'Program cancelled.',
          );
          return;
        case _AdminAction.delete:
          final warningMsg = latest.joinedCount > 0
              ? 'This program has ${latest.joinedCount} joined students. Deleting it permanently removes their bookings. Consider Cancel or Archive instead.'
              : 'This cannot be undone. Use Archive if you want to keep history.';
          if (!await _confirm(
            context,
            'Delete permanently?',
            warningMsg,
            destructive: true,
          )) {
            return;
          }
          await state.deleteProgram(latest);
          if (!context.mounted) return;
          Navigator.pop(context);
          return;
      }
    } catch (error) {
      if (context.mounted) showSnack(context, friendlyError(error), error: true);
    }
  }

  Future<bool> _confirm(
    BuildContext context,
    String title,
    String message, {
    bool destructive = false,
  }) async {
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(title),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Back'),
              ),
              FilledButton(
                style: destructive
                    ? FilledButton.styleFrom(backgroundColor: AppTheme.error)
                    : null,
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Confirm'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<String?> _askCancellationReason(BuildContext context) async {
    final values = await showTextFieldsDialog(
      context,
      title: 'Cancel program',
      fields: const [
        DialogField(
          label: 'Cancellation reason',
          autofocus: true,
          minLines: 3,
          maxLines: 5,
          maxLength: 300,
        ),
      ],
      confirmLabel: 'Cancel program',
      cancelLabel: 'Back',
      destructive: true,
    );
    return values?.first;
  }

  void _showMessage(BuildContext context, String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }
}

enum _AdminAction { edit, duplicate, open, close, complete, archive, cancel, delete }

class _MenuRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;

  const _MenuRow(this.icon, this.label, {this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: 10),
        Text(label, style: TextStyle(color: color)),
      ],
    );
  }
}

class _DetailLine extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool isLast;

  const _DetailLine({
    required this.icon,
    required this.label,
    required this.value,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 14),
      child: Row(
        children: [
          Icon(icon, color: AppTheme.coral, size: 19),
          const SizedBox(width: 10),
          SizedBox(
            width: 70,
            child: Text(label, style: Theme.of(context).textTheme.bodySmall),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
        ],
      ),
    );
  }
}
