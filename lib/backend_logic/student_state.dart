import 'dart:async';

import 'package:flutter/foundation.dart';

import '../api/email_relay.dart';
import '../availability/connectivity_manager.dart';
import '../database_storage/models.dart';
import '../database_storage/program_repository.dart';
import '../database_storage/user_repository.dart';
import '../error_tracking/error_tracker.dart';
import '../rate_limiting/rate_limiter.dart';

/// Data pelajar. Direka untuk kuota Spark:
/// * Katalog: 1 dokumen (semua program + pengumuman) – 1 bacaan.
/// * Sejarah: penyertaan sendiri sahaja (collection group).
/// * Kaunter tempat: dibaca atas permintaan (skrin butiran), bukan didengar
///   secara langsung – supaya ratusan pendaftaran tidak mencetuskan ribuan
///   bacaan pada setiap telefon.
class StudentState extends ChangeNotifier {
  final ProgramRepository _programs;
  final UserRepository _users;
  final ConnectivityManager? _connectivity;
  final EmailRelay? _relay;

  StudentState({
    required this._programs,
    required this._users,
    this._connectivity,
    this._relay,
  });

  String? _uid;
  StreamSubscription<Catalog>? _catalogSub;
  StreamSubscription<List<Participant>>? _participationSub;

  Catalog _catalog = Catalog.empty;
  bool _catalogLoaded = false;
  List<Participant> _participations = [];
  List<StudentNotification> _notifications = [];
  bool _notificationsLoading = false;
  final Map<String, SeatSummary> _seats = {};
  bool _isJoining = false;

  bool get catalogLoaded => _catalogLoaded;
  bool get isOfflineData => _catalog.fromCache;
  bool get isJoining => _isJoining;
  bool get notificationsLoading => _notificationsLoading;

  List<Program> get programs => _catalog.programs.map(_withSeats).toList();

  /// Program yang boleh dilihat dalam senarai "Programs" (dibuka sahaja).
  List<Program> get openPrograms =>
      programs.where((p) => p.isVisibleToStudents).toList();

  List<Announcement> get announcements => _catalog.announcements;
  List<Participant> get participations => _participations;
  List<StudentNotification> get notifications => _notifications;

  Program _withSeats(Program program) {
    final seats = _seats[program.id];
    return seats == null ? program : program.copyWith(joinedCount: seats.joined);
  }

  Program? programById(String id) {
    for (final program in _catalog.programs) {
      if (program.id == id) return _withSeats(program);
    }
    return null;
  }

  SeatSummary? seatsFor(String programId) => _seats[programId];

  bool hasJoined(String programId) =>
      _participations.any((p) => p.programId == programId);

  /// Penyertaan sendiri (langsung) – status emel ibu bapa dikemas kini sendiri.
  Participant? participationFor(String programId) {
    for (final p in _participations) {
      if (p.programId == programId) return p;
    }
    return null;
  }

  // -------------------------------------------------------------- langganan

  void attach(String uid) {
    if (_uid == uid) return;
    detach();
    _uid = uid;
    _catalogSub = _programs.watchCatalog().listen(
      (catalog) {
        _catalog = catalog;
        _catalogLoaded = true;
        _connectivity?.reportFirestore(online: !catalog.fromCache);
        notifyListeners();
      },
      onError: (Object error, StackTrace stack) {
        ErrorTracker().logError('Catalog stream failed', error: error, stackTrace: stack);
        _catalogLoaded = true;
        notifyListeners();
      },
    );
    _participationSub = _programs.watchMyParticipations(uid).listen(
      (items) {
        _participations = items;
        notifyListeners();
      },
      onError: (Object error, StackTrace stack) {
        ErrorTracker().logError('Participation stream failed', error: error, stackTrace: stack);
      },
    );
  }

  void detach() {
    _catalogSub?.cancel();
    _participationSub?.cancel();
    _catalogSub = null;
    _participationSub = null;
    _uid = null;
    _catalog = Catalog.empty;
    _catalogLoaded = false;
    _participations = [];
    _notifications = [];
    _seats.clear();
  }

  // ---------------------------------------------------------------- tempat

  /// Baca kiraan tempat (dihadkan sekali setiap 5 saat bagi setiap program).
  Future<SeatSummary?> refreshSeats(String programId, {bool force = false}) async {
    if (!force &&
        !RateLimiter.throttle(
          'seats_$programId',
          cooldown: const Duration(seconds: 5),
        )) {
      return _seats[programId];
    }
    try {
      final summary = await _programs.fetchSeatSummary(programId);
      _seats[programId] = summary;
      notifyListeners();
      return summary;
    } catch (error, stack) {
      ErrorTracker().logError('Seat summary failed', error: error, stackTrace: stack);
      return _seats[programId];
    }
  }

