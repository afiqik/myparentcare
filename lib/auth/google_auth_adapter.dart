import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../app_config.dart';

/// Abstraksi Google Sign-In supaya logik auth boleh diuji tanpa peranti.
abstract class GoogleAuthAdapter {
  /// Pulangkan `null` jika pengguna membatalkan.
  Future<UserCredential?> signIn(FirebaseAuth auth);
  Future<void> reauthenticate(User user);
  Future<void> signOut();
}

/// Android/iOS: pakej google_sign_in. Web: popup Firebase Auth.
///
/// Error 10 (DEVELOPER_ERROR) pada Android bermaksud cap jari SHA-1 aplikasi
/// yang dipasang tidak didaftarkan dalam Firebase. Lihat docs/PRODUCTION_SETUP.md
/// – SHA-1 upload key DAN Play App Signing key mesti ditambah.
class DefaultGoogleAuthAdapter implements GoogleAuthAdapter {
  // Dicipta secara lazy dan TIDAK pernah pada web: constructor GoogleSignIn
  // memulakan plugin web serta-merta, yang gagal tanpa client ID web (web
  // menggunakan popup Firebase Auth sebaliknya).
  GoogleSignIn? _instance;
  GoogleSignIn get _googleSignIn => _instance ??= GoogleSignIn(
    serverClientId: AppConfig.googleServerClientId,
    scopes: const ['email'],
  );

  @override
  Future<UserCredential?> signIn(FirebaseAuth auth) async {
    if (kIsWeb) {
      final provider = GoogleAuthProvider()
        ..setCustomParameters({'prompt': 'select_account'});
      return auth.signInWithPopup(provider);
    }
    // Kosongkan sesi lama supaya pemilih akaun sentiasa dipaparkan.
    await _googleSignIn.signOut().catchError((_) => null);
    final account = await _googleSignIn.signIn();
    if (account == null) return null;
    final tokens = await account.authentication;
    if (tokens.idToken == null || tokens.idToken!.isEmpty) {
      throw StateError(
        'Google did not return an ID token. Check the SHA-1 fingerprints in Firebase.',
      );
    }
    return auth.signInWithCredential(
      GoogleAuthProvider.credential(
        idToken: tokens.idToken,
        accessToken: tokens.accessToken,
      ),
    );
  }

  @override
  Future<void> reauthenticate(User user) async {
    if (kIsWeb) {
      await user.reauthenticateWithPopup(GoogleAuthProvider());
      return;
    }
    final account = await _googleSignIn.signIn();
    if (account == null) throw StateError('Re-authentication was cancelled.');
    final tokens = await account.authentication;
    await user.reauthenticateWithCredential(
      GoogleAuthProvider.credential(
        idToken: tokens.idToken,
        accessToken: tokens.accessToken,
      ),
    );
  }

  @override
  Future<void> signOut() async {
    if (kIsWeb) return;
    await _googleSignIn.signOut();
  }
}
