import 'dart:developer' as developer;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';

/// Konfigurasi cache luar talian.
///
/// * Firestore: cache berterusan (Android/iOS & web IndexedDB) 100 MB. Katalog,
///   profil dan media yang sudah dibaca dipaparkan serta-merta walaupun luar
///   talian, dan tidak dikira sebagai bacaan baharu.
/// * RTDB (ruang kerja admin sahaja): persistence pada peranti mudah alih.
class CacheManager {
  CacheManager._();

  static const firestoreCacheBytes = 100 * 1024 * 1024;
  static const rtdbCacheBytes = 10 * 1024 * 1024;

  static void configureFirestore(FirebaseFirestore firestore) {
    try {
      firestore.settings = const Settings(
        persistenceEnabled: true,
        cacheSizeBytes: firestoreCacheBytes,
      );
    } catch (error) {
      developer.log(
        'Firestore cache settings skipped: $error',
        name: 'MyParentCare.Cache',
      );
    }
  }

  static void configureRealtimeDatabase(FirebaseDatabase database) {
    if (kIsWeb) return; // Persistence RTDB tidak disokong di web.
    try {
      database.setPersistenceEnabled(true);
      database.setPersistenceCacheSizeBytes(rtdbCacheBytes);
    } catch (error) {
      developer.log(
        'RTDB persistence skipped: $error',
        name: 'MyParentCare.Cache',
      );
    }
  }
}
