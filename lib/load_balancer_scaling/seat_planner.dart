import '../database_storage/models.dart';

/// Merancang pembahagian kapasiti program kepada beberapa shard kaunter.
///
/// Firestore menghadkan kadar tulisan pada satu dokumen (~1 tulisan/saat
/// berterusan). Dengan memecahkan kapasiti kepada shard, ratusan pelajar boleh
/// mendaftar serentak tanpa bertembung pada satu dokumen. Ujian beban
/// (tests/firebase/load) mengesahkan 400 pendaftaran serentak tanpa overbooking.
class SeatPlanner {
  SeatPlanner._();

  static const seatsPerShard = 10;
  static const maxShards = 50;

  static String shardId(int index) => 's${index.toString().padLeft(2, '0')}';

  static int shardCountFor(int capacity) {
    if (capacity <= 0) return 1;
    return ((capacity + seatsPerShard - 1) ~/ seatsPerShard).clamp(
      1,
      maxShards,
    );
  }

  /// Had setiap shard untuk program baharu (jumlah = kapasiti).
  static List<int> initialCaps(int capacity) {
    final shards = shardCountFor(capacity);
    return List.generate(
      shards,
      (k) => capacity ~/ shards + (k < capacity % shards ? 1 : 0),
    );
  }

  /// Susun semula had shard apabila admin menukar kapasiti.
  ///
  /// Syarat: had baharu setiap shard tidak boleh kurang daripada kiraan
  /// semasanya, dan jumlah had = kapasiti baharu. Shard baharu ditambah jika
  /// kapasiti bertambah melebihi saiz optimum.
  static Map<String, int> rebalance({
    required List<SeatShard> existing,
    required int newCapacity,
  }) {
    final joined = existing.fold<int>(0, (sum, s) => sum + s.count);
    if (newCapacity < joined) {
      throw ArgumentError(
        'Capacity cannot be lower than $joined joined students.',
      );
    }
    final targetShards = shardCountFor(
      newCapacity,
    ).clamp(existing.isEmpty ? 1 : existing.length, maxShards);
    final ids = <String>[
      ...existing.map((s) => s.id),
      for (var k = existing.length; k < targetShards; k++) shardId(k),
    ];
    final counts = {for (final s in existing) s.id: s.count};

    // Mulakan setiap shard dengan kiraan semasanya, kemudian agihkan baki
    // tempat kosong secara sama rata supaya pendaftaran tersebar.
    final caps = {for (final id in ids) id: counts[id] ?? 0};
    var free = newCapacity - joined;
    var index = 0;
    while (free > 0) {
      final id = ids[index % ids.length];
      caps[id] = caps[id]! + 1;
      free--;
      index++;
    }
    return caps;
  }

  static SeatSummary summarize(Iterable<SeatShard> shards) {
    var joined = 0;
    var capacity = 0;
    for (final s in shards) {
      joined += s.count;
      capacity += s.cap;
    }
    return SeatSummary(joined: joined, capacity: capacity);
  }
}
