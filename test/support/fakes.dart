import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:my_parent_care/api/email_relay.dart';
import 'package:my_parent_care/api/email_gateway.dart';
import 'package:my_parent_care/auth/google_auth_adapter.dart';
import 'package:my_parent_care/backend_logic/account_deletion_service.dart';
import 'package:my_parent_care/backend_logic/email_service.dart';
import 'package:my_parent_care/cache_cdn/image_compressor.dart';
import 'package:my_parent_care/database_storage/admin_workspace.dart';
import 'package:my_parent_care/database_storage/media_repository.dart';
import 'package:my_parent_care/database_storage/models.dart';
import 'package:my_parent_care/database_storage/program_repository.dart';
import 'package:my_parent_care/database_storage/user_repository.dart';
import 'package:my_parent_care/load_balancer_scaling/retry_policy.dart';
import 'package:my_parent_care/main.dart';

/// Ruang kerja admin dalam memori (ganti RTDB dalam ujian).
class InMemoryAdminWorkspace implements AdminWorkspace {
  final Set<String> admins = {};
  final List<AuditEntry> auditEntries = [];
  final List<BackupRecord> backupRecords = [];
  final Map<String, AdminPresence> presenceMap = {};
  Map<String, dynamic> legacy = {};
  bool legacyDeleted = false;
  Map<String, dynamic>? restored;
  String? emailJsKey;

  final _audit = StreamController<List<AuditEntry>>.broadcast();
  final _presence = StreamController<List<AdminPresence>>.broadcast();
  final _backups = StreamController<List<BackupRecord>>.broadcast();

  @override
  Future<bool> isWorkspaceAdmin(String uid) async => admins.contains(uid);

  @override
  Future<void> setWorkspaceAdmin(String uid, bool isAdmin) async {
    isAdmin ? admins.add(uid) : admins.remove(uid);
  }

  @override
  Future<void> logAction({
    required String actorUid,
    required String actorEmail,
    required String action,
    required String summary,
    String targetType = '',
    String targetId = '',
  }) async {
    auditEntries.insert(
      0,
      AuditEntry(
        id: 'a${auditEntries.length}',
        action: action,
        actorUid: actorUid,
        actorEmail: actorEmail,
        summary: summary,
        targetType: targetType,
        targetId: targetId,
        at: DateTime.now().millisecondsSinceEpoch,
      ),
    );
    _audit.add(List.of(auditEntries));
  }

  @override
  Stream<List<AuditEntry>> watchAudit({int limit = 100}) async* {
    yield List.of(auditEntries);
    yield* _audit.stream;
  }

  @override
  Future<void> goOnline({required String uid, required String email, required String name}) async {
    presenceMap[uid] = AdminPresence(uid: uid, email: email, name: name, online: true, lastSeen: 1);
    _presence.add(presenceMap.values.toList());
  }

  @override
  Future<void> goOffline(String uid) async {
    final p = presenceMap[uid];
    if (p != null) {
      presenceMap[uid] = AdminPresence(uid: uid, email: p.email, name: p.name, online: false, lastSeen: 2);
    }
  }

  @override
  Stream<List<AdminPresence>> watchPresence() async* {
    yield presenceMap.values.toList();
    yield* _presence.stream;
  }

  @override
  Future<void> recordBackup(BackupRecord record) async {
    backupRecords.insert(0, record);
    _backups.add(List.of(backupRecords));
  }

  @override
  Stream<List<BackupRecord>> watchBackups({int limit = 20}) async* {
    yield List.of(backupRecords);
    yield* _backups.stream;
  }

  @override
  Future<Map<String, dynamic>> readLegacyData() async => legacy;

  @override
  Future<void> deleteLegacyData() async {
    legacy = {};
    legacyDeleted = true;
  }

  @override
  Future<Map<String, dynamic>> exportWorkspace() async => {
    'admins': {for (final a in admins) a: true},
    'admin_workspace': {'notes': {}},
  };

  @override
  Future<void> restoreWorkspace(Map<String, dynamic> data) async => restored = data;

  @override
  Stream<bool> watchConnected() => Stream.value(true);

  AutomationStatus? automation;
  final _automation = StreamController<AutomationStatus?>.broadcast();

  void setAutomation(AutomationStatus? status) {
    automation = status;
    _automation.add(status);
  }

  @override
  Stream<AutomationStatus?> watchEmailAutomation() async* {
    yield automation;
    yield* _automation.stream;
  }

  @override
  Future<String?> readEmailJsPrivateKey() async => emailJsKey;

  @override
  Future<void> saveEmailJsPrivateKey(String key, {required String uid}) async =>
      emailJsKey = key.trim();
}

/// Gerbang emel palsu: rekod mesej, boleh diset gagal.
class FakeEmailGateway implements EmailGateway {
  final List<EmailMessage> sent = [];
  bool fail = false;
  String error = 'EmailJS ralat 500';
  String? privateKey;

  @override
  bool get isConfigured => true;

  @override
  bool get hasPrivateKey => (privateKey ?? '').isNotEmpty;

  @override
  void setPrivateKey(String? key) => privateKey = key;

