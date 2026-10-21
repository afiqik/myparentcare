import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:provider/provider.dart';

import '../../../api/file_export.dart';
import '../../../app_config.dart';
import '../../../backend_logic/admin_state.dart';
import '../../../core/errors.dart';
import '../../../database_storage/models.dart';
import '../../theme.dart';
import '../../widgets/app_components.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  _ReportType _type = _ReportType.programs;
  bool _exporting = false;
  List<EmailLog> _logs = [];
  bool _logsLoaded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadLogs());
  }

  /// Log emel dimuat atas permintaan (maks 500 terkini) – jimat bacaan.
  Future<void> _loadLogs() async {
    try {
      final logs = await context.read<AdminState>().email.fetchLogs(limit: 500);
      if (mounted) setState(() => _logs = logs);
    } catch (error) {
      if (mounted) showSnack(context, friendlyError(error), error: true);
    } finally {
      if (mounted) setState(() => _logsLoaded = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AdminState>();
    final totalJoined = state.programs.fold<int>(
      0,
      (sum, program) => sum + program.joinedCount,
    );
    final sent = _logs.where((log) => log.status == 'sent').length;
    final successRate = _logs.isEmpty
        ? 0
        : ((sent / _logs.length) * 100).round();

    return RefreshIndicator(
      onRefresh: _loadLogs,
      child: ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
      children: [
        if (!_logsLoaded)
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: LinearProgressIndicator(),
          ),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppTheme.ink,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Row(
            children: [
              Expanded(
                child: _ReportHeroMetric(
                  value: '${state.programs.length}',
                  label: 'Programs',
                ),
              ),
              const _VerticalLine(),
              Expanded(
                child: _ReportHeroMetric(value: '$totalJoined', label: 'Joins'),
              ),
              const _VerticalLine(),
              Expanded(
                child: _ReportHeroMetric(
                  value: '$successRate%',
                  label: 'Email success',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        const SectionTitle(title: 'Choose report'),
        const SizedBox(height: 12),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 1.48,
          children: _ReportType.values
              .map(
                (type) => _ReportChoice(
                  type: type,
                  selected: type == _type,
                  onTap: () => setState(() => _type = type),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 24),
        SectionTitle(title: _type.title),
        const SizedBox(height: 12),
        _ReportPreview(type: _type, state: state, logs: _logs),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _exporting ? null : () => _exportCsv(state),
                icon: const Icon(Icons.table_view_outlined),
                label: const Text('EXPORT CSV'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton.icon(
                onPressed: _exporting ? null : () => _exportPdf(state),
                icon: _exporting
                    ? const SizedBox(
                        width: 17,
                        height: 17,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Icon(Icons.picture_as_pdf_outlined),
                label: const Text('EXPORT PDF'),
              ),
            ),
          ],
        ),
      ],
      ),
    );
  }

  Future<void> _exportCsv(AdminState state) async {
    setState(() => _exporting = true);
    try {
      final data = Uint8List.fromList(utf8.encode('\uFEFF${_buildCsv(state)}'));
      await FileExport.save(
        bytes: data,
        fileName: _fileName('csv'),
        mimeType: 'text/csv',
        subject: 'MyParentCare ${_type.title}',
      );
    } catch (error) {
      if (mounted) showSnack(context, friendlyError(error), error: true);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _exportPdf(AdminState state) async {
    setState(() => _exporting = true);
    try {
      final bytes = await _buildPdf(state);
      await FileExport.save(
        bytes: bytes,
        fileName: _fileName('pdf'),
        mimeType: 'application/pdf',
        subject: 'MyParentCare ${_type.title}',
      );
    } catch (error) {
      if (mounted) showSnack(context, friendlyError(error), error: true);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  String _fileName(String extension) {
    final date = DateFormat('yyyyMMdd').format(DateTime.now());
    return 'myparentcare_${_type.name}_$date.$extension';
  }

  String _buildCsv(AdminState state) {
    String row(List<Object?> values) => values
        .map((value) {
        final text = value.toString();
        final safe = RegExp(r'^[=+\-@]').hasMatch(text) ? "'$text" : text;
        return '"${safe.replaceAll('"', '""')}"';
      })
        .join(',');

    switch (_type) {
      case _ReportType.programs:
        return [
          row(['Title', 'Category', 'Date', 'Status', 'Capacity', 'Joined']),
          ...state.programs.map(
            (program) => row([
              program.title,
              program.category,
              program.date,
              program.displayStatus,
              program.capacity,
              program.joinedCount,
            ]),
          ),
        ].join('\n');
      case _ReportType.joins:
        return [
          row(['Program', 'Joined Students', 'Capacity', 'Fill Rate']),
          ...state.programs.map(
            (program) => row([
              program.title,
              program.joinedCount,
              program.capacity,
              '${_fillRate(program)}%',
            ]),
          ),
        ].join('\n');
      case _ReportType.email:
        return [
          row(['Recipient', 'Student', 'Program', 'Type', 'Status', 'Time']),
          ..._logs.map(
            (log) => row([
              log.recipient,
              log.studentName,
              log.programTitle,
              log.type,
              log.status,
              log.sentTime,
            ]),
          ),
        ].join('\n');
      case _ReportType.monthly:
        return [
          row(['Month', 'Programs', 'Joined Students', 'Emails Sent']),
          ..._monthlyRows(state).map(
            (item) => row([item.month, item.programs, item.joins, item.emails]),
          ),
        ].join('\n');
    }
  }

  Future<Uint8List> _buildPdf(AdminState state) async {
    final document = pw.Document();
    final rows = _pdfRows(state);
    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        header: (_) => pw.Container(
          padding: const pw.EdgeInsets.only(bottom: 12),
          decoration: const pw.BoxDecoration(
            border: pw.Border(
              bottom: pw.BorderSide(color: PdfColors.blue700, width: 2),
            ),
          ),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'MyParentCare',
                style: pw.TextStyle(
                  fontSize: 20,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.blue800,
                ),
              ),
              pw.Text(DateFormat('d MMM yyyy').format(DateTime.now())),
            ],
          ),
        ),
        footer: (context) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            'Page ${context.pageNumber} of ${context.pagesCount}',
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
          ),
        ),
        build: (_) => [
          pw.SizedBox(height: 18),
          pw.Text(
            _type.title,
            style: pw.TextStyle(fontSize: 26, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 6),
          pw.Text(
            'Generated from MyParentCare data · ${AppConfig.institutionName}.',
            style: const pw.TextStyle(color: PdfColors.grey700),
          ),
          pw.SizedBox(height: 22),
          pw.TableHelper.fromTextArray(
            headers: rows.headers,
            data: rows.data,
            headerDecoration: const pw.BoxDecoration(color: PdfColors.blue800),
            headerStyle: pw.TextStyle(
              color: PdfColors.white,
              fontWeight: pw.FontWeight.bold,
              fontSize: 9,
            ),
            cellStyle: const pw.TextStyle(fontSize: 8),
            cellPadding: const pw.EdgeInsets.all(6),
            border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
            oddRowDecoration: const pw.BoxDecoration(color: PdfColors.grey100),
          ),
        ],
      ),
    );
    return document.save();
  }

  ({List<String> headers, List<List<String>> data}) _pdfRows(AdminState state) {
    switch (_type) {
      case _ReportType.programs:
        return (
          headers: [
            'Program',
            'Category',
            'Date',
            'Status',
            'Capacity',
            'Joined',
          ],
          data: state.programs
              .map(
                (p) => [
                  p.title,
                  p.category,
                  p.date,
                  p.status,
                  '${p.capacity}',
                  '${p.joinedCount}',
                ],
              )
              .toList(),
        );
      case _ReportType.joins:
        return (
          headers: ['Program', 'Joined', 'Capacity', 'Fill rate'],
          data: state.programs
              .map(
                (p) => [
                  p.title,
                  '${p.joinedCount}',
                  '${p.capacity}',
                  '${_fillRate(p)}%',
                ],
              )
              .toList(),
        );
      case _ReportType.email:
        return (
          headers: [
            'Recipient',
            'Student',
            'Program',
            'Type',
            'Status',
            'Time',
          ],
          data: _logs
              .map(
                (e) => [
                  e.recipient,
                  e.studentName,
                  e.programTitle,
                  e.type,
                  e.status,
                  e.sentTime,
                ],
              )
              .toList(),
        );
      case _ReportType.monthly:
        return (
          headers: ['Month', 'Programs', 'Joins', 'Emails'],
          data: _monthlyRows(state)
              .map(
                (m) => [m.month, '${m.programs}', '${m.joins}', '${m.emails}'],
              )
              .toList(),
        );
    }
  }

  List<_MonthlyRow> _monthlyRows(AdminState state) {
    final now = DateTime.now();
    return List.generate(6, (index) {
      final date = DateTime(now.year, now.month - (5 - index));
      final key = DateFormat('yyyy-MM').format(date);
      final programs = state.programs.where((program) {
        final source = program.createdAt.isEmpty
            ? program.date
            : program.createdAt;
        return source.startsWith(key);
      }).toList();
      return _MonthlyRow(
        month: DateFormat('MMM yyyy').format(date),
        programs: programs.length,
        joins: programs.fold(0, (sum, program) => sum + program.joinedCount),
        emails: _logs
            .where((log) => log.sentTime.startsWith(key))
            .length,
      );
    });
  }
}

class _ReportPreview extends StatelessWidget {
  final _ReportType type;
  final AdminState state;
  final List<EmailLog> logs;

  const _ReportPreview({required this.type, required this.state, required this.logs});

  @override
  Widget build(BuildContext context) {
    switch (type) {
      case _ReportType.programs:
      case _ReportType.joins:
        if (state.programs.isEmpty) {
          return const EmptyState(
            icon: Icons.bar_chart_rounded,
            title: 'No report data',
            message: 'Create a program to start building reports.',
          );
        }
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: state.programs.take(6).map((program) {
                final rate = program.capacity == 0
                    ? 0.0
                    : (program.joinedCount / program.capacity).clamp(0.0, 1.0);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              program.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                          ),
                          Text('${(rate * 100).round()}%'),
                        ],
                      ),
                      const SizedBox(height: 7),
                      LinearProgressIndicator(
                        value: rate,
                        minHeight: 7,
                        borderRadius: BorderRadius.circular(99),
                        backgroundColor: AppTheme.border,
                        color: AppTheme.categoryColor(program.category),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        );
      case _ReportType.email:
        final sent = logs
            .where((log) => log.status == 'sent')
            .length;
        final failed = logs
            .where((log) => log.status == 'failed')
            .length;
        return _SplitSummary(
          leftValue: '$sent',
          leftLabel: 'Sent',
          rightValue: '$failed',
          rightLabel: 'Failed',
        );
      case _ReportType.monthly:
        final total = state.programs.fold<int>(
          0,
          (sum, p) => sum + p.joinedCount,
        );
        return _SplitSummary(
          leftValue: '${state.programs.length}',
          leftLabel: 'Programs to date',
          rightValue: '$total',
          rightLabel: 'Total registrations',
        );
    }
  }
}

