import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../database_storage/models.dart';
import '../theme.dart';
import 'media_widgets.dart';

class AppMark extends StatelessWidget {
  final double size;
  final bool showName;

  const AppMark({super.key, this.size = 40, this.showName = true});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: size,
          height: size,
          padding: EdgeInsets.all(size * 0.08),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(size * 0.3),
            border: Border.all(color: AppTheme.border),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(size * 0.22),
            child: Image.asset(
              'assets/images/launcher_icon.png',
              fit: BoxFit.cover,
            ),
          ),
        ),
        if (showName) ...[
          const SizedBox(width: 10),
          const Text(
            'MyParentCare',
            style: TextStyle(
              color: AppTheme.ink,
              fontSize: 19,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.6,
            ),
          ),
        ],
      ],
    );
  }
}

class PageBackdrop extends StatelessWidget {
  final Widget child;

  const PageBackdrop({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned(
          top: -110,
          right: -90,
          child: Container(
            width: 260,
            height: 260,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [Color(0x3320A4F3), Color(0x0020A4F3)],
              ),
            ),
          ),
        ),
        Positioned(
          bottom: -130,
          left: -100,
          child: Container(
            width: 300,
            height: 300,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [Color(0x22F72568), Color(0x00F72568)],
              ),
            ),
          ),
        ),
        child,
      ],
    );
  }
}

class SectionTitle extends StatelessWidget {
  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  const SectionTitle({
    super.key,
    required this.title,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleLarge),
        ),
        if (actionLabel != null)
          TextButton(onPressed: onAction, child: Text(actionLabel!)),
      ],
    );
  }
}

class StatusPill extends StatelessWidget {
  final String status;
  final bool compact;

  const StatusPill({super.key, required this.status, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final color = statusColor(status);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 4 : 6,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.11),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        statusLabel(status),
        style: TextStyle(
          color: color,
          fontSize: compact ? 10 : 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.35,
        ),
      ),
    );
  }

  static Color statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'open':
      case 'sent':
      case 'joined':
        return AppTheme.success;
      case 'full':
      case 'pending':
      case 'queued':
      case 'sending':
        return AppTheme.warning;
      case 'cancelled':
      case 'failed':
      case 'suspended':
        return AppTheme.error;
      case 'active':
      case 'student':
        return AppTheme.success;
      case 'admin':
        return AppTheme.coral;
      case 'draft':
        return AppTheme.violet;
      case 'completed':
        return AppTheme.cobalt;
      case 'archived':
      case 'closed':
        return AppTheme.inkSoft;
      default:
        return AppTheme.cobalt;
    }
  }

  static String statusLabel(String status) {
    switch (status.toLowerCase()) {
      case 'open':
        return 'OPEN';
      case 'full':
        return 'FULL';
      case 'closed':
        return 'CLOSED';
      case 'cancelled':
        return 'CANCELLED';
      case 'completed':
        return 'COMPLETED';
      case 'archived':
        return 'ARCHIVED';
      case 'draft':
        return 'DRAFT';
      case 'sent':
        return 'SENT';
      case 'failed':
        return 'FAILED';
      case 'pending':
        return 'PENDING';
      case 'queued':
        return 'QUEUED';
      case 'sending':
        return 'SENDING';
      case 'suspended':
        return 'SUSPENDED';
      case 'active':
        return 'ACTIVE';
      case 'admin':
        return 'ADMIN';
      case 'student':
        return 'STUDENT';
      case 'joined':
        return 'JOINED';
      default:
        return status.toUpperCase();
    }
  }
}

class ProgramArtwork extends StatelessWidget {
  final Program program;
  final double height;
  final BorderRadius borderRadius;

  const ProgramArtwork({
    super.key,
    required this.program,
    this.height = 144,
    this.borderRadius = const BorderRadius.all(Radius.circular(18)),
  });

