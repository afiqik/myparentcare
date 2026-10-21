import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:my_parent_care/backend_logic/admin_state.dart';
import 'package:my_parent_care/database_storage/firestore_paths.dart';
import 'package:my_parent_care/database_storage/models.dart';
import 'package:my_parent_care/frontend/screens/admin/admin_nav_layout.dart';
import 'package:my_parent_care/frontend/screens/admin/admin_programs_screen.dart';
import 'package:my_parent_care/frontend/screens/admin/create_program_screen.dart';
import 'package:my_parent_care/frontend/screens/admin/participant_list_screen.dart';
import 'package:my_parent_care/frontend/screens/admin/program_detail_admin.dart';
import 'package:my_parent_care/frontend/screens/auth/welcome_screen.dart';
import 'package:provider/provider.dart';

import '../support/fakes.dart';
import '../support/platform_fakes.dart';
import '../support/widget_harness.dart';

Uint8List smallPng() => Uint8List.fromList(img.encodePng(img.Image(width: 8, height: 8)));

Future<List<Map<String, dynamic>>> programDocs(TestHarness h) async =>
    (await h.firestore.collection(FirestorePaths.programs).get()).docs.map((d) => d.data()).toList();

Future<void> navTo(WidgetTester tester, String label) async {
  await tester.pump(const Duration(seconds: 1)); // tunggu animasi halaman tamat
  await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text(label)));
  await settle(tester);
}

