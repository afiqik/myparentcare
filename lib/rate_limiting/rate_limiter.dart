/// Pengehad kadar di sisi klien. Tujuannya melindungi kuota Spark (bacaan,
/// tulisan, emel) daripada tekan berulang; perlindungan sebenar data berada
/// dalam Security Rules.
class RateLimiter {
  RateLimiter._();

  static final Map<String, DateTime> _lastActionTimes = {};

  /// Pulangkan `true` jika tindakan dibenarkan sekarang.
  static bool throttle(
    String actionKey, {
    Duration cooldown = const Duration(seconds: 2),
    DateTime? now,
  }) {
    final current = now ?? DateTime.now();
    final lastTime = _lastActionTimes[actionKey];
    if (lastTime != null && current.difference(lastTime) < cooldown) {
      return false;
    }
    _lastActionTimes[actionKey] = current;
    return true;
  }

  /// Baki masa menunggu sebelum [actionKey] dibenarkan semula.
  static Duration remaining(
    String actionKey, {
    required Duration cooldown,
    DateTime? now,
  }) {
    final lastTime = _lastActionTimes[actionKey];
    if (lastTime == null) return Duration.zero;
    final left = cooldown - (now ?? DateTime.now()).difference(lastTime);
    return left.isNegative ? Duration.zero : left;
  }

  static void reset(String actionKey) => _lastActionTimes.remove(actionKey);

  static void resetAll() => _lastActionTimes.clear();
}
