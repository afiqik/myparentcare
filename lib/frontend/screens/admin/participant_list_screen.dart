import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../api/file_export.dart';
import '../../../backend_logic/admin_state.dart';
import '../../../core/errors.dart';
import '../../../database_storage/models.dart';
import '../../theme.dart';
import '../../widgets/app_components.dart';

class ParticipantListScreen extends StatefulWidget {
  final Program program;

  const ParticipantListScreen({super.key, required this.program});

  @override
  State<ParticipantListScreen> createState() => _ParticipantListScreenState();
}

class _ParticipantListScreenState extends State<ParticipantListScreen> {
  late final Stream<List<Participant>> _stream;
  String _query = '';
  String _course = 'All';
  String _semester = 'All';

  @override
  void initState() {
    super.initState();
    _stream = context.read<AdminState>().watchParticipants(widget.program.id);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Joined students')),
      body: PageBackdrop(
        child: StreamBuilder<List<Participant>>(
          stream: _stream,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return EmptyState(
                icon: Icons.error_outline_rounded,
                title: 'Could not load participants',
                message: friendlyError(snapshot.error!),
              );
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final participants = snapshot.data!;
            final courses = [
              'All',
              ...participants
                  .map((p) => p.course)
                  .where((v) => v.isNotEmpty)
                  .toSet(),
            ];
            final semesters = [
              'All',
              ...participants
                  .map((p) => p.semester)
                  .where((v) => v.isNotEmpty)
                  .toSet(),
            ];
            final filtered = participants.where((participant) {
              final searchable =
                  '${participant.studentName} ${participant.matricNo} ${participant.parentEmail}'
                      .toLowerCase();
              return searchable.contains(_query.toLowerCase()) &&
                  (_course == 'All' || participant.course == _course) &&
                  (_semester == 'All' || participant.semester == _semester);
            }).toList();

            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 10),
                  child: Column(
                    children: [
                      TextField(
                        onChanged: (value) => setState(() => _query = value),
                        decoration: const InputDecoration(
                          hintText: 'Search name, matric or parent email',
                          prefixIcon: Icon(Icons.search_rounded),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: _FilterDropdown(
                              label: 'Course',
                              value: courses.contains(_course)
                                  ? _course
                                  : 'All',
                              values: courses,
                              onChanged: (value) =>
                                  setState(() => _course = value),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _FilterDropdown(
                              label: 'Semester',
                              value: semesters.contains(_semester)
                                  ? _semester
                                  : 'All',
                              values: semesters,
                              onChanged: (value) =>
                                  setState(() => _semester = value),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      Text(
                        '${filtered.length} of ${participants.length} students',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: participants.isEmpty
                            ? null
                            : () => _exportCsv(context, participants),
                        icon: const Icon(Icons.download_rounded, size: 17),
                        label: const Text('Export CSV'),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: filtered.isEmpty
                      ? const EmptyState(
                          icon: Icons.group_off_outlined,
                          title: 'No participants found',
                          message:
                              'Students who join this program appear here immediately.',
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                          itemCount: filtered.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 12),
                          itemBuilder: (context, index) => _ParticipantCard(
                            participant: filtered[index],
                            program: widget.program,
                          ),
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _exportCsv(
    BuildContext context,
    List<Participant> participants,
  ) async {
    String escape(String value) {
      // Elak suntikan formula CSV (=, +, -, @) apabila dibuka dalam Excel.
      final safe = RegExp(r'^[=+\-@]').hasMatch(value) ? "'$value" : value;
      return '"${safe.replaceAll('"', '""')}"';
    }

    final rows = <String>[
      'Student Name,Matric No,Course,Semester,Phone,Parent Name,Parent Email,Parent Phone,Relationship,Join Date,Email Status',
      ...participants.map(
        (item) => [
          item.studentName,
          item.matricNo,
          item.course,
          item.semester,
          item.studentPhone,
          item.parentName,
          item.parentEmail,
          item.parentPhone,
          item.relationship,
          item.joinedAt,
          item.emailStatus,
        ].map(escape).join(','),
      ),
    ];
    final date = DateFormat('yyyyMMdd').format(DateTime.now());
    try {
      await FileExport.save(
        bytes: Uint8List.fromList(utf8.encode('\uFEFF${rows.join('\n')}')),
        fileName: 'participants_${widget.program.id}_$date.csv',
        mimeType: 'text/csv',
        subject: 'Participants – ${widget.program.title}',
      );
    } catch (error) {
      if (context.mounted) showSnack(context, friendlyError(error), error: true);
    }
  }
}

class _FilterDropdown extends StatelessWidget {
  final String label;
  final String value;
  final List<String> values;
  final ValueChanged<String> onChanged;

  const _FilterDropdown({
    required this.label,
    required this.value,
    required this.values,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(labelText: label, isDense: true),
      items: values
          .map(
            (item) => DropdownMenuItem(
              value: item,
              child: Text(item, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          )
          .toList(),
      onChanged: (item) {
        if (item != null) onChanged(item);
      },
    );
  }
}

class _ParticipantCard extends StatelessWidget {
  final Participant participant;
  final Program program;

  const _ParticipantCard({required this.participant, required this.program});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        shape: const Border(),
        leading: CircleAvatar(
          backgroundColor: AppTheme.cobalt.withValues(alpha: 0.1),
          child: Text(
            participant.studentName.isEmpty
                ? 'S'
                : participant.studentName[0].toUpperCase(),
            style: const TextStyle(
              color: AppTheme.cobalt,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        title: Text(
          participant.studentName,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        subtitle: Text(
          '${participant.matricNo} · ${participant.course}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: StatusPill(status: participant.emailStatus, compact: true),
        children: [
          const Divider(),
          _InfoLine('Semester', participant.semester),
          _InfoLine('Student phone', participant.studentPhone),
          _InfoLine('Parent', participant.parentName),
          _InfoLine('Parent email', participant.parentEmail),
          _InfoLine('Parent phone', participant.parentPhone),
          _InfoLine('Relationship', participant.relationship),
          _InfoLine('Joined', formatDateTime(participant.joinedAt)),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _remove(context),
                  icon: const Icon(
                    Icons.person_remove_outlined,
                    color: AppTheme.error,
                    size: 18,
                  ),
                  label: const Text(
                    'Remove',
                    style: TextStyle(color: AppTheme.error),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => _resend(context),
                  icon: const Icon(Icons.send_rounded, size: 18),
                  label: const Text('Resend email'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _remove(BuildContext context) async {
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Remove student?'),
            content: Text(
              '${participant.studentName} will be removed and one slot will reopen.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Back'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: AppTheme.error),
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Remove'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !context.mounted) return;
    try {
      await context.read<AdminState>().removeParticipant(program, participant);
      if (context.mounted) showSnack(context, '${participant.studentName} removed. The student was notified.');
    } catch (error) {
      if (context.mounted) showSnack(context, friendlyError(error), error: true);
    }
  }

  Future<void> _resend(BuildContext context) async {
    final sent = await context.read<AdminState>().resendParticipantEmail(
      participant,
      program,
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(sent ? 'Parent email resent.' : 'Email failed again.'),
        backgroundColor: sent ? AppTheme.success : AppTheme.error,
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  final String label;
  final String value;

  const _InfoLine(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 104,
            child: Text(label, style: Theme.of(context).textTheme.bodySmall),
          ),
          Expanded(
            child: Text(
              value.isEmpty ? 'Not provided' : value,
              textAlign: TextAlign.right,
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
        ],
      ),
    );
  }
}
