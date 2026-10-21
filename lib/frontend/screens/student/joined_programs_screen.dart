import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../backend_logic/student_state.dart';
import '../../../database_storage/models.dart';
import '../../theme.dart';
import '../../widgets/app_components.dart';
import 'program_detail_screen.dart';

class JoinedProgramsScreen extends StatelessWidget {
  const JoinedProgramsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<StudentState>();
    final joined = appState.participations
        .map((record) => _JoinedRecord.from(record, appState))
        .where((record) => record.program.id.isNotEmpty)
        .toList();
    final today = DateTime.now();
    final upcoming = joined.where((record) {
      final date = DateTime.tryParse(record.program.date);
      return record.program.status != 'cancelled' &&
          record.program.status != 'completed' &&
          (date == null ||
              !date.isBefore(DateTime(today.year, today.month, today.day)));
    }).toList();
    final completed = joined.where((record) {
      final date = DateTime.tryParse(record.program.date);
      return record.program.status == 'completed' ||
          (record.program.status != 'cancelled' &&
              date != null &&
              date.isBefore(DateTime(today.year, today.month, today.day)));
    }).toList();
    final cancelled = joined
        .where((record) => record.program.status == 'cancelled')
        .toList();

    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 8),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.border),
              ),
              child: const TabBar(
                dividerColor: Colors.transparent,
                indicatorSize: TabBarIndicatorSize.tab,
                indicator: BoxDecoration(
                  color: AppTheme.ink,
                  borderRadius: BorderRadius.all(Radius.circular(14)),
                ),
                labelColor: Colors.white,
                unselectedLabelColor: AppTheme.inkSoft,
                labelStyle: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
                tabs: [
                  Tab(text: 'Upcoming'),
                  Tab(text: 'Completed'),
                  Tab(text: 'Cancelled'),
                ],
              ),
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                _JoinedList(
                  records: upcoming,
                  emptyTitle: 'No upcoming programs',
                  emptyMessage: 'Programs you join will appear here.',
                ),
                _JoinedList(
                  records: completed,
                  emptyTitle: 'No completed programs',
                  emptyMessage: 'Your completed program history stays here.',
                ),
                _JoinedList(
                  records: cancelled,
                  emptyTitle: 'No cancelled programs',
                  emptyMessage:
                      'Cancelled programs remain visible for reference.',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _JoinedList extends StatelessWidget {
  final List<_JoinedRecord> records;
  final String emptyTitle;
  final String emptyMessage;

  const _JoinedList({
    required this.records,
    required this.emptyTitle,
    required this.emptyMessage,
  });

  @override
  Widget build(BuildContext context) {
    if (records.isEmpty) {
      return EmptyState(
        icon: Icons.bookmark_border_rounded,
        title: emptyTitle,
        message: emptyMessage,
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 28),
      itemCount: records.length,
      separatorBuilder: (_, _) => const SizedBox(height: 14),
      itemBuilder: (context, index) {
        final record = records[index];
        return Card(
          child: InkWell(
            borderRadius: BorderRadius.circular(22),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ProgramDetailScreen(program: record.program),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 54,
                    height: 64,
                    decoration: BoxDecoration(
                      color: AppTheme.categoryColor(
                        record.program.category,
                      ).withValues(alpha: 0.11),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(
                      Icons.event_available_rounded,
                      color: AppTheme.categoryColor(record.program.category),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                record.program.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ),
                            StatusPill(
                              status: record.program.status == 'open' ||
                                      record.program.status == 'closed'
                                  ? 'joined'
                                  : record.program.status,
                              compact: true,
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${formatProgramDate(record.program.date)} · ${record.program.time}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'Parent email: ${record.emailStatus}',
                          style: TextStyle(
                            color: StatusPill.statusColor(record.emailStatus),
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _JoinedRecord {
  final Program program;
  final String emailStatus;

  const _JoinedRecord({required this.program, required this.emailStatus});

  /// Maklumat terkini daripada katalog; jika program sudah diarkibkan (tiada
  /// dalam katalog), gunakan salinan yang disimpan semasa mendaftar.
  factory _JoinedRecord.from(Participant record, StudentState state) {
    final program = state.programById(record.programId) ??
        Program(
          id: record.programId,
          title: record.programTitle.isEmpty ? 'Program' : record.programTitle,
          description: '',
          date: record.programDate,
          time: record.programTime,
          location: record.programLocation,
          capacity: 0,
          category: 'Academic',
          status: 'completed',
        );
    return _JoinedRecord(program: program, emailStatus: record.emailStatus);
  }
}