  @override
  Widget build(BuildContext context) {
    final color = AppTheme.categoryColor(program.category);
    return ClipRRect(
      borderRadius: borderRadius,
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: program.coverMediaId.isNotEmpty
            ? FirestoreImage(
                mediaId: program.coverMediaId,
                placeholder: _fallback(color),
                error: _fallback(color),
              )
            : _fallback(color),
      ),
    );
  }

  Widget _fallback(Color color) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color, color.withValues(alpha: 0.62)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            right: -20,
            bottom: -36,
            child: Icon(
              _categoryIcon(program.category),
              color: Colors.white.withValues(alpha: 0.18),
              size: 150,
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(18),
            child: Align(
              alignment: Alignment.topLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.32),
                  ),
                ),
                child: Text(
                  program.category.toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  IconData _categoryIcon(String category) {
    switch (category.toLowerCase()) {
      case 'sports':
        return Icons.sports_basketball_rounded;
      case 'leadership':
        return Icons.groups_2_rounded;
      case 'career':
        return Icons.work_rounded;
      case 'volunteer':
        return Icons.volunteer_activism_rounded;
      default:
        return Icons.school_rounded;
    }
  }
}

class ProgramCard extends StatelessWidget {
  final Program program;
  final VoidCallback onTap;
  final bool showArtwork;

  /// Pelajar tidak mendengar kaunter tempat secara langsung (jimat kuota);
  /// jika kiraan belum diketahui, hanya kapasiti dipaparkan.
  final bool seatsKnown;

  const ProgramCard({
    super.key,
    required this.program,
    required this.onTap,
    this.showArtwork = true,
    this.seatsKnown = true,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (showArtwork) ...[
                ProgramArtwork(program: program, height: 118),
                const SizedBox(height: 14),
              ],
              Row(
                children: [
                  Expanded(
                    child: Text(
                      program.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  const SizedBox(width: 12),
                  StatusPill(status: program.displayStatus, compact: true),
                ],
              ),
              const SizedBox(height: 10),
              _MetaLine(
                icon: Icons.calendar_month_rounded,
                text: '${formatProgramDate(program.date)} · ${program.time}',
              ),
              const SizedBox(height: 6),
              _MetaLine(
                icon: Icons.location_on_outlined,
                text: program.location,
              ),
              const SizedBox(height: 12),
              if (seatsKnown) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: program.fillRate,
                    minHeight: 5,
                    backgroundColor: AppTheme.border,
                    color: AppTheme.categoryColor(program.category),
                  ),
                ),
                const SizedBox(height: 7),
              ],
              Text(
                seatsKnown
                    ? '${program.remainingSlots} slot lagi · ${program.joinedCount}/${program.capacity} joined'
                    : 'Kapasiti ${program.capacity} pelajar',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppTheme.inkSoft,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class MetricCard extends StatelessWidget {
  final String value;
  final String label;
  final IconData icon;
  final Color color;

  const MetricCard({
    super.key,
    required this.value,
    required this.label,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        // Dalam grid (tinggi terhad) kandungan menyesuaikan ruang supaya label
        // panjang / teks besar tidak melimpah; dalam senarai saiz asal digunakan.
        child: LayoutBuilder(
          builder: (context, constraints) {
            final bounded = constraints.hasBoundedHeight;
            final labelText = Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            );
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: bounded ? MainAxisSize.max : MainAxisSize.min,
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.11),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: color, size: 20),
                ),
                if (bounded) const Spacer() else const SizedBox(height: 18),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(value, maxLines: 1, style: Theme.of(context).textTheme.headlineMedium),
                ),
                const SizedBox(height: 2),
                if (bounded) Flexible(child: labelText) else labelText,
              ],
            );
          },
        ),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppTheme.cobalt.withValues(alpha: 0.09),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: AppTheme.cobalt, size: 32),
            ),
            const SizedBox(height: 18),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            if (actionLabel != null) ...[
              const SizedBox(height: 20),
              TextButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}

class _MetaLine extends StatelessWidget {
  final IconData icon;
  final String text;

  const _MetaLine({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppTheme.inkSoft),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: AppTheme.inkSoft),
          ),
        ),
      ],
    );
  }
}

String formatProgramDate(String value) {
  final date = DateTime.tryParse(value);
  if (date == null) return value;
  return DateFormat('d MMM yyyy').format(date);
}

String formatDateTime(String value) {
  final date = DateTime.tryParse(value);
  if (date == null) return value;
  return DateFormat('d MMM yyyy, h:mm a').format(date.toLocal());
}

