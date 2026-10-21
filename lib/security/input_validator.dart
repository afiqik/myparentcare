/// Pengesahan input di sisi klien. Semua peraturan penting diulang dalam
/// firestore.rules supaya tidak boleh dipintas dengan klien yang diubah suai.
class InputValidator {
  InputValidator._();

  static final _emailRegex = RegExp(
    r"^[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]+@[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,}$",
  );

  static String? validateEmail(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Email is required';
    }
    final email = value.trim();
    if (email.length > 254 || !_emailRegex.hasMatch(email)) {
      return 'Enter a valid email address';
    }
    return null;
  }

  static String? validatePhone(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Phone number is required';
    }
    final cleanPhone = value.replaceAll(RegExp(r'\D'), '');
    if (cleanPhone.length < 9 || cleanPhone.length > 12) {
      return 'Enter a valid phone number';
    }
    return null;
  }

  static String? validateMatricNo(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Matric/Student ID is required';
    }
    final trimmed = value.trim();
    if (trimmed.length < 5) {
      return 'Matric number is too short';
    }
    if (trimmed.length > 40) {
      return 'Matric number is too long';
    }
    return null;
  }

  static String? validateRequired(
    String? value,
    String fieldName, {
    int maxLength = 120,
  }) {
    if (value == null || value.trim().isEmpty) {
      return '$fieldName is required';
    }
    if (value.trim().length > maxLength) {
      return '$fieldName must be $maxLength characters or fewer';
    }
    return null;
  }

  /// Pautan video (YouTube, Google Drive atau mana-mana https).
  static String? validateVideoUrl(String? value) {
    if (value == null || value.trim().isEmpty) return 'Video link is required';
    final uri = Uri.tryParse(value.trim());
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      return 'Use a valid https:// link';
    }
    if (value.trim().length > 500) return 'Link is too long';
    return null;
  }
}