  @override
  Future<EmailSendResult> send(EmailMessage message) async {
    if (fail) return EmailSendResult.failed(error);
    sent.add(message);
    return const EmailSendResult.sent();
  }
}

class FakeGoogleAuthAdapter implements GoogleAuthAdapter {
  bool cancel = false;
  int reauthCount = 0;

  @override
  Future<UserCredential?> signIn(FirebaseAuth auth) async {
    if (cancel) return null;
    return auth.signInWithCredential(
      GoogleAuthProvider.credential(idToken: 'fake', accessToken: 'fake'),
    );
  }

  @override
  Future<void> reauthenticate(User user) async => reauthCount++;

  @override
  Future<void> signOut() async {}
}

Future<CompressedImage> fakeCompressor(Uint8List bytes) async =>
    CompressedImage(bytes: bytes, width: 10, height: 10);

/// Semua kebergantungan untuk satu ujian.
class TestHarness {
  final FakeFirebaseFirestore firestore;
  final MockFirebaseAuth auth;
  final InMemoryAdminWorkspace workspace;
  final FakeEmailGateway gateway;
  final FakeGoogleAuthAdapter google;
  final ProgramRepository programs;
  final UserRepository users;
  final MediaRepository media;
  final EmailService email;
  final AccountDeletionService deletion;

  /// Web app Apps Script tiruan (emel segera). Rekod setiap permintaan.
  final List<http.Request> relayRequests = [];
  http.Response Function(http.Request request) relayResponder =
      (_) => http.Response('{"ok":true,"status":"sent"}', 200);
  late final EmailRelay relay = EmailRelay(
    firestore,
    client: MockClient((request) async {
      relayRequests.add(request);
      return relayResponder(request);
    }),
  );
  static const relayUrl = 'https://script.google.com/macros/s/AKfycbTestDeployment_123/exec';

  /// Aktifkan emel segera (pautan web app dalam public/config).
  Future<void> enableInstantEmail() =>
      firestore.doc(EmailRelay.configDoc).set({'emailRelayUrl': relayUrl});

  TestHarness._({
    required this.firestore,
    required this.auth,
    required this.workspace,
    required this.gateway,
    required this.google,
    required this.programs,
    required this.users,
    required this.media,
    required this.email,
    required this.deletion,
  });

  /// [firestore]/[workspace] boleh dikongsi antara dua "telefon" (contoh: app
  /// pelajar dan app admin) supaya ujian interaksi guna pangkalan data sama.
  factory TestHarness({
    MockUser? user,
    bool signedIn = false,
    FakeFirebaseFirestore? firestore,
    InMemoryAdminWorkspace? workspace,
  }) {
    firestore ??= FakeFirebaseFirestore();
    final programs = ProgramRepository(firestore, retry: RetryPolicy.immediate);
    final gateway = FakeEmailGateway();
    return TestHarness._(
      firestore: firestore,
      auth: MockFirebaseAuth(mockUser: user, signedIn: signedIn),
      workspace: workspace ?? InMemoryAdminWorkspace(),
      gateway: gateway,
      google: FakeGoogleAuthAdapter(),
      programs: programs,
      users: UserRepository(firestore),
      media: MediaRepository(firestore, compressor: fakeCompressor),
      email: EmailService(firestore, gateway: gateway, programs: programs, spacing: Duration.zero),
      deletion: AccountDeletionService(firestore, programs),
    );
  }

  AppServices services() => AppServices(
    auth: auth,
    firestore: firestore,
    appVersion: 'test',
    programs: programs,
    users: users,
    media: media,
    email: email,
    deletion: deletion,
    workspace: () => workspace,
    google: google,
    relay: relay,
  );

  // ------------------------------------------------------------- data asas

  static AppUser student({
    String uid = 'stu1',
    String email = 'aina@student.test',
    String fullName = 'Nur Aina',
    bool complete = true,
  }) => AppUser(
    uid: uid,
    email: email,
    fullName: fullName,
    matricNo: complete ? 'KPTM12345' : '',
    course: complete ? 'Computer Science' : '',
    semester: complete ? '5' : '',
    phone: complete ? '0123456789' : '',
    parentName: complete ? 'Puan Mariam' : '',
    parentEmail: complete ? 'parent.$uid@example.com' : '',
    parentPhone: complete ? '0198765432' : '',
    relationship: complete ? 'Mother' : '',
    profileCompletePercent: complete ? 100 : 20,
    privacyVersion: '2026-09-30',
  );

  Future<void> saveUser(AppUser user) async {
    await firestore.doc('users/${user.uid}').set({
      ...user.toNewUserMap(),
      'role': user.role,
      'status': user.status,
      'createdAt': Timestamp.now(),
      'updatedAt': Timestamp.now(),
      'consentAt': Timestamp.now(),
    });
  }

  static Program program({
    String id = '',
    String title = 'Hari Kerjaya',
    int capacity = 3,
    String status = 'open',
  }) => Program(
    id: id,
    title: title,
    description: 'Jumpa majikan',
    date: '2026-12-01',
    time: '09:00',
    location: 'Dewan Utama',
    capacity: capacity,
    category: 'Career',
    status: status,
  );
}
