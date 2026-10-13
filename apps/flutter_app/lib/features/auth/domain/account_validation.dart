abstract final class AccountValidation {
  static String? email(String? value) {
    final email = (value ?? '').trim();
    if (email.isEmpty) return 'Enter your email address';
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
      return 'Enter a valid email address';
    }
    return null;
  }

  static String? name(String? value) => (value ?? '').trim().length < 2
      ? 'Enter your name (at least 2 characters)'
      : null;

  static String? signInPassword(String? value) =>
      (value ?? '').isEmpty ? 'Enter your password' : null;

  static String? newPassword(String? value) =>
      (value ?? '').length < 8 ? 'Use at least 8 characters' : null;
}
