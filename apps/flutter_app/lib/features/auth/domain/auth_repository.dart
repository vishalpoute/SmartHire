class AuthUser {
  const AuthUser({
    required this.uid,
    required this.email,
    required this.emailVerified,
  });
  final String uid;
  final String? email;
  final bool emailVerified;
}

class AuthFailure implements Exception {
  const AuthFailure(this.message);
  final String message;
}

abstract interface class AuthRepository {
  bool get supportsGoogle;
  Future<void> signInWithGoogle();
  Stream<AuthUser?> watchSession();
  Future<void> signIn({required String email, required String password});
  Future<void> register({required String email, required String password});
  Future<void> sendPasswordReset(String email);
  Future<void> sendVerification();
  Future<void> refreshSession();
  Future<void> signOut();
}
