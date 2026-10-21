import 'dart:async';

import 'package:flutter/foundation.dart';

import '../api/email_gateway.dart';
import '../api/email_relay.dart';
import '../api/email_templates.dart';
import '../availability/connectivity_manager.dart';
import '../database_storage/admin_workspace.dart';
import '../database_storage/media_repository.dart';
import '../database_storage/models.dart';
import '../database_storage/program_repository.dart';
import '../database_storage/user_repository.dart';
import '../error_tracking/error_tracker.dart';
import 'backup_service.dart';
import 'email_service.dart';
import 'legacy_migration_service.dart';

/// Semua operasi admin. Setiap tindakan penting dilog dalam log audit
/// (RTDB, append-only) supaya boleh dijejak siapa melakukan apa.
class AdminState extends ChangeNotifier {
  final ProgramRepository programsRepo;
  final UserRepository usersRepo;
  final EmailService email;
  final MediaRepository media;
  final AdminWorkspace Function() _workspaceFactory;
  final BackupService Function() _backupFactory;
  final LegacyMigrationService Function() _migrationFactory;
  final ConnectivityManager? _connectivity;

  /// Web app Apps Script untuk emel segera (null = tidak digunakan).
  final EmailRelay? relay;

  /// Jika emel segera aktif, penyertaan baharu diberi masa ini kepada web app
  /// sebelum aplikasi admin menghantarnya secara automatik (elak emel berganda).
  static const instantEmailGrace = Duration(minutes: 2);

  /// Kekerapan aplikasi admin menghantar emel ibu bapa yang tertangguh secara
  /// automatik (null = dimatikan, contohnya dalam ujian).
  final Duration? autoSendInterval;
  Timer? _autoSendTimer;
  bool _autoSending = false;
  bool _emailKeyConfigured = false;
  String? _relayUrl;

  AdminState({
    required this.programsRepo,
    required this.usersRepo,
    required this.email,
    required this.media,
    required AdminWorkspace Function() workspace,
    required BackupService Function() backup,
    required LegacyMigrationService Function() migration,
    this._connectivity,
    this.autoSendInterval,
    this.relay,
  }) : _workspaceFactory = workspace,
       _backupFactory = backup,
       _migrationFactory = migration;

  AppUser? _admin;
  bool _workspaceReady = false;
  AdminWorkspace? _workspace;

  StreamSubscription<List<Program>>? _programsSub;
  StreamSubscription<Map<String, SeatSummary>>? _seatsSub;
  StreamSubscription<List<AuditEntry>>? _auditSub;
  StreamSubscription<List<AdminPresence>>? _presenceSub;
  StreamSubscription<List<BackupRecord>>? _backupSub;
  StreamSubscription<bool>? _connectedSub;
  StreamSubscription<AutomationStatus?>? _automationSub;
  AutomationStatus? _automation;

  List<Program> _programs = [];
  Map<String, SeatSummary> _seats = {};
  List<AuditEntry> _audit = [];
  List<AdminPresence> _presence = [];
  List<BackupRecord> _backups = [];
  EmailCounts _emailCounts = const EmailCounts();
  int _pendingJoinEmails = 0;
  int _studentCount = 0;
  bool _programsLoaded = false;
  bool _busy = false;
  QueueProgress? _queueProgress;

  AppUser? get admin => _admin;
  bool get emailKeyConfigured => _emailKeyConfigured;
  bool get workspaceReady => _workspaceReady;
  bool get programsLoaded => _programsLoaded;
  bool get isBusy => _busy;
  QueueProgress? get queueProgress => _queueProgress;
  List<AuditEntry> get audit => _audit;
  List<AdminPresence> get presence => _presence;
  List<AdminPresence> get onlineAdmins => _presence.where((p) => p.online).toList();
  List<BackupRecord> get backups => _backups;
  EmailCounts get emailCounts => _emailCounts;
  int get pendingJoinEmails => _pendingJoinEmails;
  String? get emailRelayUrl => _relayUrl;
  bool get instantEmailConfigured => _relayUrl != null;

  /// Status emel automatik (Apps Script). `ok == false` → dipaparkan kepada admin.
  AutomationStatus? get emailAutomation => _automation;
  int get studentCount => _studentCount;

  List<Program> get programs => _programs
      .map((p) => p.copyWith(joinedCount: _seats[p.id]?.joined ?? 0))
      .toList();

