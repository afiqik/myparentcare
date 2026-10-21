import 'dart:async';
import 'dart:math';

/// Exponential backoff dengan "jitter" – mengelakkan semua klien mencuba
/// semula pada saat yang sama (thundering herd) apabila berlaku kesesakan.
class RetryPolicy {
  final int maxAttempts;
  final Duration baseDelay;
  final Duration maxDelay;
  final Random _random;

  RetryPolicy({
    this.maxAttempts = 12,
    this.baseDelay = const Duration(milliseconds: 40),
    this.maxDelay = const Duration(seconds: 2),
    Random? random,
  }) : _random = random ?? Random();

  /// Untuk ujian: tiada kelewatan.
  static final immediate = RetryPolicy(baseDelay: Duration.zero);

  Duration delayFor(int attempt) {
    if (baseDelay == Duration.zero) return Duration.zero;
    final exp = baseDelay.inMilliseconds * pow(2, attempt.clamp(0, 10));
    final capped = min(exp.toDouble(), maxDelay.inMilliseconds.toDouble());
    final jittered = capped * (0.5 + _random.nextDouble());
    return Duration(milliseconds: jittered.round());
  }

  Future<void> wait(int attempt) {
    final delay = delayFor(attempt);
    if (delay == Duration.zero) return Future.value();
    return Future.delayed(delay);
  }
}
