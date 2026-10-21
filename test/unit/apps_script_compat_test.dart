import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_parent_care/api/email_gateway.dart';
import 'package:my_parent_care/api/email_templates.dart';
import 'package:my_parent_care/backend_logic/backup_service.dart';
import 'package:my_parent_care/database_storage/firestore_paths.dart';
import 'package:my_parent_care/database_storage/models.dart';

import '../support/fakes.dart';

/// Automasi Google Apps Script (apps_script/Code.gs) mesti menghasilkan emel
/// dan fail backup yang SAMA dengan aplikasi. Aplikasi ialah sumber rujukan:
/// ujian ini menjana `test/fixtures/email_parity.json` (UPDATE_FIXTURES=1) dan
/// ujian Node (tests/firebase/apps_script) menyemak skrip terhadap fail itu.
/// Sebaliknya, `apps_script_backup.json` dijana oleh skrip dan dipulihkan di sini.
void main() {
  group('Pariti emel dengan Apps Script', () {
    final fixture = File('test/fixtures/email_parity.json');

    Map<String, dynamic> generate() {
      final cases = [
        {
          'parentEmail': 'parent@example.com',
          'studentName': 'Nur Aina',
          'program': {'title': 'Career Day', 'date': '2026-12-01', 'time': '09:00', 'location': 'Main Hall'},
        },
        {
          'parentEmail': 'ibu.bapa@gmail.com',
          'studentName': 'Siti Nur’Aisyah binti Ahmad',
          'program': {
            'title': 'Hari Kerjaya & Keusahawanan "2026"',
            'date': '2026-11-15',
            'time': '8:30 pagi – 1:00 petang',
            'location': 'Dewan Utama, Aras 2\nBlok B',
          },
        },
        {
          'parentEmail': 'long@example.com',
          'studentName': 'A' * 190,
          'program': {'title': 'T' * 130, 'date': '', 'time': '', 'location': ''},
        },
      ];
      final gateway = EmailJsGateway()..setPrivateKey('fixture-private-key');
      return {
        'cases': [
          for (final c in cases)
            () {
              final p = c['program'] as Map<String, String>;
              final message = EmailTemplates.join(
                parentEmail: c['parentEmail'] as String,
                studentName: c['studentName'] as String,
                program: Program(
                  id: 'p1',
                  title: p['title']!,
                  description: '',
                  date: p['date']!,
                  time: p['time']!,
                  location: p['location']!,
                  capacity: 10,
                  category: 'Academic',
                ),
              );
              return {'input': c, 'payload': gateway.buildPayload(message)};
            }(),
        ],
        'errors': [
          for (final e in [
            [400, 'The template ID is invalid'],
            [403, 'API access in strict mode, but no Private Key was provided'],
            [403, 'API calls are disabled for non-browser applications'],
            [412, 'Gmail_API: Invalid grant'],
            [426, 'Account quota exceeded'],
            [429, 'Too many requests'],
            [500, 'x' * 250],
          ])
            {
              'status': e[0],
              'body': e[1],
              'message': EmailJsGateway.describeError(e[0] as int, e[1] as String),
            },
        ],
      };
    }

    test('fixture sepadan dengan templat & EmailJS aplikasi', () {
      final generated = generate();
      if (Platform.environment['UPDATE_FIXTURES'] == '1') {
        fixture.writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(generated)}\n');
      }
      expect(jsonDecode(fixture.readAsStringSync()), generated,
          reason: 'Templat emel berubah – jalankan UPDATE_FIXTURES=1 flutter test '
              'test/unit/apps_script_compat_test.dart, kemudian kemas kini apps_script/Code.gs');
    });
  });

  group('Backup Apps Script boleh dipulihkan oleh aplikasi', () {
    late Map<String, dynamic> backup;

    setUp(() {
      final bytes = File('test/fixtures/apps_script_backup.json').readAsBytesSync();
      backup = BackupService.parse(Uint8List.fromList(bytes));
    });

    test('format, ringkasan dan tiada private key', () {
      final summary = BackupService.summarize(backup);
      expect(summary.counts['users'], 4);
      expect(summary.counts['participants'], 2);
      expect(summary.counts['program_seats'], 3);
      expect(summary.counts['media'], 1);
      expect(summary.createdBy, contains('(automatik)'));
      final raw = File('test/fixtures/apps_script_backup.json').readAsStringSync();
      expect(raw, isNot(contains('fixture-secret-key')));
      expect((backup['rtdb'] as Map)['admin_workspace'], isNot(contains('settings')));
    });

    test('pulih ke Firestore: Timestamp, Blob dan model aplikasi sah', () async {
      final h = TestHarness();
      final written = await BackupService(h.firestore, h.workspace).restore(backup);
      expect(written, BackupService.summarize(backup).documents);

      final alice = await h.users.fetch('alice');
      expect(alice!.fullName, 'Nur Aina');
      expect(alice.parentEmail, 'parent@example.com');

      final participants = await h.programs.fetchParticipants('p1');
      expect(participants.map((p) => p.studentUid), containsAll(['alice', 'bob']));
      final raw = await h.firestore.doc(FirestorePaths.participant('p1', 'alice')).get();
      expect(raw.data()!['joinedAt'], isA<Timestamp>());

      final media = await h.firestore.collection(FirestorePaths.media).get();
      expect((media.docs.single.data()['bytes'] as Blob).bytes, [137, 80, 78, 71, 1, 2, 3]);

      final logs = await h.firestore.collection(FirestorePaths.emailLogs).get();
      final log = EmailLog.fromMap(logs.docs.single.data());
      expect(log.status, 'sent');
      expect(log.createdAt, isNotEmpty);

      expect(h.workspace.restored!['admin_workspace']['notes'], isNotNull);
    });
  });
}
