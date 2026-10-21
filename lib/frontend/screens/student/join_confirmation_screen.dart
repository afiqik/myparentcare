import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../auth/auth_service.dart';
import '../../../backend_logic/student_state.dart';
import '../../../database_storage/models.dart';
import '../../theme.dart';
import '../../widgets/app_components.dart';
import 'join_success_screen.dart';

class JoinConfirmationScreen extends StatefulWidget {
  final Program program;
  final AppUser student;

  const JoinConfirmationScreen({
    super.key,
    required this.program,
    required this.student,
  });

  @override
  State<JoinConfirmationScreen> createState() => _JoinConfirmationScreenState();
}

class _JoinConfirmationScreenState extends State<JoinConfirmationScreen> {
  bool _loading = false;

  Future<void> _confirm() async {
    if (_loading) return;
    setState(() => _loading = true);
    final auth = context.read<AuthService>();
    final outcome = await context.read<StudentState>().joinProgram(
      program: widget.program,
      student: auth.currentUser ?? widget.student,
      emailVerified: auth.emailVerified,
    );
    if (!mounted) return;
    setState(() => _loading = false);

    if (!outcome.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(outcome.message),
          backgroundColor: AppTheme.error,
        ),
      );
      return;
    }

    await Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => JoinSuccessScreen(
          program: widget.program,
          student: widget.student,
          emailStatus: outcome.emailStatus,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Confirm your place')),
      body: PageBackdrop(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 120),
          children: [
            ProgramArtwork(program: widget.program, height: 170),
            const SizedBox(height: 20),
            Text(
              'One last check',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 7),
            Text(
              'Your registration is confirmed immediately after you tap the button below.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 20),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.program.title,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 16),
                    _SummaryRow(
                      icon: Icons.calendar_month_rounded,
                      label: 'Date',
                      value: formatProgramDate(widget.program.date),
                    ),
                    _SummaryRow(
                      icon: Icons.schedule_rounded,
                      label: 'Time',
                      value: widget.program.time,
                    ),
                    _SummaryRow(
                      icon: Icons.location_on_outlined,
                      label: 'Location',
                      value: widget.program.location,
                    ),
                    _SummaryRow(
                      icon: Icons.person_outline_rounded,
                      label: 'Student',
                      value: widget.student.fullName,
                      isLast: true,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: const Color(0xFFF1ECFF),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.forward_to_inbox_rounded,
                    color: AppTheme.violet,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Parent will be notified',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          widget.student.parentEmail,
                          style: const TextStyle(
                            color: AppTheme.violet,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            const _CheckLine(text: 'Your place is reserved the moment you confirm'),
            const _CheckLine(text: 'Only one place per student – no double booking'),
            const _CheckLine(text: 'No approval step is required'),
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
            onPressed: _loading ? null : _confirm,
            icon: _loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.check_rounded),
            label: Text(_loading ? 'Reserving your place...' : 'CONFIRM JOIN'),
          ),
        ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool isLast;

  const _SummaryRow({
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
          Icon(icon, size: 19, color: AppTheme.cobalt),
          const SizedBox(width: 10),
          SizedBox(
            width: 68,
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

class _CheckLine extends StatelessWidget {
  final String text;

  const _CheckLine({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        children: [
          const Icon(
            Icons.check_circle_rounded,
            color: AppTheme.success,
            size: 19,
          ),
          const SizedBox(width: 10),
          Text(text, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}
