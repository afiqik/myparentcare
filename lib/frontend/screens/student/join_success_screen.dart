import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../backend_logic/student_state.dart';
import '../../../database_storage/models.dart';
import '../../theme.dart';
import '../../widgets/app_components.dart';
import 'student_nav_layout.dart';

class JoinSuccessScreen extends StatelessWidget {
  final Program program;
  final AppUser student;
  final String emailStatus;

  const JoinSuccessScreen({
    super.key,
    required this.program,
    required this.student,
    required this.emailStatus,
  });

  void _openTab(BuildContext context, int index) {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => StudentNavLayout(initialIndex: index)),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    // Status langsung: emel dihantar dalam beberapa saat oleh automasi.
    final status = context.select<StudentState, String>(
      (s) => s.participationFor(program.id)?.emailStatus ?? emailStatus,
    );
    final emailSent = status == 'sent';
    final emailFailed = status == 'failed';
    return Scaffold(
      body: SafeArea(
        child: PageBackdrop(
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              children: [
                const Spacer(),
                Container(
                  width: 98,
                  height: 98,
                  decoration: BoxDecoration(
                    color: AppTheme.success.withValues(alpha: 0.11),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check_rounded,
                    color: AppTheme.success,
                    size: 52,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  "You're in!",
                  style: Theme.of(context).textTheme.displaySmall,
                ),
                const SizedBox(height: 10),
                Text(
                  'Your place is confirmed. No approval or attendance QR is needed.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: 28),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      children: [
                        Text(
                          program.title,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 16),
                        _ResultLine(
                          icon: Icons.calendar_month_rounded,
                          text:
                              '${formatProgramDate(program.date)} · ${program.time}',
                        ),
                        _ResultLine(
                          icon: Icons.location_on_outlined,
                          text: program.location,
                        ),
                        _ResultLine(
                          key: const Key('parent_email_status'),
                          icon: emailSent
                              ? Icons.mark_email_read_rounded
                              : emailFailed
                                  ? Icons.error_outline_rounded
                                  : Icons.schedule_send_rounded,
                          text: emailSent
                              ? 'Email sent to ${student.parentEmail}'
                              : emailFailed
                                  ? 'The email to ${student.parentEmail} could not be sent. Your place is still '
                                      'confirmed – check the parent email in Profile. The admin has been notified.'
                                  : 'Sending the confirmation email to ${student.parentEmail}…',
                          color: emailSent
                              ? AppTheme.success
                              : emailFailed
                                  ? AppTheme.error
                                  : AppTheme.violet,
                          isLast: true,
                        ),
                      ],
                    ),
                  ),
                ),
                const Spacer(),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => _openTab(context, 2),
                    child: const Text('VIEW MY JOINED PROGRAMS'),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => _openTab(context, 0),
                    child: const Text('Back to home'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ResultLine extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;
  final bool isLast;

  const _ResultLine({
    super.key,
    required this.icon,
    required this.text,
    this.color = AppTheme.cobalt,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 12),
      child: Row(
        children: [
          Icon(icon, color: color, size: 19),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}