class _SplitSummary extends StatelessWidget {
  final String leftValue;
  final String leftLabel;
  final String rightValue;
  final String rightLabel;

  const _SplitSummary({
    required this.leftValue,
    required this.leftLabel,
    required this.rightValue,
    required this.rightLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Row(
          children: [
            Expanded(
              child: _SummaryValue(value: leftValue, label: leftLabel),
            ),
            const SizedBox(height: 58, child: VerticalDivider()),
            Expanded(
              child: _SummaryValue(value: rightValue, label: rightLabel),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryValue extends StatelessWidget {
  final String value;
  final String label;

  const _SummaryValue({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value, style: Theme.of(context).textTheme.headlineLarge),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _ReportChoice extends StatelessWidget {
  final _ReportType type;
  final bool selected;
  final VoidCallback onTap;

  const _ReportChoice({
    required this.type,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: selected ? AppTheme.ink : Colors.white,
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Icon(type.icon, color: selected ? Colors.white : type.color),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  type.shortTitle,
                  style: TextStyle(
                    color: selected ? Colors.white : AppTheme.ink,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReportHeroMetric extends StatelessWidget {
  final String value;
  final String label;

  const _ReportHeroMetric({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.w800,
          ),
        ),
        Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white60, fontSize: 10),
        ),
      ],
    );
  }
}

class _VerticalLine extends StatelessWidget {
  const _VerticalLine();

  @override
  Widget build(BuildContext context) {
    return Container(width: 1, height: 42, color: Colors.white24);
  }
}

class _MonthlyRow {
  final String month;
  final int programs;
  final int joins;
  final int emails;

  const _MonthlyRow({
    required this.month,
    required this.programs,
    required this.joins,
    required this.emails,
  });
}

enum _ReportType { programs, joins, email, monthly }

extension on _ReportType {
  String get title {
    switch (this) {
      case _ReportType.programs:
        return 'Program report';
      case _ReportType.joins:
        return 'Student join report';
      case _ReportType.email:
        return 'Parent notification report';
      case _ReportType.monthly:
        return 'Monthly report';
    }
  }

  String get shortTitle {
    switch (this) {
      case _ReportType.programs:
        return 'Programs';
      case _ReportType.joins:
        return 'Student joins';
      case _ReportType.email:
        return 'Parent email';
      case _ReportType.monthly:
        return 'Monthly';
    }
  }

  IconData get icon {
    switch (this) {
      case _ReportType.programs:
        return Icons.event_note_rounded;
      case _ReportType.joins:
        return Icons.groups_2_rounded;
      case _ReportType.email:
        return Icons.mark_email_read_rounded;
      case _ReportType.monthly:
        return Icons.calendar_view_month_rounded;
    }
  }

  Color get color {
    switch (this) {
      case _ReportType.programs:
        return AppTheme.cobalt;
      case _ReportType.joins:
        return AppTheme.teal;
      case _ReportType.email:
        return AppTheme.violet;
      case _ReportType.monthly:
        return AppTheme.coral;
    }
  }
}

int _fillRate(Program program) {
  if (program.capacity == 0) return 0;
  return ((program.joinedCount / program.capacity) * 100).round();
}
