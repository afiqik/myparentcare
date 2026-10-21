import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../auth/auth_service.dart';
import '../../../backend_logic/student_state.dart';
import '../../../database_storage/models.dart';
import '../../theme.dart';
import '../../widgets/app_components.dart';
import '../../widgets/media_widgets.dart';
import 'complete_profile_screen.dart';
import 'join_confirmation_screen.dart';

class ProgramDetailScreen extends StatefulWidget {
  final Program program;

  const ProgramDetailScreen({super.key, required this.program});

  @override
  State<ProgramDetailScreen> createState() => _ProgramDetailScreenState();
}

class _ProgramDetailScreenState extends State<ProgramDetailScreen> {
  @override
  void initState() {
    super.initState();
    // Kiraan tempat dibaca atas permintaan (bukan didengar) untuk jimat kuota.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<StudentState>().refreshSeats(widget.program.id, force: true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<StudentState>();
    final auth = context.watch<AuthService>();
    final student = auth.currentUser;
    final latest = appState.programById(widget.program.id) ?? widget.program;
    final seats = appState.seatsFor(latest.id);
    final hasJoined = appState.hasJoined(latest.id);
    final action = _resolveAction(
      latest,
      student,
      hasJoined,
      seatsKnown: seats != null,
      emailVerified: auth.emailVerified,
    );

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () => appState.refreshSeats(latest.id, force: true),
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              expandedHeight: 270,
              pinned: true,
              backgroundColor: AppTheme.canvas,
              flexibleSpace: FlexibleSpaceBar(
                background: ProgramArtwork(
                  program: latest,
                  height: 270,
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
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.categoryColor(
                            latest.category,
                          ).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          latest.category,
                          style: TextStyle(
                            color: AppTheme.categoryColor(latest.category),
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const Spacer(),
                      StatusPill(status: latest.displayStatus),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    latest.title,
                    style: Theme.of(context).textTheme.headlineLarge,
                  ),
                  const SizedBox(height: 22),
                  _DetailsGrid(program: latest),
                  const SizedBox(height: 28),
                  Text(
                    'About this program',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    latest.description,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  if (latest.gallery.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    Text('Gallery', style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 10),
                    MediaGallery(media: latest.gallery),
                  ],
                  const SizedBox(height: 24),
                  _CapacityCard(program: latest, known: seats != null),
                  const SizedBox(height: 14),
                  if (!hasJoined && latest.status == 'open') ...[
                                const SizedBox(height: 4),
                  ],
                  if (latest.status == 'cancelled')
                    _NoticeCard(
                      color: AppTheme.error,
                      icon: Icons.event_busy_rounded,
                      title: 'Program cancelled',
                      message: latest.cancellationReason.isEmpty
                          ? 'This program has been cancelled by the administrator.'
                          : latest.cancellationReason,
                    )
                  else if (student != null && student.parentEmail.isNotEmpty)
                    _NoticeCard(
                      color: AppTheme.violet,
                      icon: Icons.mark_email_read_outlined,
                      title: 'Parent notification',
                      message:
                          'After confirmation, program details will be sent to ${student.parentEmail}.',
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          decoration: const BoxDecoration(
            color: AppTheme.surface,
            border: Border(top: BorderSide(color: AppTheme.border)),
          ),
          child: FilledButton.icon(
            key: const Key('program_action'),
            onPressed: action.enabled
                ? () => _handleAction(context, action, latest, student)
                : null,
            icon: Icon(action.icon),
            label: Text(action.label),
          ),
        ),
      ),
    );
  }

  _ProgramAction _resolveAction(
    Program program,
    AppUser? student,
    bool hasJoined, {
    required bool seatsKnown,
    required bool emailVerified,
  }) {
    if (hasJoined) {
      return const _ProgramAction(
        label: 'ALREADY JOINED',
        icon: Icons.check_circle_rounded,
        type: _ActionType.disabled,
      );
    }
    if (program.status != 'open') {
      return _ProgramAction(
        label: program.status == 'cancelled' ? 'PROGRAM CANCELLED' : 'REGISTRATION CLOSED',
        icon: Icons.lock_rounded,
        type: _ActionType.disabled,
      );
    }
    if (seatsKnown && program.isFull) {
      return const _ProgramAction(
        label: 'PROGRAM FULL',
        icon: Icons.group_off_rounded,
        type: _ActionType.disabled,
      );
    }
    if (student == null || !student.canJoinPrograms) {
      return const _ProgramAction(
        label: 'COMPLETE PROFILE',
        icon: Icons.person_add_alt_1_rounded,
        type: _ActionType.completeProfile,
      );
    }
    if (!emailVerified) {
      return const _ProgramAction(
        label: 'VERIFY EMAIL TO JOIN',
        icon: Icons.mark_email_unread_rounded,
        type: _ActionType.disabled,
      );
    }
    return const _ProgramAction(
      label: 'JOIN PROGRAM',
      icon: Icons.arrow_forward_rounded,
      type: _ActionType.join,
    );
  }

  Future<void> _handleAction(
    BuildContext context,
    _ProgramAction action,
    Program latest,
    AppUser? student,
  ) async {
    if (action.type == _ActionType.completeProfile) {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const CompleteProfileScreen()),
      );
      return;
    }
    if (action.type == _ActionType.join && student != null) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              JoinConfirmationScreen(program: latest, student: student),
        ),
      );
    }
  }
}

class _DetailsGrid extends StatelessWidget {
  final Program program;

  const _DetailsGrid({required this.program});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: _DetailItem(
                    icon: Icons.calendar_month_rounded,
                    label: 'Date',
                    value: formatProgramDate(program.date),
                  ),
                ),
                Expanded(
                  child: _DetailItem(
                    icon: Icons.schedule_rounded,
                    label: 'Time',
                    value: program.time,
                  ),
                ),
              ],
            ),
            const Divider(height: 28),
            _DetailItem(
              icon: Icons.location_on_outlined,
              label: 'Location',
              value: program.location,
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _DetailItem({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: AppTheme.cobalt, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 2),
              Text(value, style: Theme.of(context).textTheme.titleMedium),
            ],
          ),
        ),
      ],
    );
  }
}

class _CapacityCard extends StatelessWidget {
  final Program program;
  final bool known;

  const _CapacityCard({required this.program, required this.known});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Availability',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Flexible(
                  child: Text(
                    known ? '${program.remainingSlots} slots left' : 'Checking...',
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      color: AppTheme.cobalt,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: known ? program.fillRate : null,
              minHeight: 8,
              borderRadius: BorderRadius.circular(999),
              backgroundColor: AppTheme.border,
            ),
            const SizedBox(height: 8),
            Text(
              known
                  ? '${program.joinedCount} of ${program.capacity} students joined · pull down to refresh'
                  : 'Capacity ${program.capacity} students',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _NoticeCard extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String title;
  final String message;

  const _NoticeCard({
    required this.color,
    required this.icon,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(message, style: Theme.of(context).textTheme.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

enum _ActionType { join, completeProfile, disabled }

class _ProgramAction {
  final String label;
  final IconData icon;
  final _ActionType type;

  const _ProgramAction({
    required this.label,
    required this.icon,
    required this.type,
  });

  bool get enabled => type != _ActionType.disabled;
}
