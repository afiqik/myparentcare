import 'dart:collection';

import '../database_storage/models.dart';

/// Cache memori LRU untuk media yang telah dimuat turun.
///
/// Dokumen media tidak pernah diubah selepas dicipta (hanya dipadam), jadi
/// selamat untuk disimpan tanpa tarikh luput. Digabung dengan cache Firestore
/// pada cakera, setiap gambar hanya dimuat turun sekali bagi setiap peranti.
class MediaCache {
  final int maxEntries;
  final int maxBytes;
  final LinkedHashMap<String, MediaItem> _items = LinkedHashMap();
  int _bytes = 0;

  MediaCache({this.maxEntries = 80, this.maxBytes = 48 * 1024 * 1024});

  int get length => _items.length;
  int get bytes => _bytes;

  MediaItem? get(String id) {
    final item = _items.remove(id);
    if (item != null) _items[id] = item; // tandakan sebagai terkini
    return item;
  }

  void put(MediaItem item) {
    final previous = _items.remove(item.id);
    if (previous != null) _bytes -= previous.bytes?.length ?? 0;
    _items[item.id] = item;
    _bytes += item.bytes?.length ?? 0;
    while (_items.length > maxEntries || _bytes > maxBytes) {
      final oldest = _items.keys.first;
      final removed = _items.remove(oldest);
      _bytes -= removed?.bytes?.length ?? 0;
    }
  }

  void remove(String id) {
    final removed = _items.remove(id);
    _bytes -= removed?.bytes?.length ?? 0;
  }

  void clear() {
    _items.clear();
    _bytes = 0;
  }
}