  Program? programById(String id) {
    for (final p in programs) {
      if (p.id == id) return p;
    }
    return null;
  }

  int get totalJoined => _seats.values.fold(0, (sum, s) => sum + s.joined);

  BackupRecord? get lastBackup {
    for (final b in _backups) {
      if (b.kind == 'backup') return b;
    }
    return null;
  }

  bool get backupOverdue {
    final last = lastBackup;
    if (last == null) return true;
    final at = DateTime.fromMillisecondsSinceEpoch(last.at);
    return DateTime.now().difference(at) > const Duration(days: 7);
  }

  // ------------------------------------------------------------- lifecycle

  Future<void> attach(AppUser admin, {required bool workspaceReady}) async {
    if (_admin?.uid == admin.uid && _workspaceReady == workspaceReady) return;
    await detach();
    _admin = admin;
    _workspaceReady = workspaceReady;

    _programsSub = programsRepo.watchAllPrograms().listen((items) {
      _programs = items;
      _programsLoaded = true;
      notifyListeners();
    }, onError: _onStreamError);
    _seatsSub = programsRepo.watchAllSeatSummaries().listen((items) {
      _seats = items;
      notifyListeners();
    }, onError: _onStreamError);

    if (workspaceReady) {
      final workspace = _workspaceFactory();
      _workspace = workspace;
      _auditSub = workspace.watchAudit().listen((items) {
        _audit = items;
        notifyListeners();
      }, onError: _onStreamError);
      _presenceSub = workspace.watchPresence().listen((items) {
        _presence = items;
        notifyListeners();
      }, onError: _onStreamError);
      _backupSub = workspace.watchBackups().listen((items) {
        _backups = items;
        notifyListeners();
      }, onError: _onStreamError);
      _connectedSub = workspace.watchConnected().listen(
        (online) => _connectivity?.reportWorkspace(online: online),
        onError: _onStreamError,
      );
      _automationSub = workspace.watchEmailAutomation().listen((status) {
        _automation = status;
        notifyListeners();
      }, onError: _onStreamError);
      unawaited(
        workspace
            .goOnline(uid: admin.uid, email: admin.email, name: admin.fullName)
            .catchError(_onStreamError),
      );
      await _loadEmailKey(workspace);
    }
    unawaited(refreshDashboard());
    unawaited(_loadRelayUrl());
    final interval = autoSendInterval;
    if (interval != null) {
      _autoSendTimer = Timer.periodic(interval, (_) => unawaited(autoSendPendingEmails()));
    }
  }

  Future<void> _loadRelayUrl() async {
    final url = await relay?.relayUrl(refresh: true);
    if (url == _relayUrl) return;
    _relayUrl = url;
    notifyListeners();
  }

  /// Simpan pautan web app Apps Script (public/config) untuk emel segera.
  Future<void> saveEmailRelayUrl(String url) => _run(() async {
    final service = relay;
    if (service == null) throw StateError('Emel segera tidak tersedia.');
    await service.saveRelayUrl(url, adminUid: _adminUid);
    _relayUrl = url.trim();
    await _record('email.relay', 'Kemas kini pautan emel segera (Apps Script)');
  });

  /// Semak web app menjawab dan private key tersedia di pelayan.
  Future<RelayResult> testEmailRelay(String url) async {
    final service = relay;
    if (service == null) return const RelayResult('unavailable');
    return service.ping(url);
  }

  Future<void> _loadEmailKey(AdminWorkspace workspace) async {
    try {
      final key = await workspace.readEmailJsPrivateKey();
      email.gateway.setPrivateKey(key);
      _emailKeyConfigured = email.gateway.hasPrivateKey;
      notifyListeners();
    } catch (error, stack) {
      ErrorTracker().logError('Load EmailJS key failed', error: error, stackTrace: stack);
    }
  }

  /// Simpan private key EmailJS dalam ruang kerja admin (bukan dalam APK).
  Future<void> saveEmailJsPrivateKey(String key) => _run(() async {
    final admin = _admin!;
    final workspace = _workspace ?? _workspaceFactory();
    await workspace.saveEmailJsPrivateKey(key, uid: admin.uid);
    email.gateway.setPrivateKey(key);
    _emailKeyConfigured = email.gateway.hasPrivateKey;
    // Nilai kunci TIDAK direkod dalam log audit.
    await _record('email.settings', 'Kemas kini private key EmailJS');
  });

