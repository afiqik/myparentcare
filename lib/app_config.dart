/// Konfigurasi pusat MyParentCare.
///
/// Nilai di sini BUKAN rahsia. Kunci rahsia (contohnya EmailJS private key)
/// tidak boleh diletakkan dalam aplikasi kerana sesiapa boleh membongkar APK.
class AppConfig {
  AppConfig._();

  static const appName = 'MyParentCare';

  /// Institusi sasaran. Aplikasi ini untuk pelajar institusi ini sahaja.
  static const institutionName = 'KPTM Batu Pahat';
  static const institutionShort = 'KPTM BP';
  static const audienceTagline = 'Khas untuk pelajar $institutionName';

  /// Emel hubungan awam (Dasar Privasi, Padam Akaun, Play Store).
  static const supportEmail = 'admin@myparentcare.com';

  /// Pemilik / pengawal data yang dipaparkan dalam Dasar Privasi.
  static const dataControllerName = 'Pasukan Pembangun MyParentCare';

  /// Versi Dasar Privasi. Tukar tarikh ini setiap kali dasar dikemas kini supaya
  /// pengguna diminta memberi persetujuan semula.
  static const privacyPolicyVersion = '2026-09-30';

  /// Super admin: satu-satunya akaun yang boleh melantik admin lain.
  /// MESTI sama dengan senarai dalam firestore.rules dan database.rules.json.
  static const superAdminEmails = <String>['admin@myparentcare.com'];

  static bool isSuperAdminEmail(String? email) =>
      email != null && superAdminEmails.contains(email.trim().toLowerCase());

  // --------------------------------------------------------------- web/links
  /// Laman muat turun (Firebase project website-81b96). Aplikasi ini HANYA
  /// untuk Android – tiada versi web aplikasi.
  static const websiteUrl = 'https://website-81b96.web.app';
  static const privacyPolicyUrl = '$websiteUrl/privacy';
  static const deleteAccountUrl = '$websiteUrl/delete-account';
  static const downloadUrl = '$websiteUrl/#muat-turun';

  // --------------------------------------------------------------- Firebase
  static const rtdbUrl =
      'https://myparentcare-45eb1-default-rtdb.asia-southeast1.firebasedatabase.app';

  /// Web client ID (OAuth) untuk Google Sign-In Android (serverClientId).
  static const googleServerClientId =
      '177388431094-pjn60qqln9mt3c156ra9c370dbdqctat.apps.googleusercontent.com';

  // ------------------------------------------------------------------ EmailJS
  // Hanya PUBLIC key (direka untuk didedahkan). Private key telah dibuang
  // daripada aplikasi – sila jana semula private key di dashboard EmailJS
  // kerana versi lama pernah terdedah dalam APK.
  static const emailJsServiceId = 'service_aeph2e8';
  static const emailJsTemplateId = 'template_pbwdb3p';
  static const emailJsPublicKey = 'nIq9l3JATYQyg179z';
  static const emailJsEndpoint = 'https://api.emailjs.com/api/v1.0/email/send';

  /// Jarak minimum antara emel pukal (had kadar EmailJS).
  static const bulkEmailSpacing = Duration(milliseconds: 1100);

  // ------------------------------------------------------------ Kapasiti/had
  static const maxCatalogPrograms = 250;
  static const maxImageBytes = 900 * 1024;
  static const maxImageDimension = 1600;
  static const pageSize = 30;
}
