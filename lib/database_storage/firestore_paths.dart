/// Laluan koleksi Firestore – satu sumber supaya selaras dengan firestore.rules.
class FirestorePaths {
  FirestorePaths._();

  static const users = 'users';
  static const notifications = 'notifications';
  static const programs = 'programs';
  static const participants = 'participants';
  static const programSeats = 'program_seats';
  static const shards = 'shards';
  static const catalogDoc = 'public/catalog';
  static const media = 'media';
  static const emailLogs = 'email_logs';
  static const errorReports = 'error_reports';
  static const accountDeletions = 'account_deletions';

  static String user(String uid) => '$users/$uid';
  static String userNotifications(String uid) => '$users/$uid/$notifications';
  static String program(String pid) => '$programs/$pid';
  static String programParticipants(String pid) => '$programs/$pid/$participants';
  static String participant(String pid, String uid) =>
      '$programs/$pid/$participants/$uid';
  static String programShards(String pid) => '$programSeats/$pid/$shards';
  static String shard(String pid, String shardId) =>
      '$programSeats/$pid/$shards/$shardId';
}