  /// Hantar emel pengesahan tertangguh & barisan emel tanpa campur tangan admin.
  /// Pelajar tidak memegang private key, jadi aplikasi admin yang menghantar.
  Future<void> autoSendPendingEmails() async {
    if (_autoSending || _busy || _queueProgress != null || !_emailKeyConfigured) return;
    _autoSending = true;
    try {
      await refreshDashboard();
      if (_pendingJoinEmails > 0) {
        await sendPendingJoinEmails(
          minAge: instantEmailConfigured ? instantEmailGrace : Duration.zero,
        );
      }
      if (_emailCounts.queued > 0) await processEmailQueue();
    } catch (error, stack) {
      ErrorTracker().logError('Auto-send emails failed', error: error, stackTrace: stack);
    } finally {
      _autoSending = false;
    }
  }

  Future<void> detach() async {
    _autoSendTimer?.cancel();
    _autoSendTimer = null;
    email.gateway.setPrivateKey(null);
    _emailKeyConfigured = false;
    _relayUrl = null;
    final admin = _admin;
    final workspace = _workspace;
    if (admin != null && workspace != null) {
      await workspace.goOffline(admin.uid).catchError((_) {});
    }
    for (final sub in [
      _programsSub,
      _seatsSub,
      _auditSub,
      _presenceSub,
      _backupSub,
      _connectedSub,
      _automationSub,
    ]) {
      await sub?.cancel();
    }
    _automationSub = null;
    _automation = null;
    _programsSub = null;
    _seatsSub = null;
    _auditSub = null;
    _presenceSub = null;
    _backupSub = null;
    _connectedSub = null;
    _admin = null;
    _workspace = null;
    _workspaceReady = false;
    _programs = [];
    _seats = {};
    _audit = [];
    _presence = [];
    _backups = [];
    _programsLoaded = false;
    _connectivity?.reportWorkspace(online: null);
  }

  void _onStreamError(Object error, [StackTrace? stack]) {
    ErrorTracker().logError('Admin stream failed', error: error, stackTrace: stack);
  }

  Future<void> refreshDashboard() async {
    try {
      final results = await Future.wait([
        email.counts(),
        email.countPendingJoinEmails(),
        usersRepo.countUsers(role: 'student'),
      ]);
      _emailCounts = results[0] as EmailCounts;
      _pendingJoinEmails = results[1] as int;
      _studentCount = results[2] as int;
      notifyListeners();
    } catch (error, stack) {
      ErrorTracker().logError('Dashboard refresh failed', error: error, stackTrace: stack);
    }
  }

