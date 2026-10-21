import 'dart:convert';

import 'package:http/http.dart' as http;

import '../app_config.dart';

/// Mesej emel berstruktur. Kandungan dibina oleh [EmailTemplates] – tiada teks
/// bebas daripada pengguna selain nama/sebab yang dihadkan panjangnya.
class EmailMessage {
  final String to;
  final String subject;
  final String body;
  final String type;
  final String studentName;
  final String programTitle;
  final String programDate;
  final String programTime;
  final String programLocation;
  final String reason;

  const EmailMessage({
    required this.to,
    required this.subject,
    required this.body,
    required this.type,
    required this.studentName,
    required this.programTitle,
    this.programDate = '',
    this.programTime = '',
    this.programLocation = '',
    this.reason = '',
  });
}

class EmailSendResult {
  final bool success;
  final String error;

  /// Ralat yang tidak akan berjaya jika dicuba semula (contoh: kuota habis).
  final bool permanent;

  const EmailSendResult.sent() : success = true, error = '', permanent = false;

  const EmailSendResult.failed(this.error, {this.permanent = false})
    : success = false;
}

abstract class EmailGateway {
  bool get isConfigured;

  /// Private key EmailJS (strict mode). Hanya ditetapkan pada peranti ADMIN,
  /// dibaca daripada ruang kerja admin RTDB – tidak pernah dalam APK.
  bool get hasPrivateKey;
  void setPrivateKey(String? key);

  Future<EmailSendResult> send(EmailMessage message);
}

/// Penghantaran melalui EmailJS REST API.
///
/// Keselamatan (versi Spark tanpa pelayan):
/// * Akaun EmailJS dalam strict mode: setiap permintaan perlukan private key.
/// * Private key TIDAK berada dalam APK. Admin menampalnya dalam aplikasi
///   (Tools → Email settings); ia disimpan dalam RTDB ruang kerja admin yang
///   hanya admin boleh baca, dan dimuatkan ke gerbang ini pada peranti admin.
/// * Oleh itu hanya aplikasi admin boleh menghantar emel; public key dalam APK
///   tidak boleh disalahgunakan.
class EmailJsGateway implements EmailGateway {
  final http.Client _client;
  final String serviceId;
  final String templateId;
  final String publicKey;
  final Uri endpoint;

  EmailJsGateway({
    http.Client? client,
    this.serviceId = AppConfig.emailJsServiceId,
    this.templateId = AppConfig.emailJsTemplateId,
    this.publicKey = AppConfig.emailJsPublicKey,
    String endpoint = AppConfig.emailJsEndpoint,
  }) : _client = client ?? http.Client(),
       endpoint = Uri.parse(endpoint);

  String? _privateKey;

  @override
  bool get isConfigured =>
      serviceId.isNotEmpty && templateId.isNotEmpty && publicKey.isNotEmpty;

  @override
  bool get hasPrivateKey => (_privateKey ?? '').isNotEmpty;

  @override
  void setPrivateKey(String? key) {
    final trimmed = key?.trim();
    _privateKey = (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }

  Map<String, dynamic> buildPayload(EmailMessage message) => {
    'service_id': serviceId,
    'template_id': templateId,
    'user_id': publicKey,
    if (hasPrivateKey) 'accessToken': _privateKey,
    'template_params': {
      'to_email': message.to,
      'subject': message.subject,
      'message': message.body,
      'student_name': message.studentName,
      'program_title': message.programTitle,
      'program_date': message.programDate,
      'program_time': message.programTime,
      'program_location': message.programLocation,
      'reason': message.reason,
      'type': message.type,
    },
  };

  @override
  Future<EmailSendResult> send(EmailMessage message) async {
    if (!isConfigured) {
      return const EmailSendResult.failed(
        'EmailJS belum dikonfigurasi.',
        permanent: true,
      );
    }
    try {
      final response = await _client
          .post(
            endpoint,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(buildPayload(message)),
          )
          .timeout(const Duration(seconds: 20));
      if (response.statusCode == 200) return const EmailSendResult.sent();
      return EmailSendResult.failed(
        describeError(response.statusCode, response.body),
        permanent: response.statusCode == 400 ||
            response.statusCode == 403 ||
            response.statusCode == 426,
      );
    } catch (error) {
      return EmailSendResult.failed('Rangkaian gagal: $error');
    }
  }

  /// Terjemah ralat EmailJS kepada mesej yang boleh diambil tindakan oleh admin.
  static String describeError(int status, String body) {
    final detail = body.length > 200 ? '${body.substring(0, 200)}…' : body;
    switch (status) {
      case 400:
        return 'EmailJS menolak permintaan (templat/ID salah): $detail';
      case 403:
        if (body.contains('strict mode') || body.contains('Private Key')) {
          return 'EmailJS memerlukan private key (strict mode). Tampal private key '
              'di Admin tools → Email settings: $detail';
        }
        return 'EmailJS menyekat permintaan. Aktifkan "API for non-browser '
            'applications" atau semak Allowed origins: $detail';
      case 412:
        return 'Perkhidmatan emel EmailJS perlu disambung semula: $detail';
      case 426:
        return 'Kuota EmailJS telah habis. Naik taraf pelan EmailJS: $detail';
      case 429:
        return 'Terlalu banyak permintaan. Cuba semula sebentar lagi.';
      default:
        return 'EmailJS ralat $status: $detail';
    }
  }
}
