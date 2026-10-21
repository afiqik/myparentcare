import '../database_storage/models.dart';
import 'email_gateway.dart';

/// Templat emel ibu bapa (Bahasa Melayu). Semua kandungan dijana di sini.
class EmailTemplates {
  EmailTemplates._();

  static String _clip(String value, int max) =>
      value.length <= max ? value : '${value.substring(0, max)}…';

  static EmailMessage join({
    required String parentEmail,
    required String studentName,
    required Program program,
  }) {
    return EmailMessage(
      to: parentEmail,
      type: 'join',
      studentName: studentName,
      programTitle: program.title,
      programDate: program.date,
      programTime: program.time,
      programLocation: program.location,
      subject: _clip('MyParentCare: Penyertaan $studentName disahkan', 200),
      body: '''
Salam sejahtera,

$studentName telah menyertai program berikut:

Program: ${program.title}
Tarikh: ${program.date}
Masa: ${program.time}
Lokasi: ${program.location}
Status: Disahkan

Ini ialah notifikasi automatik daripada MyParentCare. Jika anda tidak mengenali pelajar ini, sila abaikan emel ini.
'''.trim(),
    );
  }

  static EmailMessage update({
    required Participant participant,
    required Program program,
  }) {
    return EmailMessage(
      to: participant.parentEmail,
      type: 'update',
      studentName: participant.studentName,
      programTitle: program.title,
      programDate: program.date,
      programTime: program.time,
      programLocation: program.location,
      subject: _clip('MyParentCare: Maklumat ${program.title} dikemas kini', 200),
      body: '''
Salam sejahtera,

Maklumat program yang disertai oleh ${participant.studentName} telah dikemas kini.

Program: ${program.title}
Tarikh: ${program.date}
Masa: ${program.time}
Lokasi: ${program.location}

Sila simpan maklumat terbaharu ini.
'''.trim(),
    );
  }

  static EmailMessage cancelled({
    required Participant participant,
    required Program program,
    required String reason,
  }) {
    final safeReason = _clip(reason.trim(), 300);
    return EmailMessage(
      to: participant.parentEmail,
      type: 'cancelled',
      studentName: participant.studentName,
      programTitle: program.title,
      programDate: program.date,
      programTime: program.time,
      programLocation: program.location,
      reason: safeReason,
      subject: _clip('MyParentCare: Program ${program.title} dibatalkan', 200),
      body: '''
Salam sejahtera,

Program yang disertai oleh ${participant.studentName} telah dibatalkan.

Program: ${program.title}
Tarikh asal: ${program.date}
Sebab: $safeReason

Kami memohon maaf atas sebarang kesulitan.
'''.trim(),
    );
  }

  /// Emel ujian daripada Pusat Emel admin – mengesahkan EmailJS berfungsi.
  static EmailMessage test({required String to, required String adminName}) {
    final sentAt = DateTime.now().toIso8601String().substring(0, 16).replaceFirst('T', ' ');
    return EmailMessage(
      to: to,
      type: 'test',
      studentName: adminName,
      programTitle: 'Emel ujian MyParentCare',
      subject: 'MyParentCare: Emel ujian ($sentAt)',
      body: '''
Salam sejahtera,

Ini ialah emel ujian daripada Pusat Emel MyParentCare.

Jika anda menerima emel ini, penghantaran emel kepada ibu bapa berfungsi dengan betul.

Dihantar oleh: $adminName
Masa: $sentAt
'''.trim(),
    );
  }

  static EmailMessage fromLog(EmailLog log) => EmailMessage(
    to: log.recipient,
    subject: log.subject,
    body: log.body,
    type: log.type,
    studentName: log.studentName,
    programTitle: log.programTitle,
  );
}
