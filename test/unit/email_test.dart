import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:my_parent_care/api/email_gateway.dart';
import 'package:my_parent_care/api/email_templates.dart';
import 'package:my_parent_care/app_config.dart';
import 'package:my_parent_care/database_storage/models.dart';

import '../support/fakes.dart';

void main() {
  final message = EmailTemplates.join(
    parentEmail: 'parent@example.com',
    studentName: 'Nur Aina',
    program: TestHarness.program(id: 'p1'),
  );

  group('EmailJsGateway (keselamatan kunci)', () {
    test('private key dihantar HANYA apabila ditetapkan (peranti admin)', () async {
      late Map<String, dynamic> body;
      final gateway = EmailJsGateway(
        client: MockClient((request) async {
          body = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response('OK', 200);
        }),
      );
      expect(gateway.hasPrivateKey, isFalse);
      gateway.setPrivateKey('  admin-only-key-123  ');
      expect(gateway.hasPrivateKey, isTrue);
      await gateway.send(message);
      expect(body['accessToken'], 'admin-only-key-123');
      gateway.setPrivateKey(null);
      await gateway.send(message);
      expect(body.containsKey('accessToken'), isFalse);
    });

    test('ralat strict mode memberitahu admin di mana menetapkan private key', () {
      final text = EmailJsGateway.describeError(
        403,
        'API access in strict mode, but no Private Key was provided',
      );
      expect(text, contains('Email settings'));
    });

    test('tanpa kunci ditetapkan, tiada private key / accessToken dihantar', () async {
      late Map<String, dynamic> body;
      final gateway = EmailJsGateway(
        client: MockClient((request) async {
          body = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response('OK', 200);
        }),
      );
      final result = await gateway.send(message);
      expect(result.success, isTrue);
      expect(body.containsKey('accessToken'), isFalse);
      expect(body['user_id'], AppConfig.emailJsPublicKey);
      expect(body['template_params']['to_email'], 'parent@example.com');
      expect(jsonEncode(body), isNot(contains('bEx3oNwod4FPBKQuTDZId')));
    });

    test('ralat EmailJS diterjemah dan ditanda kekal/sementara', () async {
      Future<EmailSendResult> sendWith(int status) => EmailJsGateway(
        client: MockClient((_) async => http.Response('nope', status)),
      ).send(message);

      final forbidden = await sendWith(403);
      expect(forbidden.success, isFalse);
      expect(forbidden.permanent, isTrue);
      expect(forbidden.error, contains('non-browser'));

      final quota = await sendWith(426);
      expect(quota.error, contains('Kuota'));

      final rate = await sendWith(429);
      expect(rate.permanent, isFalse);
    });

    test('ralat rangkaian tidak merosakkan aplikasi', () async {
      final gateway = EmailJsGateway(
        client: MockClient((_) async => throw http.ClientException('offline')),
      );
      final result = await gateway.send(message);
      expect(result.success, isFalse);
      expect(result.error, contains('Rangkaian'));
    });
  });

  group('EmailTemplates', () {
    test('emel pengesahan mengandungi butiran program', () {
      expect(message.subject, contains('Nur Aina'));
      expect(message.body, contains('Dewan Utama'));
      expect(message.type, 'join');
    });

    test('sebab pembatalan dihadkan panjangnya', () {
      final cancelled = EmailTemplates.cancelled(
        participant: const Participant(
          studentUid: 's',
          studentName: 'Aina',
          studentEmail: 'a@b.com',
          parentEmail: 'p@b.com',
          joinedAt: '',
        ),
        program: TestHarness.program(),
        reason: 'x' * 1000,
      );
      expect(cancelled.reason.length, lessThanOrEqualTo(301));
      expect(cancelled.type, 'cancelled');
    });
  });
}
