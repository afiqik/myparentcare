import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_parent_care/database_storage/models.dart';

import '../support/fakes.dart';

void main() {
  group('AppUser', () {
    test('pelajar lengkap boleh menyertai; tidak lengkap tidak boleh', () {
      expect(TestHarness.student().canJoinPrograms, isTrue);
      expect(TestHarness.student(complete: false).canJoinPrograms, isFalse);
    });

    test('pelajar digantung dan admin tidak boleh menyertai program', () {
      expect(TestHarness.student().copyWith(status: 'suspended').canJoinPrograms, isFalse);
      expect(TestHarness.student().copyWith(role: 'admin').canJoinPrograms, isFalse);
    });

    test('emel ibu bapa tidak sah menjadikan maklumat ibu bapa tidak lengkap', () {
      expect(TestHarness.student().copyWith(parentEmail: 'bukan-emel').hasParentInfo, isFalse);
    });

    test('peratus profil dikira daripada medan sebenar', () {
      expect(AppUser.computeProfilePercent(TestHarness.student()), 100);
      final partial = TestHarness.student(complete: false);
      expect(AppUser.computeProfilePercent(partial), lessThan(100));
    });

    test('peranan tidak dikenali dibaca sebagai student (tidak boleh naik taraf sendiri)', () {
      final user = AppUser.fromMap({'uid': 'x', 'email': 'x@y.com', 'role': 'superuser'});
      expect(user.role, 'student');
    });

    test('toProfileMap tidak mengandungi role/status/email', () {
      final map = TestHarness.student().toProfileMap();
      expect(map.containsKey('role'), isFalse);
      expect(map.containsKey('status'), isFalse);
      expect(map.containsKey('email'), isFalse);
      expect(map['parentEmail'], 'parent.stu1@example.com');
    });
  });

  group('Program', () {
    test('penuh dikira daripada kaunter tempat', () {
      final p = TestHarness.program(capacity: 2).copyWith(joinedCount: 2);
      expect(p.isFull, isTrue);
      expect(p.displayStatus, 'full');
      expect(p.canJoin, isFalse);
      expect(p.remainingSlots, 0);
    });

    test('status "full" data lama dibaca sebagai open', () {
      final p = Program.fromMap({'id': 'x', 'status': 'full', 'capacity': 10});
      expect(p.status, 'open');
    });

    test('katalog hanya mengandungi status awam', () {
      expect(TestHarness.program(status: 'draft').isInCatalog, isFalse);
      expect(TestHarness.program(status: 'archived').isInCatalog, isFalse);
      for (final s in ['open', 'closed', 'cancelled', 'completed']) {
        expect(TestHarness.program(status: s).isInCatalog, isTrue, reason: s);
      }
    });

    test('hanya program dibuka dipaparkan dalam senarai pelajar', () {
      expect(TestHarness.program(status: 'open').isVisibleToStudents, isTrue);
      expect(TestHarness.program(status: 'closed').isVisibleToStudents, isFalse);
    });

    test('galeri media dibaca & ditulis', () {
      final p = TestHarness.program().copyWith(
        gallery: const [
          MediaRef(id: 'm1', kind: 'image'),
          MediaRef(id: 'v1', kind: 'video', url: 'https://youtu.be/abc'),
        ],
      );
      final back = Program.fromMap(p.toMap());
      expect(back.images.single.id, 'm1');
      expect(back.videos.single.url, 'https://youtu.be/abc');
    });

    test('toCatalogMap tidak mendedahkan createdBy', () {
      final map = TestHarness.program().copyWith(createdBy: 'admin1').toCatalogMap();
      expect(map.containsKey('createdBy'), isFalse);
    });
  });

  group('Participant & Catalog', () {
    test('Participant.fromStudent menyalin profil & menormalkan emel ibu bapa', () {
      final student = TestHarness.student().copyWith(parentEmail: ' Parent@Example.COM ');
      final p = Participant.fromStudent(
        student: student,
        program: TestHarness.program(id: 'p1'),
        seatShard: 's03',
      );
      expect(p.parentEmail, 'parent@example.com');
      expect(p.seatShard, 's03');
      expect(p.toJoinMap()['emailStatus'], 'pending');
    });

    test('Catalog.fromMap menyusun program ikut tarikh dan pengumuman terbaharu dahulu', () {
      final catalog = Catalog.fromMap({
        'programs': {
          'b': {'id': 'b', 'date': '2026-12-05', 'status': 'open'},
          'a': {'id': 'a', 'date': '2026-11-01', 'status': 'open'},
        },
        'announcements': {
          'x': {'id': 'x', 'title': 'Lama', 'createdAt': '2026-01-01T00:00:00'},
          'y': {'id': 'y', 'title': 'Baharu', 'createdAt': '2026-09-01T00:00:00'},
        },
      });
      expect(catalog.programs.map((p) => p.id), ['a', 'b']);
      expect(catalog.announcements.first.title, 'Baharu');
    });

    test('readTime menyokong Timestamp, DateTime, int dan String', () {
      final dt = DateTime(2026, 9, 30, 10);
      expect(readTime(Timestamp.fromDate(dt)), dt.toIso8601String());
      expect(readTime(dt), dt.toIso8601String());
      expect(readTime(dt.millisecondsSinceEpoch), dt.toIso8601String());
      expect(readTime(null), '');
    });
  });
}
