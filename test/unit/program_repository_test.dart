import 'package:flutter_test/flutter_test.dart';
import 'package:my_parent_care/database_storage/models.dart';
import 'package:my_parent_care/database_storage/program_repository.dart';

import '../support/fakes.dart';

void main() {
  late TestHarness h;

  setUp(() => h = TestHarness());

  Future<Program> createOpen({int capacity = 3, String status = 'open'}) =>
      h.programs.createProgram(
        TestHarness.program(capacity: capacity, status: status),
        adminUid: 'admin1',
      );

  test('cipta program: dokumen penuh, shard kaunter dan entri katalog', () async {
    final program = await createOpen(capacity: 25);
    expect(program.id, isNotEmpty);
    expect(program.seatShards, 3);
    final shards = await h.programs.fetchShards(program.id);
    expect(shards.fold<int>(0, (s, x) => s + x.cap), 25);
    final catalog = await h.programs.watchCatalog().first;
    expect(catalog.programs.single.id, program.id);
  });

  test('draf tidak dipaparkan dalam katalog pelajar sehingga dibuka', () async {
    final draft = await createOpen(status: 'draft');
    expect((await h.programs.watchCatalog().first).programs, isEmpty);
    await h.programs.setStatus(draft, 'open');
    expect((await h.programs.watchCatalog().first).programs.single.status, 'open');
    await h.programs.setStatus(draft, 'archived');
    expect((await h.programs.watchCatalog().first).programs, isEmpty);
  });

  test('sertai program: berjaya, kemudian "sudah sertai"', () async {
    final program = await createOpen();
    final student = TestHarness.student();
    final first = await h.programs.joinProgram(program: program, student: student);
    expect(first.code, JoinCode.success);
    expect(first.participant!.seatShard, isNotEmpty);
    final again = await h.programs.joinProgram(program: program, student: student);
    expect(again.code, JoinCode.alreadyJoined);
    expect((await h.programs.fetchSeatSummary(program.id)).joined, 1);
  });

  test('tiada overbooking: pelajar ke-(kapasiti+1) mendapat "penuh"', () async {
    final program = await createOpen(capacity: 3);
    final codes = <JoinCode>[];
    for (var i = 0; i < 5; i++) {
      final result = await h.programs.joinProgram(
        program: program,
        student: TestHarness.student(uid: 'stu$i', email: 's$i@student.test'),
      );
      codes.add(result.code);
    }
    expect(codes.where((c) => c == JoinCode.success).length, 3);
    expect(codes.where((c) => c == JoinCode.full).length, 2);
    final summary = await h.programs.fetchSeatSummary(program.id);
    expect(summary.joined, 3);
    expect((await h.programs.fetchParticipants(program.id)).length, 3);
  });

  test('program ditutup tidak boleh disertai', () async {
    final program = await createOpen();
    final closed = await h.programs.setStatus(program, 'closed');
    final result = await h.programs.joinProgram(program: closed, student: TestHarness.student());
    expect(result.code, JoinCode.unavailable);
  });

  test('ubah kapasiti menyusun semula shard tanpa kehilangan kiraan', () async {
    final program = await createOpen(capacity: 3);
    await h.programs.joinProgram(program: program, student: TestHarness.student(uid: 'a'));
    await h.programs.joinProgram(program: program, student: TestHarness.student(uid: 'b'));
    final updated = await h.programs.updateProgram(program.copyWith(capacity: 40, title: 'Baharu'));
    final summary = await h.programs.fetchSeatSummary(program.id);
    expect(summary.capacity, 40);
    expect(summary.joined, 2);
    expect(updated.seatShards, greaterThan(1));
    expect((await h.programs.watchCatalog().first).programs.single.title, 'Baharu');
  });

  test('kapasiti tidak boleh diturunkan di bawah bilangan peserta', () async {
    final program = await createOpen(capacity: 3);
    await h.programs.joinProgram(program: program, student: TestHarness.student(uid: 'a'));
    await h.programs.joinProgram(program: program, student: TestHarness.student(uid: 'b'));
    expect(
      () => h.programs.updateProgram(program.copyWith(capacity: 1)),
      throwsArgumentError,
    );
  });

  test('buang peserta: tempat dibuka semula dan pelajar dimaklumkan', () async {
    final program = await createOpen(capacity: 1);
    final student = TestHarness.student();
    await h.saveUser(student);
    final joined = await h.programs.joinProgram(program: program, student: student);
    final participant = (await h.programs.fetchParticipants(program.id)).single;
    expect(participant.seatShard, joined.participant!.seatShard);
    await h.programs.removeParticipant(program: program, participant: participant);
    expect((await h.programs.fetchSeatSummary(program.id)).joined, 0);
    final notes = await h.users.fetchNotifications(student.uid);
    expect(notes.single.type, 'removed');
    expect((await h.users.fetch(student.uid))!.unreadNotifications, 1);
  });

  test('notifikasi pukal kepada semua peserta', () async {
    final program = await createOpen(capacity: 5);
    for (var i = 0; i < 3; i++) {
      final s = TestHarness.student(uid: 'n$i');
      await h.saveUser(s);
      await h.programs.joinProgram(program: program, student: s);
    }
    final participants = await h.programs.fetchParticipants(program.id);
    final sent = await h.programs.notifyParticipants(
      participants: participants,
      type: 'update',
      title: 'Tukar masa',
      message: 'Masa baharu 10:00',
      programId: program.id,
    );
    expect(sent, 3);
    for (var i = 0; i < 3; i++) {
      expect((await h.users.fetchNotifications('n$i')).single.title, 'Tukar masa');
    }
  });

  test(
    'sejarah penyertaan pelajar melalui collection group',
    () async {
      final p1 = await createOpen();
      final p2 = await createOpen();
      final student = TestHarness.student();
      await h.programs.joinProgram(program: p1, student: student);
      await h.programs.joinProgram(program: p2, student: student);
      final mine = await h.programs.fetchMyParticipations(student.uid);
      expect(mine.map((p) => p.programId).toSet(), {p1.id, p2.id});
    },
    // fake_cloud_firestore menggabungkan dokumen ber-ID sama merentas koleksi
    // dalam collectionGroup. Query ini disahkan terhadap emulator Firestore
    // sebenar dalam tests/firebase/rules/firestore.test.mjs.
    skip: 'fake_cloud_firestore collectionGroup limitation – verified in emulator tests',
  );

  test('pelajar yang sama boleh menyertai beberapa program', () async {
    final p1 = await createOpen();
    final p2 = await createOpen();
    final student = TestHarness.student();
    expect((await h.programs.joinProgram(program: p1, student: student)).code, JoinCode.success);
    expect((await h.programs.joinProgram(program: p2, student: student)).code, JoinCode.success);
    expect((await h.programs.fetchParticipants(p1.id)).single.studentUid, student.uid);
    expect((await h.programs.fetchParticipants(p2.id)).single.studentUid, student.uid);
  });

  test('padam program membuang penyertaan, shard dan entri katalog', () async {
    final program = await createOpen();
    await h.programs.joinProgram(program: program, student: TestHarness.student());
    await h.programs.deleteProgram(program.id);
    expect(await h.programs.fetchParticipants(program.id), isEmpty);
    expect(await h.programs.fetchShards(program.id), isEmpty);
    expect((await h.programs.watchCatalog().first).programs, isEmpty);
  });

  test('pengumuman: hanya 20 terkini disimpan dalam katalog', () async {
    for (var i = 0; i < 23; i++) {
      await h.programs.addAnnouncement(Announcement(
        id: 'ann_${i.toString().padLeft(2, '0')}',
        title: 'Pengumuman $i',
        message: 'm',
        createdAt: '',
      ));
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
    final catalog = await h.programs.watchCatalog().first;
    expect(catalog.announcements.length, 20);
    await h.programs.deleteAnnouncement(catalog.announcements.first.id);
    expect((await h.programs.watchCatalog().first).announcements.length, 19);
  });

  test('ringkasan tempat admin (collection group shard)', () async {
    final program = await createOpen(capacity: 12);
    await h.programs.joinProgram(program: program, student: TestHarness.student());
    final summaries = await h.programs.watchAllSeatSummaries().first;
    expect(summaries[program.id]!.joined, 1);
    expect(summaries[program.id]!.capacity, 12);
  });
}