  // ----------------------------------------------------------------- sertai

  Future<void> _notifyParent(String programId, String uid) async {
    final relay = _relay;
    if (relay == null) return;
    final result = await relay.notifyJoin(programId: programId, uid: uid);
    if (result.status == 'error') {
      ErrorTracker().logError('Instant parent email failed: ${result.message}');
    }
  }

  Future<JoinOutcome> joinProgram({
    required Program program,
    required AppUser student,
    required bool emailVerified,
  }) async {
    if (student.isSuspended) {
      return const JoinOutcome(
        success: false,
        code: 'suspended',
        message: 'Akaun anda digantung. Sila hubungi admin.',
      );
    }
    if (!student.hasCompleteStudentProfile) {
      return const JoinOutcome(
        success: false,
        code: 'profile_required',
        message: 'Lengkapkan maklumat pelajar sebelum menyertai program.',
      );
    }
    if (!student.hasParentInfo) {
      return const JoinOutcome(
        success: false,
        code: 'parent_required',
        message: 'Lengkapkan maklumat dan emel ibu bapa terlebih dahulu.',
      );
    }
    if (!emailVerified) {
      return const JoinOutcome(
        success: false,
        code: 'email_unverified',
        message: 'Sahkan emel anda dahulu melalui pautan yang dihantar ke peti masuk.',
      );
    }
    if (hasJoined(program.id)) {
      return const JoinOutcome(
        success: false,
        code: 'already_joined',
        message: 'Anda sudah menyertai program ini.',
      );
    }
    if (!program.canJoin) {
      return const JoinOutcome(
        success: false,
        code: 'unavailable',
        message: 'Pendaftaran program ini sudah tidak tersedia.',
      );
    }
    if (_isJoining ||
        !RateLimiter.throttle('join_${student.uid}_${program.id}')) {
      return const JoinOutcome(
        success: false,
        code: 'rate_limited',
        message: 'Sila tunggu sebentar sebelum mencuba lagi.',
      );
    }

    _isJoining = true;
    notifyListeners();
    try {
      final result = await _programs.joinProgram(program: program, student: student);
      switch (result.code) {
        case JoinCode.success:
          break;
        case JoinCode.alreadyJoined:
          return const JoinOutcome(
            success: false,
            code: 'already_joined',
            message: 'Anda sudah menyertai program ini.',
          );
        case JoinCode.full:
          await refreshSeats(program.id, force: true);
          return const JoinOutcome(
            success: false,
            code: 'full',
            message: 'Maaf, program ini sudah penuh.',
          );
        case JoinCode.unavailable:
          return const JoinOutcome(
            success: false,
            code: 'unavailable',
            message: 'Pendaftaran ditutup atau profil anda belum layak.',
          );
        case JoinCode.busy:
          return const JoinOutcome(
            success: false,
            code: 'busy',
            message: 'Ramai pelajar sedang mendaftar. Sila cuba lagi sebentar.',
          );
      }

      // Tempat sudah disahkan. Emel ibu bapa dihantar SERTA-MERTA oleh web app
      // Apps Script (private key EmailJS kekal di pelayan – strict mode). Jika
      // gagal, emel kekal "pending" dan dihantar oleh trigger 5 minit / admin.
      unawaited(refreshSeats(program.id, force: true));
      unawaited(_notifyParent(program.id, student.uid));
      return const JoinOutcome(
        success: true,
        code: 'success',
        message: 'Penyertaan berjaya disahkan.',
        emailStatus: 'pending',
      );
    } catch (error, stack) {
      ErrorTracker().logError('Join program failed', error: error, stackTrace: stack);
      return const JoinOutcome(
        success: false,
        code: 'error',
        message: 'Sesuatu berlaku. Sila semak sambungan internet dan cuba lagi.',
      );
    } finally {
      _isJoining = false;
      notifyListeners();
    }
  }

  // ------------------------------------------------------------- notifikasi

  Future<void> loadNotifications(String uid) async {
    _notificationsLoading = true;
    notifyListeners();
    try {
      _notifications = await _users.fetchNotifications(uid);
    } catch (error, stack) {
      ErrorTracker().logError('Notifications failed', error: error, stackTrace: stack);
    } finally {
      _notificationsLoading = false;
      notifyListeners();
    }
  }

  Future<void> markNotificationRead(String uid, String id) async {
    await _users.markNotificationRead(uid, id);
    _notifications = [
      for (final n in _notifications)
        n.id == id
            ? StudentNotification(
                id: n.id,
                type: n.type,
                title: n.title,
                message: n.message,
                programId: n.programId,
                createdAt: n.createdAt,
                isRead: true,
              )
            : n,
    ];
    notifyListeners();
  }

  @override
  void dispose() {
    detach();
    super.dispose();
  }
}
