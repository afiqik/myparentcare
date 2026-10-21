import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../app_config.dart';
import '../backend_logic/account_deletion_service.dart';
import '../database_storage/admin_workspace.dart';
import '../database_storage/models.dart';
import '../database_storage/user_repository.dart';
import '../error_tracking/error_tracker.dart';
import 'google_auth_adapter.dart';

/// Peringkat sesi – menentukan skrin yang dipaparkan oleh [SplashScreen].
enum AuthStage {
  loading,
  signedOut,

  /// Log masuk tetapi tiada profil (Google baharu / akaun lama).
  needsProfile,

  /// Profil wujud tetapi belum bersetuju dengan versi Dasar Privasi semasa.
  needsConsent,
  suspended,
  ready,
}

class AdminAccess {
  final bool isAdmin;
  final bool workspaceReady;
  final String message;

  const AdminAccess({
    required this.isAdmin,
    required this.workspaceReady,
    this.message = '',
  });
}

class AuthService extends ChangeNotifier {
  final FirebaseAuth _auth;
  final UserRepository _users;
  final AdminWorkspace Function() _workspace;
  final GoogleAuthAdapter _google;
  final AccountDeletionService _deletion;

  StreamSubscription<User?>? _authSub;
  StreamSubscription<AppUser?>? _profileSub;
  final Completer<void> _initCompleter = Completer<void>();

  User? _firebaseUser;
  AppUser? _currentUser;
  bool _profileLoaded = false;
  bool _isLoading = false;
  bool _isInitialized = false;

  AuthService({
    required this._auth,
    required this._users,
    required this._workspace,
    required this._deletion,
    GoogleAuthAdapter? google,
  }) : _google = google ?? DefaultGoogleAuthAdapter() {
    _authSub = _auth.authStateChanges().listen(_onAuthStateChanged);
  }

  // ---------------------------------------------------------------- getters

  User? get firebaseUser => _firebaseUser;
  AppUser? get currentUser => _currentUser;
  bool get isLoading => _isLoading;
  bool get isInitialized => _isInitialized;
  Future<void> get initializationComplete => _initCompleter.future;

  bool get isGoogleUser =>
      _firebaseUser?.providerData.any((p) => p.providerId == 'google.com') ??
      false;

  /// Akaun Google sentiasa disahkan; akaun emel perlu klik pautan pengesahan.
  bool get emailVerified =>
      (_firebaseUser?.emailVerified ?? false) || isGoogleUser;

  bool get isSuperAdmin =>
      emailVerified && AppConfig.isSuperAdminEmail(_firebaseUser?.email);

  AuthStage get stage {
    if (!_isInitialized) return AuthStage.loading;
    if (_firebaseUser == null) return AuthStage.signedOut;
    if (!_profileLoaded) return AuthStage.loading;
    final user = _currentUser;
    if (user == null) return AuthStage.needsProfile;
    if (user.isSuspended) return AuthStage.suspended;
    if (user.privacyVersion != AppConfig.privacyPolicyVersion) {
      return AuthStage.needsConsent;
    }
    return AuthStage.ready;
  }

  // ------------------------------------------------------------- lifecycle

  void _completeInit() {
    _isInitialized = true;
    if (!_initCompleter.isCompleted) _initCompleter.complete();
  }

  /// Batalkan langganan profil tanpa menyekat (cancel() boleh lambat selesai).
  void _stopProfileStream() {
    final sub = _profileSub;
    _profileSub = null;
    if (sub != null) unawaited(sub.cancel());
  }

  Future<void> _onAuthStateChanged(User? user) async {
    _firebaseUser = user;
    _stopProfileStream();
    if (user == null) {
      _currentUser = null;
      _profileLoaded = false;
      _completeInit();
      notifyListeners();
      return;
    }
    _profileLoaded = false;
    notifyListeners();
    _profileSub = _users
        .watch(user.uid)
        .listen(
          (profile) {
            _currentUser = profile;
            _profileLoaded = true;
            _completeInit();
            notifyListeners();
          },
          onError: (Object error, StackTrace stack) {
            ErrorTracker().logError(
              'Profile stream failed',
              error: error,
              stackTrace: stack,
            );
            _profileLoaded = true;
            _completeInit();
            notifyListeners();
          },
        );
  }

  /// Tunggu profil selepas log masuk (untuk navigasi selepas butang ditekan).
  Future<AppUser?> _loadProfile(User user) async {
    _firebaseUser = user;
    final profile = await _users.fetch(user.uid);
    _currentUser = profile;
    _profileLoaded = true;
    _completeInit();
    return profile;
  }

