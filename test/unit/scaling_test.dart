import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_parent_care/availability/connectivity_manager.dart';
import 'package:my_parent_care/cache_cdn/media_cache.dart';
import 'package:my_parent_care/database_storage/models.dart';
import 'package:my_parent_care/load_balancer_scaling/retry_policy.dart';
import 'package:my_parent_care/load_balancer_scaling/seat_planner.dart';
import 'package:my_parent_care/rate_limiting/rate_limiter.dart';
import 'dart:typed_data';

void main() {
  group('SeatPlanner (shard kaunter tempat)', () {
    test('kapasiti dibahagi ~10 tempat setiap shard, jumlah tepat', () {
      for (final capacity in [1, 9, 10, 11, 150, 333, 5000]) {
        final caps = SeatPlanner.initialCaps(capacity);
        expect(caps.reduce((a, b) => a + b), capacity, reason: '$capacity');
        expect(caps.length, lessThanOrEqualTo(SeatPlanner.maxShards));
        expect(caps.every((c) => c > 0), isTrue);
      }
      expect(SeatPlanner.initialCaps(150).length, 15);
      expect(SeatPlanner.initialCaps(5000).length, 50);
    });

    test('rebalance mengekalkan kiraan semasa dan jumlah = kapasiti baharu', () {
      const existing = [
        SeatShard(id: 's00', count: 5, cap: 5),
        SeatShard(id: 's01', count: 2, cap: 5),
      ];
      final caps = SeatPlanner.rebalance(existing: existing, newCapacity: 30);
      expect(caps.values.reduce((a, b) => a + b), 30);
      expect(caps['s00']! >= 5, isTrue);
      expect(caps['s01']! >= 2, isTrue);
      expect(caps.length, 3); // shard baharu ditambah
    });

    test('kapasiti tidak boleh kurang daripada pelajar yang sudah sertai', () {
      const existing = [SeatShard(id: 's00', count: 8, cap: 10)];
      expect(
        () => SeatPlanner.rebalance(existing: existing, newCapacity: 5),
        throwsArgumentError,
      );
      final caps = SeatPlanner.rebalance(existing: existing, newCapacity: 8);
      expect(caps['s00'], 8);
    });

    test('summarize menjumlahkan shard', () {
      final s = SeatPlanner.summarize(const [
        SeatShard(id: 'a', count: 3, cap: 5),
        SeatShard(id: 'b', count: 5, cap: 5),
      ]);
      expect(s.joined, 8);
      expect(s.capacity, 10);
      expect(s.remaining, 2);
      expect(s.isFull, isFalse);
    });
  });

  test('RetryPolicy: backoff eksponen dengan had maksimum', () {
    final policy = RetryPolicy(baseDelay: const Duration(milliseconds: 100), maxDelay: const Duration(seconds: 1));
    for (var i = 1; i < 10; i++) {
      final d = policy.delayFor(i).inMilliseconds;
      expect(d, lessThanOrEqualTo(1500));
      expect(d, greaterThanOrEqualTo(50));
    }
    expect(RetryPolicy.immediate.delayFor(5), Duration.zero);
  });

  test('RateLimiter: menyekat tindakan berulang dalam tempoh cooldown', () {
    RateLimiter.resetAll();
    final t0 = DateTime(2026);
    expect(RateLimiter.throttle('k', now: t0), isTrue);
    expect(RateLimiter.throttle('k', now: t0.add(const Duration(seconds: 1))), isFalse);
    expect(
      RateLimiter.remaining('k', cooldown: const Duration(seconds: 2), now: t0.add(const Duration(seconds: 1))),
      const Duration(seconds: 1),
    );
    expect(RateLimiter.throttle('k', now: t0.add(const Duration(seconds: 3))), isTrue);
  });

  test('MediaCache: LRU membuang item paling lama apabila penuh', () {
    final cache = MediaCache(maxEntries: 2, maxBytes: 1000);
    MediaItem item(String id, int size) =>
        MediaItem(id: id, programId: 'p', kind: 'image', bytes: Uint8List(size));
    cache.put(item('a', 100));
    cache.put(item('b', 100));
    cache.get('a'); // a kini terkini
    cache.put(item('c', 100));
    expect(cache.get('b'), isNull);
    expect(cache.get('a'), isNotNull);
    cache.put(item('big', 900));
    expect(cache.bytes, lessThanOrEqualTo(1000));
  });

  test('ConnectivityManager: luar talian hanya selepas tempoh tenggang', () {
    fakeAsync((async) {
      final manager = ConnectivityManager(offlineGrace: const Duration(seconds: 4));
      manager.reportFirestore(online: false);
      expect(manager.isConnected, isTrue);
      async.elapse(const Duration(seconds: 2));
      manager.reportFirestore(online: true); // pulih sebelum tamat tempoh
      async.elapse(const Duration(seconds: 5));
      expect(manager.isConnected, isTrue);
      manager.reportFirestore(online: false);
      async.elapse(const Duration(seconds: 5));
      expect(manager.isConnected, isFalse);
      manager.reportWorkspace(online: false);
      manager.reportFirestore(online: true);
      expect(manager.isConnected, isFalse);
    });
  });
}