void main() {
  late PlatformFakes fakes;

  setUp(() => fakes = setUpWidgetTest());

  // ================================================================ nav + dashboard

  group('Admin: navigasi & papan pemuka', () {
    testWidgets('5 tab berfungsi; tab Programs ada butang "Create program"', (tester) async {
      final h = await adminHarness();
      await h.programs.createProgram(TestHarness.program(title: 'Futsal Night'), adminUid: 'admin1');
      await pumpScreen(tester, h, const AdminNavLayout());
      expect(find.text('Admin command centre'), findsOneWidget);
      expect(find.text('Open programs'), findsOneWidget);

      await navTo(tester, 'Programs');
      expect(find.text('Futsal Night'), findsOneWidget);
      expect(find.text('Create program'), findsOneWidget);
      await tester.tap(find.text('Create program'));
      await settle(tester);
      expect(find.text('New program'), findsOneWidget);
      await tester.pageBack();
      await settle(tester);

      await navTo(tester, 'Email');
      expect(find.text('Email centre'), findsWidgets);
      await navTo(tester, 'Reports');
      expect(find.text('Choose report'), findsOneWidget);
      await navTo(tester, 'Tools');
      expect(find.text('Users & roles'), findsOneWidget);
      // Ruang kerja RTDB disambung automatik untuk super admin.
      expect(h.workspace.presenceMap.containsKey('admin1'), isTrue);
    });

    testWidgets('akaun bukan admin dikeluarkan dari ruang admin', (tester) async {
      final h = await studentHarness();
      await pumpScreen(tester, h, const AdminNavLayout());
      await settle(tester);
      expect(find.byType(WelcomeScreen), findsOneWidget);
      expect(h.auth.currentUser, isNull);
    });

    testWidgets('amaran: kunci tiada, emel gagal, automasi terhenti, backup, program hampir penuh', (tester) async {
      final h = await adminHarness();
      h.workspace.emailJsKey = null;
      final program = await h.programs.createProgram(
        TestHarness.program(title: 'Seminar Popular', capacity: 10),
        adminUid: 'admin1',
      );
      for (var i = 0; i < 9; i++) {
        await h.programs.joinProgram(program: program, student: TestHarness.student(uid: 's$i'));
      }
      await h.firestore.collection(FirestorePaths.emailLogs).doc('f1').set({
        'id': 'f1', 'recipient': 'p@x.com', 'subject': 's', 'body': 'b', 'status': 'failed',
        'errorMessage': 'bad', 'studentName': 'A', 'studentUid': 's1', 'programId': program.id,
        'programTitle': 'Seminar Popular', 'type': 'join', 'createdBy': 'apps-script',
        'createdAt': Timestamp.now(), 'updatedAt': Timestamp.now(), 'attempts': 1,
      });
      h.workspace.setAutomation(const AutomationStatus(ok: false, code: '426', message: 'Kuota EmailJS telah habis.'));
      await pumpScreen(tester, h, const AdminNavLayout());
      await settle(tester);

      for (final text in [
        'EmailJS private key is missing',
        '1 parent emails failed',
        'Automatic parent emails are paused: Kuota EmailJS telah habis.',
        '9 parent emails are waiting',
        'No backup has been made yet',
        '"Seminar Popular" is 90% full.',
      ]) {
        await scrollTo(tester, find.textContaining(text));
        expect(find.textContaining(text), findsOneWidget, reason: text);
      }

      // Butiran automasi → Email settings.
      await tester.drag(find.byType(Scrollable).first, const Offset(0, 2000));
      await settle(tester, times: 2);
      await tapVisible(tester, find.text('Details'));
      expect(find.text('Email settings'), findsOneWidget);
    });

    testWidgets('tindakan pantas & "New program" dari papan pemuka', (tester) async {
      final h = await adminHarness();
      await pumpScreen(tester, h, const AdminNavLayout());
      await tapVisible(tester, find.text('Admin\ntools'));
      expect(find.text('Users & roles'), findsOneWidget);
      await navTo(tester, 'Overview');
      await tapVisible(tester, find.text('New program'));
      expect(find.text('Build something worth joining.'), findsOneWidget);
    });
  });

  // ================================================================ senarai program

  group('Admin: senarai program', () {
    testWidgets('cari, tapis status, kosong, buka butiran', (tester) async {
      final h = await adminHarness();
      await h.programs.createProgram(TestHarness.program(title: 'Futsal Night'), adminUid: 'admin1');
      await h.programs.createProgram(TestHarness.program(title: 'Career Draft', status: 'draft'), adminUid: 'admin1');
      await h.programs.createProgram(TestHarness.program(title: 'Old Talk', status: 'closed'), adminUid: 'admin1');
      await pumpScreen(tester, h, const Scaffold(body: AdminProgramsScreen()), attachAdmin: true);
      expect(find.text('Futsal Night'), findsOneWidget);
      expect(find.text('Career Draft'), findsOneWidget);
      expect(find.text('Old Talk'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'futsal');
      await settle(tester, times: 2);
      expect(find.text('Futsal Night'), findsOneWidget);
      expect(find.text('Career Draft'), findsNothing);

      await tester.enterText(find.byType(TextField), '');
      await tester.tap(find.text('DRAFT'));
      await settle(tester, times: 2);
      expect(find.text('Career Draft'), findsOneWidget);
      expect(find.text('Futsal Night'), findsNothing);

      await tester.tap(find.text('All'));
      await settle(tester, times: 2);
      await tester.enterText(find.byType(TextField), 'tiada program begini');
      await settle(tester, times: 2);
      expect(find.text('No programs found'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'old');
      await settle(tester, times: 2);
      await tapVisible(tester, find.text('Old Talk'));
      expect(find.byType(ProgramDetailAdmin), findsOneWidget);
      expect(find.text('VIEW PARTICIPANTS (0)'), findsOneWidget);
    });
  });

  // ================================================================ cipta / edit program

  group('Admin: cipta & edit program', () {
    Future<void> openCreate(WidgetTester tester, TestHarness h, {Program? edit}) async {
      await pumpScreen(
        tester,
        h,
        Launcher(builder: (_) => CreateProgramScreen(programToEdit: edit)),
        attachAdmin: true,
      );
      await tester.tap(find.byKey(const Key('launch')));
      await settle(tester);
    }

    Future<void> fillForm(WidgetTester tester, {String capacity = '40'}) async {
      await enterVisible(tester, find.byKey(const Key('program_title')), 'Bengkel Robotik');
      await enterVisible(tester, find.byKey(const Key('program_description')), 'Bina robot pertama anda.');
      await enterVisible(tester, find.byKey(const Key('program_location')), 'Makmal 3');
      await enterVisible(tester, find.byKey(const Key('program_capacity')), capacity);
    }

    testWidgets('borang kosong ditolak dengan mesej jelas', (tester) async {
      final h = await adminHarness();
      await openCreate(tester, h);
      await tapVisible(tester, find.byKey(const Key('program_save')));
      expect(find.text('Title is required'), findsOneWidget);
      expect(find.text('Description is required'), findsOneWidget);
      await enterVisible(tester, find.byKey(const Key('program_capacity')), '0');
      await tapVisible(tester, find.byKey(const Key('program_save')));
      await scrollTo(tester, find.text('Enter 1 or more'));
      expect(find.text('Enter 1 or more'), findsOneWidget);
      await enterVisible(tester, find.byKey(const Key('program_capacity')), '6000');
      await tapVisible(tester, find.byKey(const Key('program_save')));
      await scrollTo(tester, find.text('Maximum 5000'));
      expect(find.text('Maximum 5000'), findsOneWidget);
      expect(await programDocs(h), isEmpty);
    });

    testWidgets('terbit program dengan gambar & video → muncul untuk pelajar', (tester) async {
      final h = await adminHarness();
      fakes.imagePicker.next = smallPng();
      await openCreate(tester, h);
      await fillForm(tester);

      await tapVisible(tester, find.text('Add image'));
      expect(fakes.imagePicker.calls, 1);
      expect(find.text('Cover image'), findsOneWidget);
      expect(find.textContaining('Image uploaded'), findsOneWidget);
      await clearSnackBars(tester);

      await tapVisible(tester, find.text('Add video link'));
      await tester.enterText(find.widgetWithText(TextFormField, 'https:// link'), 'bukan pautan');
      await tester.tap(find.widgetWithText(FilledButton, 'Add'));
      await settle(tester, times: 2);
      expect(find.byType(AlertDialog), findsOneWidget, reason: 'pautan tidak sah ditolak');
      await tester.enterText(find.widgetWithText(TextFormField, 'https:// link'), 'https://youtu.be/dQw4w9WgXcQ');
      await tester.tap(find.widgetWithText(FilledButton, 'Add'));
      await settle(tester);

      await tapVisible(tester, find.byKey(const Key('program_save')));
      expect(find.textContaining('Program published to the Student App.'), findsOneWidget);
      expect(find.byKey(const Key('launch')), findsOneWidget, reason: 'skrin ditutup selepas simpan');

      final saved = (await programDocs(h)).single;
      expect(saved['title'], 'Bengkel Robotik');
      expect(saved['location'], 'Makmal 3');
      expect(saved['capacity'], 40);
      expect(saved['status'], 'open');
      expect(saved['coverMediaId'], isNotEmpty);
      expect((saved['gallery'] as List), hasLength(2));
      final catalog = (await tester.runAsync(() => h.programs.watchCatalog().first))!;
      expect(catalog.programs.single.title, 'Bengkel Robotik');
    });

    testWidgets('simpan sebagai draf → tidak kelihatan kepada pelajar', (tester) async {
      final h = await adminHarness();
      await openCreate(tester, h);
      await fillForm(tester);
      await tapVisible(tester, find.text('OPEN'));
      await tester.tap(find.text('DRAFT').last);
      await settle(tester, times: 2);
      await settle(tester, times: 2);
      expect(find.text('SAVE DRAFT'), findsOneWidget);
      await tapVisible(tester, find.byKey(const Key('program_save')));
      expect((await programDocs(h)).single['status'], 'draft');
      expect((await tester.runAsync(() => h.programs.watchCatalog().first))!.programs, isEmpty);
    });

    testWidgets('edit program: tukar lokasi; kapasiti < peserta ditolak', (tester) async {
      final h = await adminHarness();
      final program = await h.programs.createProgram(TestHarness.program(capacity: 5), adminUid: 'admin1');
      for (final uid in ['a', 'b']) {
        await h.saveUser(TestHarness.student(uid: uid));
        await h.programs.joinProgram(program: program, student: TestHarness.student(uid: uid));
      }
      await openCreate(tester, h, edit: program.copyWith(joinedCount: 2));
      expect(find.text('Edit program'), findsOneWidget);

      await enterVisible(tester, find.byKey(const Key('program_capacity')), '1');
      await tapVisible(tester, find.byKey(const Key('program_save')));
      expect(find.textContaining('cannot be lower than 2 joined students'), findsOneWidget);
      await clearSnackBars(tester);

      await enterVisible(tester, find.byKey(const Key('program_capacity')), '5');
      await enterVisible(tester, find.byKey(const Key('program_location')), 'Dewan Baharu');
      await tapVisible(tester, find.byKey(const Key('program_save')));
      expect(find.textContaining('2 participants notified'), findsWidgets);
      expect((await programDocs(h)).single['location'], 'Dewan Baharu');
    });

    testWidgets('pemilih tarikh & masa', (tester) async {
      final h = await adminHarness();
      await openCreate(tester, h);
      await tapVisible(tester, find.text('Date'));
      expect(find.byType(DatePickerDialog), findsOneWidget);
      await tester.tap(find.descendant(of: find.byType(DatePickerDialog), matching: find.text('OK')));
      await settle(tester);
      expect(find.byType(DatePickerDialog), findsNothing);
      await tapVisible(tester, find.text('Time'));
      expect(find.byType(TimePickerDialog), findsOneWidget);
      await tester.tap(find.descendant(of: find.byType(TimePickerDialog), matching: find.text('OK')));
      await settle(tester);
      expect(find.byType(TimePickerDialog), findsNothing);
    });
  });

  // ================================================================ tindakan program

  group('Admin: tindakan program (menu)', () {
    Future<Program> openDetail(WidgetTester tester, TestHarness h, {String status = 'open', bool joined = true}) async {
      final program = await h.programs.createProgram(
        TestHarness.program(title: 'Hari Sukan', capacity: 5, status: status),
        adminUid: 'admin1',
      );
      if (joined) {
        await h.saveUser(TestHarness.student());
        await h.programs.joinProgram(program: program, student: TestHarness.student());
      }
      await pumpScreen(
        tester,
        h,
        Launcher(builder: (_) => ProgramDetailAdmin(program: program)),
        attachAdmin: true,
      );
      await tester.tap(find.byKey(const Key('launch')));
      await settle(tester);
      return program;
    }

    Future<void> menu(WidgetTester tester, String item) async {
      await tester.tap(find.byTooltip('Program actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(item).last);
      await tester.pumpAndSettle();
      await settle(tester);
    }

    Future<String> statusOf(TestHarness h, String id) async =>
        (await h.firestore.doc(FirestorePaths.program(id)).get()).data()!['status'] as String;

    testWidgets('butiran program dipaparkan', (tester) async {
      final h = await adminHarness();
      await openDetail(tester, h);
      expect(find.text('Hari Sukan'), findsOneWidget);
      expect(find.text('Dewan Utama'), findsOneWidget);
      expect(find.text('Jumpa majikan'), findsOneWidget);
      expect(find.text('Students joined'), findsOneWidget);
      expect(find.textContaining('Editing or cancelling this program notifies'), findsOneWidget);
    });

    testWidgets('tutup → buka semula → tandakan selesai', (tester) async {
      final h = await adminHarness();
      final program = await openDetail(tester, h);
      await menu(tester, 'Close registration');
      await tester.tap(find.text('Confirm'));
      await settle(tester);
      expect(await statusOf(h, program.id), 'closed');
      expect(find.text('Registration closed.'), findsOneWidget);
      await clearSnackBars(tester);

      await menu(tester, 'Open registration');
      expect(await statusOf(h, program.id), 'open');

      await menu(tester, 'Mark completed');
      expect(await statusOf(h, program.id), 'completed');
    });

    testWidgets('arkib (dengan pengesahan) & salin sebagai draf', (tester) async {
      final h = await adminHarness();
      final program = await openDetail(tester, h);
      await menu(tester, 'Duplicate');
      expect(find.text('A draft copy was created.'), findsOneWidget);
      await clearSnackBars(tester);
      expect((await programDocs(h)).where((p) => p['status'] == 'draft'), hasLength(1));

      await menu(tester, 'Archive');
      await tester.tap(find.text('Back'));
      await settle(tester);
      expect(await statusOf(h, program.id), 'open', reason: 'dibatalkan oleh admin');
      await menu(tester, 'Archive');
      await tester.tap(find.text('Confirm'));
      await settle(tester);
      expect(await statusOf(h, program.id), 'archived');
    });

    testWidgets('batal program dengan sebab → pelajar & ibu bapa dimaklumkan', (tester) async {
      final h = await adminHarness();
      final program = await openDetail(tester, h);
      await menu(tester, 'Cancel program');
      await tester.enterText(find.widgetWithText(TextField, 'Cancellation reason'), 'Hujan lebat');
      await tester.tap(find.widgetWithText(FilledButton, 'Cancel program'));
      await settle(tester);
      expect(await statusOf(h, program.id), 'cancelled');
      expect(find.textContaining('1 students notified'), findsOneWidget);
      expect(find.text('Hujan lebat'), findsOneWidget);
      final queued = await h.email.fetchLogs();
      expect(queued.single.type, 'cancelled');
      expect(queued.single.status, 'queued');
    });

    testWidgets('padam kekal (amaran peserta) → kembali ke skrin sebelum', (tester) async {
      final h = await adminHarness();
      await openDetail(tester, h);
      await menu(tester, 'Delete permanently');
      expect(find.textContaining('This program has 1 joined students'), findsOneWidget);
      await tester.tap(find.text('Confirm'));
      await settle(tester);
      expect(await programDocs(h), isEmpty);
      expect(find.byKey(const Key('launch')), findsOneWidget);
    });

    testWidgets('edit dari menu & lihat peserta', (tester) async {
      final h = await adminHarness();
      await openDetail(tester, h);
      await menu(tester, 'Edit program');
      expect(find.byType(CreateProgramScreen), findsOneWidget);
      await tester.pageBack();
      await settle(tester);
      await tapVisible(tester, find.text('VIEW PARTICIPANTS (1)'));
      expect(find.byType(ParticipantListScreen), findsOneWidget);
    });
  });

  // ================================================================ peserta

  group('Admin: senarai peserta', () {
    Future<Program> openList(WidgetTester tester, TestHarness h) async {
      final program = await h.programs.createProgram(TestHarness.program(capacity: 5), adminUid: 'admin1');
      await h.saveUser(TestHarness.student(uid: 'a', fullName: 'Aiman'));
      await h.programs.joinProgram(program: program, student: TestHarness.student(uid: 'a', fullName: 'Aiman'));
      final tricky = TestHarness.student(uid: 'b', fullName: '=HYPERLINK("x")');
      await h.saveUser(tricky);
      await h.programs.joinProgram(program: program, student: tricky);
      await h.firestore.doc(FirestorePaths.participant(program.id, 'b')).update({'course': 'Accounting'});
      await pumpScreen(tester, h, ParticipantListScreen(program: program), attachAdmin: true);
      return program;
    }

    testWidgets('cari, tapis kursus, eksport CSV (selamat daripada suntikan formula)', (tester) async {
      final h = await adminHarness();
      final program = await openList(tester, h);
      expect(find.text('2 of 2 students'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'aiman');
      await settle(tester, times: 2);
      expect(find.text('1 of 2 students'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '');
      await settle(tester, times: 2);

      await tester.tap(find.widgetWithText(DropdownButtonFormField<String>, 'All').first);
      await settle(tester, times: 2);
      await tester.tap(find.text('Accounting').last);
      await settle(tester, times: 2);
      expect(find.text('1 of 2 students'), findsOneWidget);

      await tapVisible(tester, find.text('Export CSV'));
      expect(fakes.share.lastName, startsWith('participants_${program.id}_'));
      final bytes = await fakes.share.lastBytes();
      expect(bytes.take(3), [0xEF, 0xBB, 0xBF], reason: 'BOM UTF-8 supaya Excel memaparkan huruf betul');
      final csv = utf8.decode(bytes.skip(3).toList());
      expect(csv, startsWith('Student Name,Matric No'));
      expect(csv, contains('"Aiman"'));
      expect(csv, contains('"\'=HYPERLINK(""x"")"'));
      expect(csv, contains('parent.a@example.com'));
    });

    testWidgets('hantar semula emel & buang peserta', (tester) async {
      final h = await adminHarness();
      final program = await openList(tester, h);
      await tester.enterText(find.byType(TextField), 'aiman');
      await settle(tester, times: 2);
      await tapVisible(tester, find.text('Aiman'));

      await tapVisible(tester, find.text('Resend email'));
      expect(find.text('Parent email resent.'), findsOneWidget);
      expect(h.gateway.sent.single.to, 'parent.a@example.com');
      await clearSnackBars(tester);

      h.gateway.fail = true;
      await tapVisible(tester, find.text('Resend email'));
      expect(find.text('Email failed again.'), findsOneWidget);
      await clearSnackBars(tester);

      await tapVisible(tester, find.text('Remove'));
      await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
      await settle(tester);
      expect(find.textContaining('Aiman removed'), findsOneWidget);
      expect((await h.programs.fetchParticipants(program.id)).map((p) => p.studentUid), ['b']);
      final state = tester.element(find.byType(ParticipantListScreen)).read<AdminState>();
      expect(state.audit.map((e) => e.action), contains('participant.remove'));
    });
  });
}
