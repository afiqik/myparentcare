import 'dart:async';

import 'package:flutter/foundation.dart';

/// Status sambungan aplikasi.
///
/// Pelajar: dikesan daripada metadata katalog Firestore (`isFromCache`) –
/// tidak membuka sambungan RTDB (had 100 sambungan serentak pelan Spark).
/// Admin: juga daripada `.info/connected` ruang kerja RTDB.
///
/// Status "luar talian" hanya dipaparkan selepas [offlineGrace] supaya
/// snapshot cache pertama semasa aplikasi dibuka tidak menyebabkan kelipan.
class ConnectivityManager extends ChangeNotifier {
  final Duration offlineGrace;

  ConnectivityManager({this.offlineGrace = const Duration(seconds: 4)});

  bool _firestoreOnline = true;
  bool? _workspaceOnline;
  Timer? _pendingOffline;

  bool get isConnected => _firestoreOnline && (_workspaceOnline ?? true);
  bool get firestoreOnline => _firestoreOnline;
  bool? get workspaceOnline => _workspaceOnline;

  void reportFirestore({required bool online}) {
    if (online) {
      _pendingOffline?.cancel();
      _pendingOffline = null;
      if (!_firestoreOnline) {
        _firestoreOnline = true;
        notifyListeners();
      }
      return;
    }
    if (!_firestoreOnline || _pendingOffline != null) return;
    _pendingOffline = Timer(offlineGrace, () {
      _pendingOffline = null;
      _firestoreOnline = false;
      notifyListeners();
    });
  }

  void reportWorkspace({required bool? online}) {
    if (_workspaceOnline == online) return;
    _workspaceOnline = online;
    notifyListeners();
  }

  @override
  void dispose() {
    _pendingOffline?.cancel();
    super.dispose();
  }
}
