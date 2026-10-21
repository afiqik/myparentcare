import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;

import '../error_tracking/error_tracker.dart';

/// Keputusan panggilan ke web app Apps Script (apps_script/Code.gs).
class RelayResult {
  /// sent | failed | queued | not_found | invalid | unavailable | error
  final String status;
  final bool keyConfigured;
  final String message;

  const RelayResult(this.status, {this.keyConfigured = false, this.message = ''});

  bool get ok => status != 'unavailable' && status != 'error' && status != 'invalid';
}

/// Emel SEGERA kepada ibu bapa selepas pelajar join.
///
/// Pelajar tidak memegang private key EmailJS (strict mode). Selepas join,
/// aplikasi memanggil web app Google Apps Script milik pemilik projek; skrip
/// membaca semula penyertaan dari Firestore dan menghantar emel pengesahan
/// dalam beberapa saat. Pautan web app disimpan dalam `public/config`.
/// Jika panggilan gagal, emel kekal "pending" dan dihantar oleh trigger
/// 5 minit skrip atau aplikasi admin.
class EmailRelay {
  static final urlPattern = RegExp(
    r'^https://script\.google\.com/(a/macros/[^/]+|macros)/s/[A-Za-z0-9_-]+/exec$',
  );
  static const configDoc = 'public/config';

  final FirebaseFirestore _db;
  final http.Client _client;
  final Duration timeout;
  final Duration cacheFor;

  EmailRelay(
    this._db, {
    http.Client? client,
    this.timeout = const Duration(seconds: 30),
    this.cacheFor = const Duration(minutes: 10),
  }) : _client = client ?? http.Client();

  String? _url;
  DateTime? _loadedAt;

  static bool isValidUrl(String url) => urlPattern.hasMatch(url.trim());

  /// Pautan web app daripada public/config (disimpan sementara 10 minit).
  Future<String?> relayUrl({bool refresh = false}) async {
    final loadedAt = _loadedAt;
    if (!refresh && loadedAt != null && DateTime.now().difference(loadedAt) < cacheFor) {
      return _url;
    }
    try {
      final snapshot = await _db.doc(configDoc).get();
      final value = snapshot.data()?['emailRelayUrl'];
      _url = value is String && isValidUrl(value) ? value.trim() : null;
      _loadedAt = DateTime.now();
    } catch (error, stack) {
      ErrorTracker().logError('Read email relay URL failed', error: error, stackTrace: stack);
    }
    return _url;
  }

  /// Admin: simpan pautan web app supaya aplikasi pelajar menggunakannya.
  Future<void> saveRelayUrl(String url, {required String adminUid}) async {
    final clean = url.trim();
    if (!isValidUrl(clean)) {
      throw ArgumentError('Pautan mesti bermula https://script.google.com/macros/s/ dan berakhir /exec');
    }
    await _db.doc(configDoc).set({
      'emailRelayUrl': clean,
      'emailRelayUpdatedBy': adminUid,
      'emailRelayUpdatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    _url = clean;
    _loadedAt = DateTime.now();
  }

  /// Pelajar: minta emel pengesahan dihantar sekarang. Tidak pernah membaling ralat.
  Future<RelayResult> notifyJoin({required String programId, required String uid}) async {
    final url = await relayUrl();
    if (url == null) return const RelayResult('unavailable');
    return _call(url, {'action': 'join', 'programId': programId, 'uid': uid});
  }

  /// Admin: semak web app menjawab (dan private key ada).
  Future<RelayResult> ping(String url) async {
    if (!isValidUrl(url)) return const RelayResult('invalid', message: 'Pautan tidak sah');
    return _call(url.trim(), {'action': 'ping'});
  }

  Future<RelayResult> _call(String url, Map<String, Object?> body) async {
    try {
      var response = await _client
          .post(
            Uri.parse(url),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(timeout);
      // Apps Script menjawab POST dengan 302 ke script.googleusercontent.com.
      final location = response.headers['location'];
      if (response.statusCode >= 300 && response.statusCode < 400 && location != null) {
        response = await _client.get(Uri.parse(location)).timeout(timeout);
      }
      if (response.statusCode != 200) {
        return RelayResult('error', message: 'HTTP ${response.statusCode}');
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) return const RelayResult('error', message: 'Jawapan tidak sah');
      if (decoded['service'] != null) {
        return RelayResult(
          decoded['ok'] == true ? 'ok' : 'error',
          keyConfigured: decoded['keyConfigured'] == true,
        );
      }
      return RelayResult(decoded['status']?.toString() ?? 'error');
    } catch (error) {
      return RelayResult('error', message: '$error');
    }
  }
}