String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

void showSnack(BuildContext context, String message, {bool error = false}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      backgroundColor: error ? AppTheme.error : AppTheme.ink,
    ),
  );
}

Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
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
              child: Text(confirmLabel),
            ),
          ],
        ),
      ) ??
      false;
}

/// Satu medan dalam [showTextFieldsDialog].
class DialogField {
  final String label;
  final String initialValue;
  final String? Function(String?)? validator;
  final int? maxLength;
  final int minLines;
  final int maxLines;
  final TextInputType? keyboardType;
  final bool autofocus;
  final Key? key;

  const DialogField({
    required this.label,
    this.initialValue = '',
    this.validator,
    this.maxLength,
    this.minLines = 1,
    this.maxLines = 1,
    this.keyboardType,
    this.autofocus = false,
    this.key,
  });
}

/// Dialog borang ringkas. Pengawal teks dimiliki oleh dialog dan hanya
/// dilupuskan selepas animasi tutup selesai – melupuskannya serta-merta
/// selepas `showDialog` kembali menyebabkan ralat "used after being disposed".
/// Pulangkan nilai setiap medan, atau `null` jika dibatalkan.
Future<List<String>?> showTextFieldsDialog(
  BuildContext context, {
  required String title,
  String? intro,
  required List<DialogField> fields,
  required String confirmLabel,
  String cancelLabel = 'Cancel',
  bool destructive = false,
  Key? confirmKey,
}) {
  return showDialog<List<String>>(
    context: context,
    builder: (_) => _TextFieldsDialog(
      title: title,
      intro: intro,
      fields: fields,
      confirmLabel: confirmLabel,
      cancelLabel: cancelLabel,
      destructive: destructive,
      confirmKey: confirmKey,
    ),
  );
}

class _TextFieldsDialog extends StatefulWidget {
  final String title;
  final String? intro;
  final List<DialogField> fields;
  final String confirmLabel;
  final String cancelLabel;
  final bool destructive;
  final Key? confirmKey;

  const _TextFieldsDialog({
    required this.title,
    required this.intro,
    required this.fields,
    required this.confirmLabel,
    required this.cancelLabel,
    required this.destructive,
    required this.confirmKey,
  });

  @override
  State<_TextFieldsDialog> createState() => _TextFieldsDialogState();
}

class _TextFieldsDialogState extends State<_TextFieldsDialog> {
  final _formKey = GlobalKey<FormState>();
  late final List<TextEditingController> _controllers = [
    for (final field in widget.fields) TextEditingController(text: field.initialValue),
  ];

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState!.validate()) {
      Navigator.pop(context, [for (final c in _controllers) c.text]);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.intro != null) ...[
                Text(widget.intro!, style: const TextStyle(fontSize: 12, color: AppTheme.inkSoft)),
                const SizedBox(height: 12),
              ],
              for (var i = 0; i < widget.fields.length; i++)
                TextFormField(
                  key: widget.fields[i].key,
                  controller: _controllers[i],
                  autofocus: widget.fields[i].autofocus,
                  keyboardType: widget.fields[i].keyboardType,
                  maxLength: widget.fields[i].maxLength,
                  minLines: widget.fields[i].minLines,
                  maxLines: widget.fields[i].maxLines,
                  decoration: InputDecoration(
                    labelText: widget.fields[i].label,
                    alignLabelWithHint: widget.fields[i].maxLines > 1,
                  ),
                  validator: widget.fields[i].validator,
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(widget.cancelLabel),
        ),
        FilledButton(
          key: widget.confirmKey,
          style: widget.destructive ? FilledButton.styleFrom(backgroundColor: AppTheme.error) : null,
          onPressed: _submit,
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}

/// Jalur amaran kecil (luar talian, versi web ujian, dsb.).
class InfoBanner extends StatelessWidget {
  final IconData icon;
  final String message;
  final Color color;
  final String? actionLabel;
  final VoidCallback? onAction;

  const InfoBanner({
    super.key,
    required this.icon,
    required this.message,
    this.color = AppTheme.warning,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: AppTheme.ink,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (actionLabel != null)
            TextButton(onPressed: onAction, child: Text(actionLabel!)),
        ],
      ),
    );
  }
}
