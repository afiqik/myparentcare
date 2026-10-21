import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';

/// Tukar ralat teknikal kepada mesej yang difahami pengguna.
String friendlyError(Object error, {bool google = false}) {
  if (error is FirebaseAuthException) {
    switch (error.code) {
      case 'network-request-failed':
        return 'No internet connection. Check Wi-Fi or mobile data.';
      case 'user-disabled':
        return 'This account has been disabled.';
      case 'invalid-credential':
      case 'wrong-password':
      case 'user-not-found':
      case 'invalid-login-credentials':
        return 'Email or password is incorrect.';
      case 'email-already-in-use':
        return 'This email is already registered. Try signing in instead.';
      case 'weak-password':
        return 'Choose a stronger password (8+ characters with letters and numbers).';
      case 'invalid-email':
        return 'Enter a valid email address.';
      case 'too-many-requests':
        return 'Too many attempts. Please wait a few minutes and try again.';
      case 'requires-recent-login':
        return 'Please sign in again to confirm this action.';
      case 'account-exists-with-different-credential':
        return 'This email already uses another sign-in method.';
      case 'popup-closed-by-user':
      case 'cancelled-popup-request':
        return 'Sign-in was cancelled.';
      case 'popup-blocked':
        return 'Your browser blocked the sign-in popup. Allow popups and try again.';
      case 'unauthorized-domain':
        return 'This website is not authorised for sign-in yet.';
      default:
        return error.message ?? 'Authentication failed (${error.code}).';
    }
  }
  if (error is PlatformException) {
    final details = '${error.code} ${error.message ?? ''}';
    if (details.contains('ApiException: 10') ||
        details.contains('DEVELOPER_ERROR') ||
        RegExp(r'\b10\b').hasMatch(details)) {
      return 'Google sign-in is not configured for this app build (error 10). '
          'The app SHA-1 fingerprint must be registered in Firebase.';
    }
    if (details.contains('network_error') || details.contains('ApiException: 7')) {
      return 'Google could not connect. Check the internet connection.';
    }
    if (details.contains('sign_in_canceled') || details.contains('12501')) {
      return 'Sign-in was cancelled.';
    }
    return google
        ? 'Google sign-in failed (${error.code}).'
        : 'Something went wrong (${error.code}).';
  }
  if (error is FirebaseException) {
    switch (error.code) {
      case 'permission-denied':
        return 'You do not have permission to do this.';
      case 'unavailable':
        return 'The service is temporarily unavailable. Check your connection and try again.';
      case 'resource-exhausted':
        return 'The daily free quota has been reached. Please try again later.';
      case 'not-found':
        return 'The requested item no longer exists.';
      default:
        return error.message ?? 'Something went wrong (${error.code}).';
    }
  }
  if (error is StateError) return error.message;
  if (error is ArgumentError) return error.message?.toString() ?? '$error';
  if (error is FormatException) return error.message;
  return google
      ? 'Google sign-in could not continue. Please try again.'
      : 'Something went wrong. Please try again.';
}
