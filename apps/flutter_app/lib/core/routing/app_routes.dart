abstract final class AppRoutes {
  static String jobDetails(String id) => '/jobs/${Uri.encodeComponent(id)}';
  static const discover = '/';
  static const profile = '/profile';
  static const signIn = '/sign-in';
  static const register = '/register';
  static const resetPassword = '/reset-password';
}