  Future<T> _busy<T>(Future<T> Function() action) async {
    _isLoading = true;
    notifyListeners();
    try {
      return await action();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // ------------------------------------------------------------- log masuk

  // Log masuk HANYA dengan Google (pelajar & admin). Tiada kata laluan untuk
  // diingat/dicuri, dan emel sentiasa disahkan oleh Google.

  /// Pulangkan `null` jika dibatalkan oleh pengguna.
  Future<AppUser?> signInWithGoogle() {
    return _busy(() async {
      final credential = await _google.signIn(_auth);
      final user = credential?.user;
      if (user == null) return null;
      return _afterSignIn(user);
    });
  }

  Future<AppUser?> _afterSignIn(User user) async {
    var profile = await _loadProfile(user);
    if (profile == null && isSuperAdmin) {
      profile = AppUser(
        uid: user.uid,
        email: user.email ?? '',
        role: 'admin',
        authProvider: 'google',
        fullName: user.displayName?.trim().isNotEmpty == true
            ? user.displayName!.trim()
            : 'Super Admin',
        privacyVersion: AppConfig.privacyPolicyVersion,
      );
      await _users.create(profile);
      _currentUser = profile;
    }
    notifyListeners();
    return profile;
  }

  /// Cipta profil pelajar untuk pengguna Google baharu.
  Future<AppUser> createMissingProfile({
    required String fullName,
    required bool acceptedPrivacy,
  }) {
    if (!acceptedPrivacy) {
      throw StateError('You must accept the Privacy Policy to continue.');
    }
    final user = _firebaseUser;
    if (user == null) throw StateError('Not signed in.');
    return _busy(() async {
      final profile = AppUser(
        uid: user.uid,
        email: user.email ?? '',
        role: 'student',
        authProvider: 'google',
        fullName: fullName.trim(),
        privacyVersion: AppConfig.privacyPolicyVersion,
      );
      await _users.create(profile);
      _currentUser = profile;
      _profileLoaded = true;
      return profile;
    });
  }

  Future<void> acceptPrivacyPolicy() async {
    final user = _currentUser;
    if (user == null) return;
    await _busy(() async {
      final updated = user.copyWith(
        privacyVersion: AppConfig.privacyPolicyVersion,
      );
      await _users.updateProfile(updated, renewConsent: true);
      _currentUser = updated;
    });
  }

  // ------------------------------------------------------------ admin

  /// Pastikan admin mempunyai akses ke ruang kerja RTDB. Super admin juga
  /// dinaikkan secara automatik kali pertama (bootstrap).
  Future<AdminAccess> ensureAdminAccess() async {
    final user = _currentUser;
    final authUser = _firebaseUser;
    if (user == null || authUser == null) {
      return const AdminAccess(isAdmin: false, workspaceReady: false);
    }
    var profile = user;
    if (!profile.isAdmin && isSuperAdmin) {
      await _users.promoteSelfToAdmin(profile.uid);
      profile = profile.copyWith(role: 'admin', status: 'active');
      _currentUser = profile;
    }
    if (!profile.isAdmin) {
      return const AdminAccess(isAdmin: false, workspaceReady: false);
    }
    try {
      final workspace = _workspace();
      var ready = await workspace.isWorkspaceAdmin(profile.uid);
      if (!ready && isSuperAdmin) {
        await workspace.setWorkspaceAdmin(profile.uid, true);
        ready = true;
      }
      notifyListeners();
      return AdminAccess(
        isAdmin: true,
        workspaceReady: ready,
        message: ready
            ? ''
            : 'Admin workspace access is not linked yet. Ask the super admin to re-grant admin access.',
      );
    } catch (error, stack) {
      ErrorTracker().logError(
        'Admin workspace check failed',
        error: error,
        stackTrace: stack,
      );
      return AdminAccess(
        isAdmin: true,
        workspaceReady: false,
        message: 'Admin workspace is unreachable: $error',
      );
    }
  }

  // --------------------------------------------------------------- profil

  Future<void> updateProfile(AppUser updated) async {
    await _users.updateProfile(updated);
    _currentUser = updated.copyWith(
      profileCompletePercent: AppUser.computeProfilePercent(updated),
    );
    notifyListeners();
  }

  Future<void> clearUnreadNotifications() async {
    final user = _currentUser;
    if (user == null || user.unreadNotifications == 0) return;
    await _users.clearUnread(user.uid);
  }

  // ---------------------------------------------------------- padam akaun

  /// Firebase memerlukan log masuk terkini sebelum akaun dipadam.
  Future<void> reauthenticate() async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('Not signed in.');
    await _google.reauthenticate(user);
  }

  Future<DeletionReport> deleteAccount({String reason = ''}) {
    final profile = _currentUser;
    if (profile != null && profile.isAdmin) {
      throw StateError(
        'Admin accounts cannot be deleted here. Ask the super admin to remove your admin role first.',
      );
    }
    return _busy(() async {
      await reauthenticate();
      final user = _auth.currentUser!;
      final report = await _deletion.deleteStudentData(user.uid, reason: reason);
      _stopProfileStream();
      await user.delete();
      await _google.signOut().catchError((_) {});
      _currentUser = null;
      _firebaseUser = null;
      return report;
    });
  }

  Future<void> signOut() async {
    _stopProfileStream();
    try {
      await _google.signOut();
    } catch (_) {}
    try {
      await _auth.signOut();
    } catch (error, stack) {
      ErrorTracker().logError('Sign out failed', error: error, stackTrace: stack);
    } finally {
      _currentUser = null;
      _firebaseUser = null;
      _profileLoaded = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _stopProfileStream();
    super.dispose();
  }
}
