import 'dart:math';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_parent_care/availability/connectivity_manager.dart';
import 'package:my_parent_care/firebase_options.dart';
import 'package:my_parent_care/load_balancer_scaling/retry_policy.dart';
import 'package:my_parent_care/rate_limiting/rate_limiter.dart';

void main() {
  group('RetryPolicy: backoff eksponen + jitter (elak "thundering herd")', () {
    test('kelewatan meningkat 2x dan dihadkan pada maxDelay', () {
      final policy = RetryPolicy(random: Random(1));
      final delays = [for (var i = 0; i < 8; i++) policy.delayFor(i).inMilliseconds];
      // jitter 0.5x–1.5x daripada nilai asas.
      expect(delays[0], inInclusiveRange(20, 60));
      expect(delays[3], inInclusiveRange(160, 480));
      for (final d in delays) {
        expect(d, lessThanOrEqualTo(3000));
      }
      expect(policy.delayFor(30).inMilliseconds, inInclusiveRange(1000, 3000), reason: 'had maxDelay 2s');
    });

    test('jitter: klien berbeza menunggu masa berbeza', () {
      final a = RetryPolicy(random: Random(1)).delayFor(4);
      final b = RetryPolicy(random: Random(99)).delayFor(4);
      expect(a, isNot(b));
    });

    test('immediate (ujian) tiada kelewatan; wait() selesai', () async {
      expect(RetryPolicy.immediate.delayFor(5), Duration.zero);
      await RetryPolicy.immediate.wait(3);
      await RetryPolicy(baseDelay: const Duration(milliseconds: 1), random: Random(1)).wait(0);
    });
  });

  group('RateLimiter: lindungi kuota daripada tekan berulang', () {
    setUp(RateLimiter.resetAll);

    test('tindakan kedua dalam tempoh cooldown ditolak; selepas itu dibenarkan', () {
      final t0 = DateTime(2026, 10, 1, 9);
      expect(RateLimiter.throttle('join', now: t0), isTrue);
      expect(RateLimiter.throttle('join', now: t0.add(const Duration(seconds: 1))), isFalse);
      expect(
        RateLimiter.remaining('join', cooldown: const Duration(seconds: 2), now: t0.add(const Duration(seconds: 1))),
        const Duration(seconds: 1),
      );
      expect(RateLimiter.throttle('join', now: t0.add(const Duration(seconds: 3))), isTrue);
      expect(RateLimiter.remaining('join', cooldown: const Duration(seconds: 2), now: t0.add(const Duration(seconds: 10))),
          Duration.zero);
    });

    test('kunci berasingan tidak saling menyekat; reset membenarkan semula', () {
      final t0 = DateTime(2026, 10, 1, 9);
      expect(RateLimiter.throttle('a', now: t0), isTrue);
      expect(RateLimiter.throttle('b', now: t0), isTrue);
      RateLimiter.reset('a');
      expect(RateLimiter.throttle('a', now: t0), isTrue);
      expect(RateLimiter.remaining('tiada', cooldown: const Duration(seconds: 2)), Duration.zero);
    });
  });

  group('ConnectivityManager: jalur luar talian', () {
    test('Firestore luar talian hanya selepas tempoh tenang; RTDB admin serta-merta', () {
      fakeAsync((async) {
        void advance(Duration d) => async.elapse(d);
        final manager = ConnectivityManager(offlineGrace: const Duration(seconds: 4));
        var changes = 0;
        manager.addListener(() => changes++);

        manager.reportFirestore(online: false);
        advance(const Duration(seconds: 2));
        expect(manager.isConnected, isTrue);
        manager.reportFirestore(online: true);
        advance(const Duration(seconds: 5));
        expect(manager.isConnected, isTrue, reason: 'terputus sekejap diabaikan');
        expect(changes, 0);

        manager.reportFirestore(online: false);
        manager.reportFirestore(online: false); // pendua diabaikan
        advance(const Duration(seconds: 5));
        expect(manager.firestoreOnline, isFalse);
        expect(manager.isConnected, isFalse);
        manager.reportFirestore(online: true);
        expect(manager.isConnected, isTrue);

        manager.reportWorkspace(online: false);
        expect(manager.workspaceOnline, isFalse);
        expect(manager.isConnected, isFalse);
        manager.reportWorkspace(online: false); // tiada perubahan
        manager.reportWorkspace(online: null); // pelajar: tiada ruang kerja
        expect(manager.isConnected, isTrue);
        manager.dispose();
      });
    });
  });

  group('DefaultFirebaseOptions: aplikasi disambung ke projek yang betul', () {
    tearDown(() => debugDefaultTargetPlatformOverride = null);

    test('Android & iOS → myparentcare-45eb1', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final android = DefaultFirebaseOptions.currentPlatform;
      expect(android.projectId, 'myparentcare-45eb1');
      expect(android.databaseURL, contains('asia-southeast1'));
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      expect(DefaultFirebaseOptions.currentPlatform.projectId, 'myparentcare-45eb1');
    });

    test('platform tidak disokong ditolak dengan jelas', () {
      for (final platform in [TargetPlatform.macOS, TargetPlatform.windows, TargetPlatform.linux]) {
        debugDefaultTargetPlatformOverride = platform;
        expect(() => DefaultFirebaseOptions.currentPlatform, throwsUnsupportedError, reason: '$platform');
      }
    });
  });
}
