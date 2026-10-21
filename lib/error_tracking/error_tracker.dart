import 'dart:developer' as developer;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../database_storage/firestore_paths.dart';

/// Penjejak ralat ringan (percuma): log tempatan + laporan ke Firestore
/// `error_reports` yang hanya boleh dibaca oleh admin.
///
/// Had perlindungan kuota: maksimum [maxReportsPerSession] laporan setiap sesi
/// dan ralat yang sama tidak dihantar semula dalam [dedupeWindow].
class ErrorTracker {
  static final ErrorTracker _instance = ErrorTracker._internal();
  factory ErrorTracker() => _instance;
  ErrorTracker._internal();

  static const maxReportsPerSession = 20;
  static const dedupeWindow = Duration(minutes: 5);

  FirebaseFirestore? _firestore;
  String? Function()? _currentUid;
  String _appVersion = '';
  int _sent = 0;
  final Map<String, DateTime> _recent = {};

  void configure({
    required FirebaseFirestore firestore,
    required String? Function() currentUid,
    String appVersion = '',
  }) {
    _firestore = firestore;
    _currentUid = currentUid;
    _appVersion = appVersion;
  }

  @visibleForTesting
  void reset() {
    _firestore = null;
    _currentUid = null;
    _sent = 0;
    _recent.clear();
  }

  static String get platform {
    if (kIsWeb) return 'web';
    return defaultTargetPlatform.name;
  }

  Future<void> logError(
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) async {
    developer.log(
      'ERROR: $message',
      name: 'MyParentCare.ErrorTracker',
      error: error,
      stackTrace: stackTrace,
    );

    final firestore = _firestore;
    final uid = _currentUid?.call();
    if (firestore == null || uid == null) return;
    if (_sent >= maxReportsPerSession) return;

    final key = '$message|${error.runtimeType}';
    final last = _recent[key];
    final now = DateTime.now();
    if (last != null && now.difference(last) < dedupeWindow) return;
    _recent[key] = now;
    _sent++;

    String clip(String value, int max) =>
        value.length <= max ? value : value.substring(0, max);

    try {
      await firestore.collection(FirestorePaths.errorReports).add({
        'message': clip(message, 500),
        'error': clip(error?.toString() ?? '', 2000),
        'stackTrace': clip(stackTrace?.toString() ?? '', 6000),
        'platform': platform,
        'appVersion': clip(_appVersion, 30),
        'uid': uid,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      developer.log(
        'Failed to upload error report: $e',
        name: 'MyParentCare.ErrorTracker',
      );
    }
  }

  void logWarning(String message) {
    developer.log('WARNING: $message', name: 'MyParentCare.ErrorTracker');
  }
}
