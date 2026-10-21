import 'package:cloud_firestore/cloud_firestore.dart';

import 'firestore_paths.dart';
import 'models.dart';

class UserPage {
  final List<AppUser> users;
  final DocumentSnapshot<Map<String, dynamic>>? lastDoc;
  final bool hasMore;

  const UserPage({required this.users, this.lastDoc, required this.hasMore});
}

/// Akses `users/{uid}` dan notifikasi pelajar dalam Firestore.
class UserRepository {
  final FirebaseFirestore _db;

  UserRepository(this._db);

  DocumentReference<Map<String, dynamic>> _ref(String uid) =>
      _db.doc(FirestorePaths.user(uid));

  Future<AppUser?> fetch(String uid) async {
    final snapshot = await _ref(uid).get();
    final data = snapshot.data();
    if (!snapshot.exists || data == null) return null;
    return AppUser.fromMap(data);
  }

  Stream<AppUser?> watch(String uid) => _ref(uid).snapshots().map((snapshot) {
    final data = snapshot.data();
    if (!snapshot.exists || data == null) return null;
    return AppUser.fromMap(data);
  });

  /// Cipta profil baharu (pelajar, atau admin untuk super admin).
  Future<void> create(AppUser user) async {
    await _ref(user.uid).set({
      ...user.toNewUserMap(),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'consentAt': FieldValue.serverTimestamp(),
    });
  }

  /// Kemas kini medan profil yang dibenarkan sahaja.
  Future<void> updateProfile(AppUser user, {bool renewConsent = false}) async {
    await _ref(user.uid).update({
      ...user.toProfileMap(),
      if (renewConsent) 'consentAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> clearUnread(String uid) =>
      _ref(uid).update({'unreadNotifications': 0});

  Future<void> promoteSelfToAdmin(String uid) => _ref(uid).update({
    'role': 'admin',
    'status': 'active',
    'updatedAt': FieldValue.serverTimestamp(),
  });

  // ------------------------------------------------------------------ admin

  Future<UserPage> listUsers({
    String? role,
    DocumentSnapshot<Map<String, dynamic>>? startAfter,
    int limit = 30,
  }) async {
    Query<Map<String, dynamic>> query = _db.collection(FirestorePaths.users);
    if (role != null) query = query.where('role', isEqualTo: role);
    query = query.orderBy('createdAt', descending: true).limit(limit);
    if (startAfter != null) query = query.startAfterDocument(startAfter);
    final snapshot = await query.get();
    return UserPage(
      users: snapshot.docs.map((d) => AppUser.fromMap(d.data())).toList(),
      lastDoc: snapshot.docs.isEmpty ? null : snapshot.docs.last,
      hasMore: snapshot.docs.length == limit,
    );
  }

  Future<AppUser?> findByEmail(String email) async {
    final snapshot = await _db
        .collection(FirestorePaths.users)
        .where('email', isEqualTo: email.trim().toLowerCase())
        .limit(1)
        .get();
    if (snapshot.docs.isEmpty) return null;
    return AppUser.fromMap(snapshot.docs.first.data());
  }

  Future<int> countUsers({String? role}) async {
    Query<Map<String, dynamic>> query = _db.collection(FirestorePaths.users);
    if (role != null) query = query.where('role', isEqualTo: role);
    final result = await query.count().get();
    return result.count ?? 0;
  }

  Future<void> setStatus(String uid, String status) => _ref(uid).update({
    'status': status,
    'updatedAt': FieldValue.serverTimestamp(),
  });

  Future<void> setRole(String uid, String role) => _ref(uid).update({
    'role': role,
    'status': 'active',
    'updatedAt': FieldValue.serverTimestamp(),
  });

  // ------------------------------------------------------------ notifikasi

  Future<List<StudentNotification>> fetchNotifications(
    String uid, {
    int limit = 30,
  }) async {
    final snapshot = await _db
        .collection(FirestorePaths.userNotifications(uid))
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .get();
    return snapshot.docs
        .map((d) => StudentNotification.fromMap(d.data()))
        .toList();
  }

  Future<void> markNotificationRead(String uid, String id) => _db
      .doc('${FirestorePaths.userNotifications(uid)}/$id')
      .update({'isRead': true});
}