  Future<T> _run<T>(Future<T> Function() action) async {
    _busy = true;
    notifyListeners();
    try {
      return await action();
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> _record(
    String action,
    String summary, {
    String targetType = '',
    String targetId = '',
  }) async {
    final admin = _admin;
    final workspace = _workspace;
    if (admin == null || workspace == null) return;
    try {
      await workspace.logAction(
        actorUid: admin.uid,
        actorEmail: admin.email,
        action: action,
        summary: summary,
        targetType: targetType,
        targetId: targetId,
      );
    } catch (error, stack) {
      ErrorTracker().logError('Audit log failed', error: error, stackTrace: stack);
    }
  }

  String get _adminUid => _admin?.uid ?? '';

  // --------------------------------------------------------------- program

  Future<Program> createProgram(Program draft) => _run(() async {
    final program = await programsRepo.createProgram(draft, adminUid: _adminUid);
    await _record('program.create', 'Cipta program "${program.title}" (${program.status})',
        targetType: 'program', targetId: program.id);
    return program;
  });

  /// Kemas kini program. Jika tarikh/masa/lokasi berubah dan ada peserta,
  /// notifikasi dalam aplikasi dihantar dan emel dimasukkan ke barisan.
  Future<int> updateProgram(Program program, {required Program previous}) =>
      _run(() async {
        final updated = await programsRepo.updateProgram(program);
        var notified = 0;
        final scheduleChanged = previous.date != updated.date ||
            previous.time != updated.time ||
            previous.location != updated.location;
        if (scheduleChanged) {
          final participants = await programsRepo.fetchParticipants(updated.id);
          if (participants.isNotEmpty) {
            notified = await programsRepo.notifyParticipants(
              participants: participants,
              type: 'update',
              title: 'Maklumat program dikemas kini',
              message:
                  '${updated.title} kini pada ${updated.date}, ${updated.time} di ${updated.location}.',
              programId: updated.id,
            );
            await email.enqueue(
              participants: participants,
              build: (p) => EmailTemplates.update(participant: p, program: updated),
              programId: updated.id,
              adminUid: _adminUid,
            );
          }
        }
        await _record('program.update',
            'Kemas kini "${updated.title}"${notified > 0 ? ' – $notified peserta dimaklumkan' : ''}',
            targetType: 'program', targetId: updated.id);
        unawaited(refreshDashboard());
        return notified;
      });

  Future<void> setProgramStatus(Program program, String status) => _run(() async {
    await programsRepo.setStatus(program, status);
    await _record('program.status', '"${program.title}": ${program.status} → $status',
        targetType: 'program', targetId: program.id);
  });

  Future<int> cancelProgram(Program program, String reason) => _run(() async {
    final cancelled = await programsRepo.setStatus(program, 'cancelled', reason: reason);
    final participants = await programsRepo.fetchParticipants(program.id);
    if (participants.isNotEmpty) {
      await programsRepo.notifyParticipants(
        participants: participants,
        type: 'cancelled',
        title: 'Program dibatalkan',
        message: '${program.title} dibatalkan. Sebab: $reason',
        programId: program.id,
      );
      await email.enqueue(
        participants: participants,
        build: (p) => EmailTemplates.cancelled(
          participant: p,
          program: cancelled,
          reason: reason,
        ),
        programId: program.id,
        adminUid: _adminUid,
      );
    }
    await _record('program.cancel',
        'Batal "${program.title}" – ${participants.length} peserta dimaklumkan. Sebab: $reason',
        targetType: 'program', targetId: program.id);
    unawaited(refreshDashboard());
    return participants.length;
  });

  Future<void> deleteProgram(Program program) => _run(() async {
    await programsRepo.deleteProgram(program.id);
    await _record('program.delete',
        'Padam "${program.title}" (${program.joinedCount} peserta)',
        targetType: 'program', targetId: program.id);
  });

  Future<Program> duplicateProgram(Program program) => _run(() async {
    final copy = await programsRepo.createProgram(
      program.copyWith(
        id: '',
        title: program.title.length > 110
            ? '${program.title.substring(0, 110)} (Copy)'
            : '${program.title} (Copy)',
        status: 'draft',
        cancellationReason: '',
        joinedCount: 0,
      ),
      adminUid: _adminUid,
    );
    await _record('program.duplicate', 'Salin "${program.title}" sebagai draf',
        targetType: 'program', targetId: copy.id);
    return copy;
  });

  Stream<List<Participant>> watchParticipants(String programId) =>
      programsRepo.watchParticipants(programId);

  Future<void> removeParticipant(Program program, Participant participant) =>
      _run(() async {
        await programsRepo.removeParticipant(
          program: program,
          participant: participant,
        );
        await _record('participant.remove',
            'Buang ${participant.studentName} (${participant.matricNo}) daripada "${program.title}"',
            targetType: 'participant', targetId: '${program.id}/${participant.studentUid}');
      });

  // ------------------------------------------------------------------ media

  Future<MediaItem> uploadImage(Uint8List bytes, {required String programId, String caption = ''}) =>
      _run(() async {
        final item = await media.uploadImage(
          bytes: bytes,
          programId: programId,
          adminUid: _adminUid,
          caption: caption,
        );
        await _record('media.image', 'Muat naik gambar (${(item.sizeBytes / 1024).round()} KB)',
            targetType: 'media', targetId: item.id);
        return item;
      });

  Future<MediaItem> addVideoLink(String url, {required String programId, String caption = ''}) =>
      _run(() async {
        final item = await media.addVideoLink(
          url: url,
          programId: programId,
          adminUid: _adminUid,
          caption: caption,
        );
        await _record('media.video', 'Tambah pautan video', targetType: 'media', targetId: item.id);
        return item;
      });

  Future<void> deleteMedia(String id) async {
    await media.delete(id);
    await _record('media.delete', 'Padam media', targetType: 'media', targetId: id);
  }

  // ------------------------------------------------------------------- emel

  Future<bool> resendParticipantEmail(Participant participant, Program program) async {
    final ok = await email.resendJoin(
      participant: participant,
      program: program,
      adminUid: _adminUid,
    );
    await _record('email.resend', 'Hantar semula emel kepada ${participant.parentEmail}: ${ok ? 'berjaya' : 'gagal'}',
        targetType: 'participant', targetId: '${program.id}/${participant.studentUid}');
    unawaited(refreshDashboard());
    return ok;
  }

  Future<QueueProgress> processEmailQueue() async {
    _queueProgress = const QueueProgress(done: 0, total: 0);
    notifyListeners();
    QueueProgress last = const QueueProgress(done: 0, total: 0);
    try {
      await for (final progress in email.processQueue()) {
        last = progress;
        _queueProgress = progress;
        notifyListeners();
      }
      await _record('email.queue', 'Proses barisan emel: ${last.done - last.failed} berjaya, ${last.failed} gagal');
    } finally {
      _queueProgress = null;
      notifyListeners();
      unawaited(refreshDashboard());
    }
    return last;
  }

  /// Hantar emel pengesahan yang tertinggal (status "pending").
  /// [minAge]: hanya penyertaan yang menunggu sekurang-kurangnya selama ini
  /// (penghantaran automatik); butang manual menghantar semua.
  Future<QueueProgress> sendPendingJoinEmails({Duration minAge = Duration.zero}) => _run(() async {
    final cutoff = DateTime.now().subtract(minAge);
    final pending = (await email.fetchPendingJoinEmails()).where((p) {
      if (minAge == Duration.zero) return true;
      final joined = DateTime.tryParse(p.joinedAt);
      return joined == null || !joined.isAfter(cutoff);
    }).toList();
    if (pending.isEmpty) return const QueueProgress(done: 0, total: 0);
    var failed = 0;
    for (var i = 0; i < pending.length; i++) {
      final participant = pending[i];
      final program = programById(participant.programId) ??
          Program(
            id: participant.programId,
            title: participant.programTitle,
            description: '',
            date: participant.programDate,
            time: participant.programTime,
            location: participant.programLocation,
            capacity: 0,
            category: 'Academic',
          );
      final ok = await email.resendJoin(
        participant: participant,
        program: program,
        adminUid: _adminUid,
      );
      if (!ok) failed++;
      _queueProgress = QueueProgress(done: i + 1, total: pending.length, failed: failed);
      notifyListeners();
      if (i < pending.length - 1) await Future.delayed(email.spacing);
    }
    _queueProgress = null;
    await _record('email.pending', 'Hantar ${pending.length} emel tertangguh ($failed gagal)');
    unawaited(refreshDashboard());
    return QueueProgress(done: pending.length, total: pending.length, failed: failed);
  });

  /// Hantar emel ujian sebenar melalui EmailJS (tidak direkod sebagai log ibu bapa).
  Future<EmailSendResult> sendTestEmail(String to) async {
    final admin = _admin;
    final result = await email.gateway.send(
      EmailTemplates.test(to: to.trim(), adminName: admin?.fullName ?? 'Admin'),
    );
    await _record(
      'email.test',
      'Emel ujian ke $to: ${result.success ? 'berjaya' : 'gagal – ${result.error}'}',
    );
    return result;
  }

  Future<bool> retryEmail(EmailLog log) async {
    final ok = await email.retry(log);
    await _record('email.retry', 'Cuba semula emel ${log.recipient}: ${ok ? 'berjaya' : 'gagal'}',
        targetType: 'email', targetId: log.id);
    unawaited(refreshDashboard());
    return ok;
  }

  Future<void> deleteEmailLog(EmailLog log) async {
    await email.deleteLog(log.id);
    await _record('email.delete', 'Padam log emel ${log.recipient}', targetType: 'email', targetId: log.id);
    unawaited(refreshDashboard());
  }

  Future<int> clearEmailLogs({String? status}) => _run(() async {
    final deleted = await email.clearLogs(status: status);
    await _record('email.clear', 'Padam $deleted log emel${status == null ? '' : ' ($status)'}');
    unawaited(refreshDashboard());
    return deleted;
  });

  // -------------------------------------------------------------- pengumuman

  Future<void> addAnnouncement(String title, String message) => _run(() async {
    final announcement = Announcement(
      id: 'ann_${DateTime.now().millisecondsSinceEpoch}',
      title: title.trim(),
      message: message.trim(),
      createdAt: DateTime.now().toIso8601String(),
    );
    await programsRepo.addAnnouncement(announcement);
    await _record('announcement.create', 'Pengumuman "${announcement.title}"',
        targetType: 'announcement', targetId: announcement.id);
  });

  Future<void> deleteAnnouncement(Announcement announcement) => _run(() async {
    await programsRepo.deleteAnnouncement(announcement.id);
    await _record('announcement.delete', 'Padam pengumuman "${announcement.title}"',
        targetType: 'announcement', targetId: announcement.id);
  });

  // --------------------------------------------------------------- pengguna

  Future<UserPage> listUsers({String? role, UserPage? after}) =>
      usersRepo.listUsers(role: role, startAfter: after?.lastDoc);

  Future<AppUser?> findUserByEmail(String email) => usersRepo.findByEmail(email);

  Future<void> setUserStatus(AppUser user, String status) => _run(() async {
    await usersRepo.setStatus(user.uid, status);
    await _record('user.status', '${user.email}: ${user.status} → $status',
        targetType: 'user', targetId: user.uid);
  });

  /// Super admin sahaja (dikuatkuasakan oleh rules Firestore & RTDB).
  Future<void> setUserRole(AppUser user, String role) => _run(() async {
    final workspace = _workspace ?? _workspaceFactory();
    await usersRepo.setRole(user.uid, role);
    try {
      await workspace.setWorkspaceAdmin(user.uid, role == 'admin');
    } catch (error) {
      // Kembalikan peranan supaya dua pangkalan data kekal selaras.
      await usersRepo.setRole(user.uid, user.role).catchError((_) {});
      rethrow;
    }
    await _record('user.role', '${user.email}: ${user.role} → $role',
        targetType: 'user', targetId: user.uid);
  });

  // ------------------------------------------------------ backup & migrasi

  Future<BackupFile> createBackup() => _run(() async {
    final admin = _admin!;
    final file = await _backupFactory().createBackup(adminEmail: admin.email);
    try {
      await (_workspace ?? _workspaceFactory()).recordBackup(
        BackupRecord(
          id: '',
          at: DateTime.now().millisecondsSinceEpoch,
          by: admin.uid,
          byEmail: admin.email,
          documents: file.summary.documents,
          bytes: file.summary.bytes,
          kind: 'backup',
        ),
      );
    } catch (error, stack) {
      ErrorTracker().logError('Backup record failed', error: error, stackTrace: stack);
    }
    await _record('backup.create', 'Backup ${file.summary.documents} dokumen (${(file.summary.bytes / 1024).round()} KB)');
    return file;
  });

  Future<int> restoreBackup(Map<String, dynamic> backup, {void Function(int)? onProgress}) =>
      _run(() async {
        final admin = _admin!;
        final written = await _backupFactory().restore(backup, onProgress: onProgress);
        await (_workspace ?? _workspaceFactory())
            .recordBackup(
              BackupRecord(
                id: '',
                at: DateTime.now().millisecondsSinceEpoch,
                by: admin.uid,
                byEmail: admin.email,
                documents: written,
                bytes: 0,
                kind: 'restore',
                note: 'Backup ${backup['createdAt'] ?? ''}',
              ),
            )
            .catchError((_) {});
        await _record('backup.restore', 'Pulih $written dokumen daripada backup ${backup['createdAt'] ?? ''}');
        return written;
      });

  Future<Map<String, dynamic>> readLegacyData() => _migrationFactory().readLegacy();

  Future<MigrationReport> migrateLegacy(Map<String, dynamic> legacy) => _run(() async {
    final report = await _migrationFactory().migrate(legacy, adminUid: _adminUid);
    await _record('legacy.migrate',
        'Migrasi: ${report.users} pengguna, ${report.programs} program, ${report.participants} penyertaan, ${report.emailLogs} log emel');
    return report;
  });

  Future<void> deleteLegacyData() => _run(() async {
    await _migrationFactory().deleteLegacy();
    await _record('legacy.delete', 'Padam data lama RTDB');
  });

  @override
  void dispose() {
    unawaited(detach());
    super.dispose();
  }
}
